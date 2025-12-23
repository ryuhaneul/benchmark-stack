#!/bin/bash
# hey-benchmark.sh - hey 벤치마크 (Docker 컨테이너 사용) 실행 후 결과를 API로 자동 저장
#
# 사용법:
#   ./hey-benchmark.sh <TARGET_URL> [TOTAL_REQUESTS] [CONCURRENCY] [CPUS]
#
# 예시:
#   ./hey-benchmark.sh http://example.com/health
#   ./hey-benchmark.sh http://example.com/health 5000 500
#   ./hey-benchmark.sh http://example.com/health 5000 500 4
#
# 매개변수:
#   TARGET_URL      - 테스트 대상 URL (필수)
#   TOTAL_REQUESTS  - 총 요청 수 (기본값: 5000)
#   CONCURRENCY     - 동시 연결 수 (기본값: 500)
#   CPUS            - 사용할 CPU 코어 수 (기본값: 4)
#
# 결과는 TARGET_URL의 호스트로 API 요청을 보내 DB에 저장됩니다.

set -e

# 매개변수
TARGET_URL="${1:-}"
TOTAL_REQUESTS="${2:-5000}"
CONCURRENCY="${3:-500}"
CPUS="${4:-4}"

# TARGET_URL 필수 확인
if [ -z "$TARGET_URL" ]; then
    echo "❌ 오류: TARGET_URL이 필요합니다."
    echo ""
    echo "사용법: $0 <TARGET_URL> [TOTAL_REQUESTS] [CONCURRENCY] [CPUS]"
    echo "예시:   $0 http://example.com/health 5000 500 4"
    exit 1
fi

# TARGET_URL에서 API_BASE 자동 추출
API_BASE=$(echo "$TARGET_URL" | sed -E 's|(https?://[^/]+).*|\1|')

# 대상 엔드포인트 추출
TARGET_ENDPOINT=$(echo "$TARGET_URL" | sed -E 's|https?://[^/]+||')
if [ -z "$TARGET_ENDPOINT" ]; then
    TARGET_ENDPOINT="/"
fi

echo "🚀 hey 벤치마크 시작 (Docker 컨테이너)..."
echo "   대상: $TARGET_URL"
echo "   총 요청: $TOTAL_REQUESTS, 동시 접속: $CONCURRENCY, CPU: ${CPUS}코어"
echo ""

# 진행 표시
echo "   ⏳ 테스트 진행 중... (완료까지 대기)"

# hey 실행 (CSV 출력으로 raw 데이터 수집)
HEY_CSV=$(docker run --rm --network host \
    williamyeh/hey:latest \
    -n "$TOTAL_REQUESTS" -c "$CONCURRENCY" -cpus "$CPUS" -o csv \
    "$TARGET_URL" 2>&1)

echo "   ✅ 테스트 완료!"
echo ""

# CSV 데이터에서 응답시간 추출 및 정렬 (첫 번째 컬럼, 초 단위)
# 헤더 제외하고 response-time 컬럼만 추출
RESPONSE_TIMES=$(echo "$HEY_CSV" | tail -n +2 | cut -d',' -f1 | sort -n)
TOTAL_COUNT=$(echo "$RESPONSE_TIMES" | wc -l | tr -d ' ')

# 빈 응답 체크
if [ "$TOTAL_COUNT" -eq 0 ] || [ -z "$RESPONSE_TIMES" ]; then
    echo "❌ 오류: 응답 데이터가 없습니다."
    exit 1
fi

# 성공/실패 카운트 (status-code 컬럼, 7번째)
# set -e 충돌 방지를 위해 서브쉘에서 처리
SUCCESS_COUNT=$(echo "$HEY_CSV" | tail -n +2 | cut -d',' -f7 | { grep -c "200" || true; })
if [ -z "$SUCCESS_COUNT" ]; then
    SUCCESS_COUNT=0
fi
ERROR_COUNT=$((TOTAL_COUNT - SUCCESS_COUNT))
if [ "$ERROR_COUNT" -lt 0 ]; then
    ERROR_COUNT=0
fi

# 통계 계산 함수 (초 -> ms)
convert_to_ms() {
    echo "$1" | awk '{printf "%.2f", $1 * 1000}'
}

# 기본 통계
MIN_SEC=$(echo "$RESPONSE_TIMES" | head -1)
MAX_SEC=$(echo "$RESPONSE_TIMES" | tail -1)
AVG_SEC=$(echo "$RESPONSE_TIMES" | awk '{sum+=$1} END {printf "%.6f", sum/NR}')

# 퍼센타일 계산 (인덱스 기반, 1-indexed)
calc_percentile() {
    local pct=$1
    local idx=$(( (TOTAL_COUNT * pct + 99) / 100 ))  # 올림 처리
    if [ "$idx" -lt 1 ]; then idx=1; fi
    if [ "$idx" -gt "$TOTAL_COUNT" ]; then idx=$TOTAL_COUNT; fi
    echo "$RESPONSE_TIMES" | sed -n "${idx}p"
}

P50_SEC=$(calc_percentile 50)
P95_SEC=$(calc_percentile 95)
P99_SEC=$(calc_percentile 99)

# ms로 변환
MIN_LATENCY_MS=$(convert_to_ms "$MIN_SEC")
MAX_LATENCY_MS=$(convert_to_ms "$MAX_SEC")
AVG_LATENCY_MS=$(convert_to_ms "$AVG_SEC")
P50_MS=$(convert_to_ms "$P50_SEC")
P95_MS=$(convert_to_ms "$P95_SEC")
P99_MS=$(convert_to_ms "$P99_SEC")

