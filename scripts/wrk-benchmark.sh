#!/bin/bash
# wrk-benchmark.sh - wrk 벤치마크 실행 후 결과를 API로 자동 저장
#
# 사용법: 
#   ./wrk-benchmark.sh <TARGET_URL> [THREADS] [CONNECTIONS] [DURATION]
#
# 예시:
#   ./wrk-benchmark.sh http://example.com/health
#   ./wrk-benchmark.sh http://example.com/health 4 500 10s
#   ./wrk-benchmark.sh http://example.com/api/items 8 1000 30s
#
# 매개변수:
#   TARGET_URL   - 테스트 대상 URL (필수)
#   THREADS      - wrk 스레드 수 (기본값: 4)
#   CONNECTIONS  - 동시 연결 수 (기본값: 500)
#   DURATION     - 테스트 시간 (기본값: 5s)
#
# 결과는 TARGET_URL의 호스트로 API 요청을 보내 DB에 저장됩니다.

set -e

# 매개변수
TARGET_URL="${1:-}"
THREADS="${2:-4}"
CONNECTIONS="${3:-500}"
DURATION="${4:-5s}"

# TARGET_URL 필수 확인
if [ -z "$TARGET_URL" ]; then
    echo "❌ 오류: TARGET_URL이 필요합니다."
    echo ""
    echo "사용법: $0 <TARGET_URL> [THREADS] [CONNECTIONS] [DURATION]"
    echo "예시:   $0 http://example.com/health 4 500 10s"
    exit 1
fi

# TARGET_URL에서 API_BASE 자동 추출
API_BASE=$(echo "$TARGET_URL" | sed -E 's|(https?://[^/]+).*|\1|')

# 대상 엔드포인트 추출
TARGET_ENDPOINT=$(echo "$TARGET_URL" | sed -E 's|https?://[^/]+||')
if [ -z "$TARGET_ENDPOINT" ]; then
    TARGET_ENDPOINT="/"
fi

echo "🚀 wrk 벤치마크 시작..."
echo "   대상: $TARGET_URL"
echo "   스레드: $THREADS, 연결: $CONNECTIONS, 시간: $DURATION"
echo ""

# DURATION에서 숫자만 추출 (10s -> 10)
DURATION_NUM=$(echo "$DURATION" | sed 's/[^0-9]//g')

# 진행 표시기 함수
show_progress() {
    local duration=$1
    local spinner='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    local elapsed=0
    
    while [ $elapsed -lt $duration ]; do
        local spin_char="${spinner:i%10:1}"
        printf "\r   $spin_char 진행 중... %ds / %ds" "$elapsed" "$duration"
        sleep 1
        elapsed=$((elapsed + 1))
        i=$((i + 1))
    done
    printf "\r   ✅ wrk 테스트 완료!        \n"
}

# 진행 표시기를 백그라운드에서 실행
show_progress "$DURATION_NUM" &
PROGRESS_PID=$!

# wrk 실행 및 결과 캡처
WRK_OUTPUT=$(wrk -t$THREADS -c$CONNECTIONS -d$DURATION "$TARGET_URL" 2>&1)

# 진행 표시기 종료
kill $PROGRESS_PID 2>/dev/null || true
wait $PROGRESS_PID 2>/dev/null || true
printf "\r   ✅ wrk 테스트 완료!        \n"

echo ""
echo "$WRK_OUTPUT"
echo ""

# 결과 파싱
REQUESTS=$(echo "$WRK_OUTPUT" | grep "requests in" | awk '{print $1}')
DURATION_SEC=$(echo "$WRK_OUTPUT" | grep "requests in" | awk '{print $4}' | sed 's/s,//')
RPS=$(echo "$WRK_OUTPUT" | grep "Requests/sec:" | awk '{print $2}')
AVG_LATENCY=$(echo "$WRK_OUTPUT" | grep "Latency" | awk '{print $2}')
MAX_LATENCY=$(echo "$WRK_OUTPUT" | grep "Latency" | awk '{print $4}')
TIMEOUTS=$(echo "$WRK_OUTPUT" | grep "timeout" | awk '{print $NF}' || echo "0")
SOCKET_ERRORS=$(echo "$WRK_OUTPUT" | grep "Socket errors" || echo "none")

