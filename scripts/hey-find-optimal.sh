#!/bin/bash
# hey-find-optimal.sh - 적정 동시 접속자 수를 자동으로 찾는 스크립트
#
# 사용법:
#   ./hey-find-optimal.sh <TARGET_URL> [TOTAL_REQUESTS] [CONCURRENCY] [CPUS]
#
# 예시:
#   ./hey-find-optimal.sh http://example.com/health
#   ./hey-find-optimal.sh http://example.com/health 5000 500
#   ./hey-find-optimal.sh http://example.com/health 5000 500 4
#
# 매개변수:
#   TARGET_URL      - 테스트 대상 URL (필수)
#   TOTAL_REQUESTS  - 테스트당 요청 수 (기본값: 5000)
#   CONCURRENCY     - 탐색 시작 동시 접속 수 (기본값: 500)
#   CPUS            - 사용할 CPU 코어 수 (기본값: 4)
#
# 동작 방식:
#   - unstable/warning: 70%로 줄여서 재시도 (기존 권장값과 동일)
#   - stable: 150%로 올려서 상한선 탐색
#   - stable 값을 찾을 때까지 반복

set -e

# 매개변수 (hey-benchmark.sh와 동일)
TARGET_URL="${1:-}"
TOTAL_REQUESTS="${2:-5000}"
START_CONCURRENCY="${3:-500}"
CPUS="${4:-4}"

# 평가 기준 (hey-benchmark.sh와 동일)
MAX_AVG_MS=500
MAX_P95_MS=1000
MAX_MAX_MS=3000

# TARGET_URL 필수 확인
if [ -z "$TARGET_URL" ]; then
    echo "❌ 오류: TARGET_URL이 필요합니다."
    echo ""
    echo "사용법: $0 <TARGET_URL> [TOTAL_REQUESTS] [CONCURRENCY] [CPUS]"
    echo "예시:   $0 http://example.com/health 5000 500 4"
    exit 1
fi

echo "🔍 적정 동시 접속자 수 탐색 시작"
echo "   대상: $TARGET_URL"
echo "   요청 수: ${TOTAL_REQUESTS}, 시작: ${START_CONCURRENCY}명, CPU: ${CPUS}코어"
echo "   평가 기준: avg<${MAX_AVG_MS}ms && P95<${MAX_P95_MS}ms && max<${MAX_MAX_MS}ms"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 결과 저장용 배열
declare -a RESULTS

# 테스트 함수
run_test() {
    local concurrency=$1
    
    # hey 실행 (CSV 출력)
    local HEY_CSV=$(docker run --rm --network host \
        williamyeh/hey:latest \
        -n "$TOTAL_REQUESTS" -c "$concurrency" -cpus "$CPUS" -o csv \
        "$TARGET_URL" 2>&1)
    
    # 응답 시간 추출 및 정렬
    RESPONSE_TIMES=$(echo "$HEY_CSV" | tail -n +2 | cut -d',' -f1 | sort -n)
    TOTAL_COUNT=$(echo "$RESPONSE_TIMES" | wc -l | tr -d ' ')
    
    if [ "$TOTAL_COUNT" -eq 0 ]; then
        echo "ERROR"
        return
    fi
    
    # 통계 계산
    MAX_SEC=$(echo "$RESPONSE_TIMES" | tail -1)
    AVG_SEC=$(echo "$RESPONSE_TIMES" | awk '{sum+=$1} END {printf "%.6f", sum/NR}')
    
    # 퍼센타일 계산
    local P95_IDX=$(( (TOTAL_COUNT * 95 + 99) / 100 ))
    [ "$P95_IDX" -lt 1 ] && P95_IDX=1
    [ "$P95_IDX" -gt "$TOTAL_COUNT" ] && P95_IDX=$TOTAL_COUNT
    P95_SEC=$(echo "$RESPONSE_TIMES" | sed -n "${P95_IDX}p")
    
    local P99_IDX=$(( (TOTAL_COUNT * 99 + 99) / 100 ))
    [ "$P99_IDX" -lt 1 ] && P99_IDX=1
    [ "$P99_IDX" -gt "$TOTAL_COUNT" ] && P99_IDX=$TOTAL_COUNT
    P99_SEC=$(echo "$RESPONSE_TIMES" | sed -n "${P99_IDX}p")
    
    # ms로 변환
    AVG_MS=$(echo "$AVG_SEC" | awk '{printf "%.0f", $1 * 1000}')
    MAX_MS=$(echo "$MAX_SEC" | awk '{printf "%.0f", $1 * 1000}')
    P95_MS=$(echo "$P95_SEC" | awk '{printf "%.0f", $1 * 1000}')
    P99_MS=$(echo "$P99_SEC" | awk '{printf "%.0f", $1 * 1000}')
    
    # RPS 계산
    DURATION_SEC=$(echo "$HEY_CSV" | tail -n +2 | awk -F',' '{print $8 + $1}' | sort -n | tail -1)
    RPS=$(echo "$TOTAL_COUNT $DURATION_SEC" | awk '{if($2>0) printf "%.0f", $1/$2; else print "0"}')
    
    # 성공/에러 카운트
    SUCCESS_COUNT=$(echo "$HEY_CSV" | tail -n +2 | cut -d',' -f7 | { grep -c "200" || true; })
    ERROR_COUNT=$((TOTAL_COUNT - SUCCESS_COUNT))
    
    # 평가
    if [ "$ERROR_COUNT" -eq 0 ] && [ "$AVG_MS" -lt "$MAX_AVG_MS" ] && [ "$P95_MS" -lt "$MAX_P95_MS" ] && [ "$MAX_MS" -lt "$MAX_MAX_MS" ]; then
        STATUS="stable"
    elif [ "$ERROR_COUNT" -lt $((TOTAL_COUNT / 20)) ] && [ "$AVG_MS" -lt 2000 ] && [ "$MAX_MS" -lt 5000 ]; then
        STATUS="warning"
    else
        STATUS="unstable"
    fi
    
    # 결과 반환 (파이프로 전달하기 위해 echo)
    echo "$RPS|$AVG_MS|$P95_MS|$P99_MS|$MAX_MS|$ERROR_COUNT|$STATUS"
}