# RPS 계산 (실제 테스트 소요시간 기반)
# CSV의 offset(8번째) + response-time(1번째) 중 최대값 = 실제 총 소요시간
DURATION_SEC=$(echo "$HEY_CSV" | tail -n +2 | awk -F',' '{print $8 + $1}' | sort -n | tail -1)
if [ -z "$DURATION_SEC" ] || [ "$DURATION_SEC" = "0" ]; then
    # 폴백: 응답시간 합계 / 동시성
    DURATION_SEC=$(echo "$RESPONSE_TIMES" | awk -v c="$CONCURRENCY" '{sum+=$1} END {printf "%.4f", sum/c}')
fi
DURATION_MS=$(convert_to_ms "$DURATION_SEC")

RPS=$(echo "$TOTAL_COUNT $DURATION_SEC" | awk '{if($2>0) printf "%.2f", $1/$2; else print "0"}')
RPS_INT=$(echo "$RPS" | awk '{printf "%.0f", $1}')

# 오류율 계산
if [ "$TOTAL_COUNT" -gt 0 ]; then
    ERROR_RATE=$(echo "scale=2; $ERROR_COUNT * 100 / $TOTAL_COUNT" | bc)
else
    ERROR_RATE=0
fi

# 평가 로직 (stable/warning/unstable)
# 기준:
#   안정: 에러=0 && avg<500ms && P95<1000ms && max<3000ms
#   주의: 에러<5% && avg<2000ms && max<5000ms
#   불안정: 그 외
AVG_MS_INT=$(echo "$AVG_LATENCY_MS" | awk '{printf "%.0f", $1}')
P95_MS_INT=$(echo "$P95_MS" | awk '{printf "%.0f", $1}')
MAX_MS_INT=$(echo "$MAX_LATENCY_MS" | awk '{printf "%.0f", $1}')

if [ "$ERROR_COUNT" -eq 0 ] && [ "$AVG_MS_INT" -lt 500 ] && [ "$P95_MS_INT" -lt 1000 ] && [ "$MAX_MS_INT" -lt 3000 ]; then
    STATUS="stable"
    RECOMMENDED=$((CONCURRENCY * 3 / 2))
    RECOMMENDATION="✅ ${CONCURRENCY}명 동시 접속 테스트 통과! 더 높은 동시 접속(${RECOMMENDED}명)으로 테스트해보세요."
elif [ "$ERROR_COUNT" -lt $((TOTAL_COUNT / 20)) ] && [ "$AVG_MS_INT" -lt 2000 ] && [ "$MAX_MS_INT" -lt 5000 ]; then
    STATUS="warning"
    RECOMMENDATION="⚠️ ${CONCURRENCY}명 동시 접속에서 약간의 지연이 있습니다. 현재 수준이 안정적인 상한선일 수 있습니다."
else
    STATUS="unstable"
    SUGGESTED=$((CONCURRENCY * 7 / 10))
    RECOMMENDATION="❌ ${CONCURRENCY}명 동시 접속에서 성능 저하가 발생했습니다. ${SUGGESTED}명 이하로 줄여서 테스트해보세요."
fi

echo "📊 테스트 결과:"
echo "   대상: $TARGET_ENDPOINT"
echo "   동시 접속: ${CONCURRENCY}명"
echo "   총 요청: $TOTAL_COUNT"
echo "   성공/실패: $SUCCESS_COUNT / $ERROR_COUNT"
echo "   오류율: ${ERROR_RATE}%"
echo "   RPS: $RPS_INT"
echo "   응답시간: avg ${AVG_LATENCY_MS}ms / min ${MIN_LATENCY_MS}ms / max ${MAX_LATENCY_MS}ms"
echo "   퍼센타일: P50 ${P50_MS}ms / P95 ${P95_MS}ms / P99 ${P99_MS}ms"
echo "   소요 시간: ${DURATION_SEC}s (${DURATION_MS}ms)"
echo ""
echo "📋 평가: $STATUS"
echo "   $RECOMMENDATION"
echo ""

# API로 결과 전송
echo "💾 결과를 DB에 저장 중..."

JSON_PAYLOAD=$(cat <<EOF
{
    "test_type": "CONCURRENT_EXTERNAL",
    "iterations": $TOTAL_COUNT,
    "duration_ms": ${DURATION_MS%.*},
    "throughput": $RPS_INT,
    "details": {
        "tool": "hey",
        "concurrency": $CONCURRENCY,
        "targetEndpoint": "$TARGET_ENDPOINT",
        "successCount": $SUCCESS_COUNT,
        "failCount": $ERROR_COUNT,
        "errorRate": $ERROR_RATE,
        "responseTime": {
            "avg": $AVG_LATENCY_MS,
            "min": $MIN_LATENCY_MS,
            "max": $MAX_LATENCY_MS,
            "p50": $P50_MS,
            "p95": $P95_MS,
            "p99": $P99_MS
        },
        "status": "$STATUS",
        "recommendation": "$RECOMMENDATION"
    }
}
EOF
)

RESPONSE=$(curl -s -X POST "${API_BASE}/api/performance/result" \
    -H "Content-Type: application/json" \
    -d "$JSON_PAYLOAD")

echo "✅ 저장 완료!"