# 단위 변환 (ms로)
convert_to_ms() {
    local val=$1
    if [[ $val == *"us"* ]]; then
        echo "$val" | sed 's/us//' | awk '{printf "%.2f", $1/1000}'
    elif [[ $val == *"ms"* ]]; then
        echo "$val" | sed 's/ms//'
    elif [[ $val == *"s"* ]]; then
        echo "$val" | sed 's/s//' | awk '{printf "%.2f", $1*1000}'
    else
        echo "$val"
    fi
}

AVG_LATENCY_MS=$(convert_to_ms "$AVG_LATENCY")
MAX_LATENCY_MS=$(convert_to_ms "$MAX_LATENCY")
DURATION_MS=$(echo "$DURATION_SEC" | awk '{printf "%.0f", $1*1000}')
RPS_INT=$(echo "$RPS" | awk '{printf "%.0f", $1}')

if [ -z "$TIMEOUTS" ] || [ "$TIMEOUTS" == "0" ]; then
    TIMEOUTS=0
fi

# 오류율 계산
if [ -n "$REQUESTS" ] && [ "$REQUESTS" -gt 0 ]; then
    ERROR_RATE=$(echo "scale=2; $TIMEOUTS * 100 / $REQUESTS" | bc)
else
    ERROR_RATE=0
fi

# 평가 로직 (stable/warning/unstable)
# 기준: 오류율 1% 미만 & 평균응답 500ms 미만 = 안정
AVG_MS_INT=$(echo "$AVG_LATENCY_MS" | awk '{printf "%.0f", $1}')

if [ "$TIMEOUTS" -eq 0 ] && [ "$AVG_MS_INT" -lt 500 ]; then
    STATUS="stable"
    RECOMMENDED=$((CONNECTIONS * 3 / 2))
    RECOMMENDATION="✅ ${CONNECTIONS}명 동시 접속 테스트 통과! 더 높은 동시 접속(${RECOMMENDED}명)으로 테스트해보세요."
elif [ "$TIMEOUTS" -lt $((REQUESTS / 20)) ] && [ "$AVG_MS_INT" -lt 2000 ]; then
    STATUS="warning"
    RECOMMENDATION="⚠️ ${CONNECTIONS}명 동시 접속에서 약간의 지연이 있습니다. 현재 수준이 상한선일 수 있습니다."
else
    STATUS="unstable"
    SUGGESTED=$((CONNECTIONS * 7 / 10))
    RECOMMENDATION="❌ ${CONNECTIONS}명 동시 접속에서 성능 저하가 발생했습니다. ${SUGGESTED}명 이하로 줄여서 테스트해보세요."
fi

echo "📊 테스트 결과:"
echo "   대상: $TARGET_ENDPOINT"
echo "   동시 접속: ${CONNECTIONS}명 (스레드: $THREADS)"
echo "   총 요청: $REQUESTS"
echo "   RPS: $RPS_INT"
echo "   평균 응답: ${AVG_LATENCY_MS}ms / 최대: ${MAX_LATENCY_MS}ms"
echo "   타임아웃: $TIMEOUTS (오류율: ${ERROR_RATE}%)"
echo ""
echo "📋 평가: $STATUS"
echo "   $RECOMMENDATION"
echo ""

# API로 결과 전송
echo "💾 결과를 DB에 저장 중..."

JSON_PAYLOAD=$(cat <<EOF
{
    "test_type": "WRK_EXTERNAL",
    "iterations": $REQUESTS,
    "duration_ms": $DURATION_MS,
    "throughput": $RPS_INT,
    "details": {
        "tool": "wrk",
        "threads": $THREADS,
        "connections": $CONNECTIONS,
        "duration": "$DURATION",
        "targetEndpoint": "$TARGET_ENDPOINT",
        "avgLatency": "$AVG_LATENCY",
        "avgLatencyMs": $AVG_LATENCY_MS,
        "maxLatency": "$MAX_LATENCY",
        "maxLatencyMs": $MAX_LATENCY_MS,
        "timeouts": $TIMEOUTS,
        "errorRate": $ERROR_RATE,
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