CURRENT_CONCURRENCY=$START_CONCURRENCY
TEST_COUNT=0
MAX_TESTS=15  # 무한 루프 방지
DIRECTION="unknown"  # down, up, or fine-tuning

OPTIMAL_CONCURRENCY=0
OPTIMAL_RPS=0
LAST_STABLE_CONCURRENCY=0
LAST_UNSTABLE_CONCURRENCY=0

while [ "$TEST_COUNT" -lt "$MAX_TESTS" ] && [ "$CURRENT_CONCURRENCY" -gt 0 ]; do
    TEST_COUNT=$((TEST_COUNT + 1))
    echo ""
    echo "📊 테스트 #${TEST_COUNT}: 동시 접속 ${CURRENT_CONCURRENCY}명"
    echo "   ⏳ 진행 중..."
    
    RESULT=$(run_test "$CURRENT_CONCURRENCY")
    
    if [ "$RESULT" = "ERROR" ]; then
        echo "   ❌ 응답 없음, 건너뜀"
        CURRENT_CONCURRENCY=$((CURRENT_CONCURRENCY * 7 / 10))
        continue
    fi
    
    IFS='|' read -r RPS AVG_MS P95_MS P99_MS MAX_MS ERROR_COUNT STATUS <<< "$RESULT"
    
    # 상태 표시
    case "$STATUS" in
        "stable")   STATUS_ICON="✅" ;;
        "warning")  STATUS_ICON="⚠️" ;;
        "unstable") STATUS_ICON="❌" ;;
    esac
    
    echo "   RPS: $RPS | avg: ${AVG_MS}ms | P95: ${P95_MS}ms | max: ${MAX_MS}ms | ${STATUS_ICON} ${STATUS}"
    
    # 결과 저장
    RESULTS+=("$CURRENT_CONCURRENCY|$RPS|$AVG_MS|$P95_MS|$MAX_MS|${STATUS_ICON} ${STATUS}")
    
    # 다음 테스트 결정
    if [ "$STATUS" = "stable" ]; then
        LAST_STABLE_CONCURRENCY=$CURRENT_CONCURRENCY
        OPTIMAL_CONCURRENCY=$CURRENT_CONCURRENCY
        OPTIMAL_RPS=$RPS
        
        if [ "$DIRECTION" = "unknown" ]; then
            # 첫 테스트가 stable → 상향 탐색
            DIRECTION="up"
            echo "   🔼 첫 테스트 안정! 상한선 탐색을 위해 상향..."
            NEXT=$((CURRENT_CONCURRENCY * 3 / 2))  # 150%
        elif [ "$DIRECTION" = "down" ]; then
            # 하향 중 stable 찾음 → 상한선 정밀 탐색
            if [ "$LAST_UNSTABLE_CONCURRENCY" -gt 0 ]; then
                # 마지막 unstable과 현재 stable 사이 중간값 테스트
                MIDDLE=$(( (LAST_UNSTABLE_CONCURRENCY + CURRENT_CONCURRENCY) / 2 ))
                if [ "$MIDDLE" -gt "$CURRENT_CONCURRENCY" ] && [ "$MIDDLE" -lt "$LAST_UNSTABLE_CONCURRENCY" ]; then
                    DIRECTION="fine-tuning"
                    echo "   🎯 stable 발견! 정밀 탐색: ${CURRENT_CONCURRENCY}~${LAST_UNSTABLE_CONCURRENCY} 사이"
                    NEXT=$MIDDLE
                else
                    echo "   🎯 최적값 확정!"
                    break
                fi
            else
                echo "   🎯 최적값 확정!"
                break
            fi
        elif [ "$DIRECTION" = "up" ]; then
            # 상향 중 계속 stable → 더 올리기
            NEXT=$((CURRENT_CONCURRENCY * 3 / 2))
        elif [ "$DIRECTION" = "fine-tuning" ]; then
            # 정밀 탐색 중 stable → 더 올려보기
            if [ "$LAST_UNSTABLE_CONCURRENCY" -gt 0 ]; then
                MIDDLE=$(( (LAST_UNSTABLE_CONCURRENCY + CURRENT_CONCURRENCY) / 2 ))
                if [ "$MIDDLE" -gt "$CURRENT_CONCURRENCY" ] && [ "$((MIDDLE - CURRENT_CONCURRENCY))" -gt 10 ]; then
                    NEXT=$MIDDLE
                else
                    echo "   🎯 최적값 확정!"
                    break
                fi
            else
                break
            fi
        fi
    else
        # unstable 또는 warning
        LAST_UNSTABLE_CONCURRENCY=$CURRENT_CONCURRENCY
        
        if [ "$DIRECTION" = "unknown" ] || [ "$DIRECTION" = "down" ]; then
            # 하향 탐색 계속
            DIRECTION="down"
            NEXT=$((CURRENT_CONCURRENCY * 7 / 10))  # 70% (기존 권장값과 동일)
            echo "   🔽 ${NEXT}명으로 재시도..."
        elif [ "$DIRECTION" = "up" ]; then
            # 상향 중 unstable → 정밀 탐색으로 전환
            if [ "$LAST_STABLE_CONCURRENCY" -gt 0 ]; then
                DIRECTION="fine-tuning"
                MIDDLE=$(( (CURRENT_CONCURRENCY + LAST_STABLE_CONCURRENCY) / 2 ))
                echo "   🎯 상한선 발견! 정밀 탐색: ${LAST_STABLE_CONCURRENCY}~${CURRENT_CONCURRENCY} 사이"
                NEXT=$MIDDLE
            else
                NEXT=$((CURRENT_CONCURRENCY * 7 / 10))
            fi
        elif [ "$DIRECTION" = "fine-tuning" ]; then
            # 정밀 탐색 중 unstable → 더 내려가기
            if [ "$LAST_STABLE_CONCURRENCY" -gt 0 ]; then
                MIDDLE=$(( (CURRENT_CONCURRENCY + LAST_STABLE_CONCURRENCY) / 2 ))
                if [ "$MIDDLE" -lt "$CURRENT_CONCURRENCY" ] && [ "$((CURRENT_CONCURRENCY - MIDDLE))" -gt 10 ]; then
                    NEXT=$MIDDLE
                else
                    echo "   🎯 최적값 확정: ${LAST_STABLE_CONCURRENCY}명"
                    OPTIMAL_CONCURRENCY=$LAST_STABLE_CONCURRENCY
                    break
                fi
            else
                break
            fi
        fi
    fi
    
    CURRENT_CONCURRENCY=$NEXT
    
    # 테스트 간 쿨다운
    sleep 2
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📋 테스트 결과 요약"
echo ""
printf "%-12s %-8s %-10s %-10s %-12s %-12s\n" "동시접속" "RPS" "avg(ms)" "P95(ms)" "max(ms)" "평가"
echo "────────────────────────────────────────────────────────────"
for result in "${RESULTS[@]}"; do
    IFS='|' read -r conc rps avg p95 max status <<< "$result"
    printf "%-12s %-8s %-10s %-10s %-12s %-12s\n" "${conc}명" "$rps" "$avg" "$p95" "$max" "$status"
done
echo ""

if [ "$OPTIMAL_CONCURRENCY" -gt 0 ]; then
    echo "🎯 권장 동시 접속 수: ${OPTIMAL_CONCURRENCY}명 (RPS: ${OPTIMAL_RPS})"
    echo "   (avg<${MAX_AVG_MS}ms, P95<${MAX_P95_MS}ms, max<${MAX_MAX_MS}ms 기준)"
else
    echo "⚠️ 안정적인 동시 접속 수를 찾지 못했습니다."
    echo "   더 낮은 동시 접속 수로 시작하거나, 서버 성능을 점검하세요."
fi
echo ""
