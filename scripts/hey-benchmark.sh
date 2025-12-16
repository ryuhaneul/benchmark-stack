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

# hey 실행 (Docker 컨테이너 사용, 다중 CPU)
HEY_STATS=$(docker run --rm --network host \
    williamyeh/hey:latest \
    -n "$TOTAL_REQUESTS" -c "$CONCURRENCY" -cpus "$CPUS" \
    "$TARGET_URL" 2>&1)

echo "   ✅ 테스트 완료!"
echo ""

# 결과 파싱 (hey 기본 출력에서)
TOTAL_TIME=$(echo "$HEY_STATS" | grep "Total:" | awk '{print $2}')
RPS=$(echo "$HEY_STATS" | grep "Requests/sec:" | awk '{print $2}')
AVG_LATENCY=$(echo "$HEY_STATS" | grep "Average:" | awk '{print $2}')
FASTEST=$(echo "$HEY_STATS" | grep "Fastest:" | awk '{print $2}')
SLOWEST=$(echo "$HEY_STATS" | grep "Slowest:" | awk '{print $2}')

# 상태 코드 파싱
SUCCESS_COUNT=$(echo "$HEY_STATS" | grep "\[200\]" | awk '{print $2}' || echo "0")
if [ -z "$SUCCESS_COUNT" ]; then
    SUCCESS_COUNT=0
fi

# 에러 카운트 (200이 아닌 응답 + 연결 실패)
ERROR_LINES=$(echo "$HEY_STATS" | grep -E "^\s+\[[^2]" || true)
ERROR_COUNT=$((TOTAL_REQUESTS - SUCCESS_COUNT))
if [ "$ERROR_COUNT" -lt 0 ]; then
    ERROR_COUNT=0
fi

# 단위 변환 (초 -> ms)
convert_to_ms() {
    local val=$1
    # hey는 초 단위로 출력
    echo "$val" | awk '{printf "%.2f", $1 * 1000}'
}

AVG_LATENCY_MS=$(convert_to_ms "$AVG_LATENCY")
MIN_LATENCY_MS=$(convert_to_ms "$FASTEST")
MAX_LATENCY_MS=$(convert_to_ms "$SLOWEST")
DURATION_MS=$(convert_to_ms "$TOTAL_TIME")

RPS_INT=$(echo "$RPS" | awk '{printf "%.0f", $1}')

# 오류율 계산
if [ "$TOTAL_REQUESTS" -gt 0 ]; then
    ERROR_RATE=$(echo "scale=2; $ERROR_COUNT * 100 / $TOTAL_REQUESTS" | bc)
else
    ERROR_RATE=0
fi

# 평가 로직 (stable/warning/unstable)
# 기준: 오류율 1% 미만 & 평균응답 500ms 미만 = 안정
AVG_MS_INT=$(echo "$AVG_LATENCY_MS" | awk '{printf "%.0f", $1}')

if [ "$ERROR_COUNT" -eq 0 ] && [ "$AVG_MS_INT" -lt 500 ]; then
    STATUS="stable"
    RECOMMENDED=$((CONCURRENCY * 3 / 2))
    RECOMMENDATION="✅ ${CONCURRENCY}명 동시 접속 테스트 통과! 더 높은 동시 접속(${RECOMMENDED}명)으로 테스트해보세요."
elif [ "$ERROR_COUNT" -lt $((TOTAL_REQUESTS / 20)) ] && [ "$AVG_MS_INT" -lt 2000 ]; then
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
echo "   총 요청: $TOTAL_REQUESTS"
echo "   성공/실패: $SUCCESS_COUNT / $ERROR_COUNT"
echo "   오류율: ${ERROR_RATE}%"
echo "   RPS: $RPS_INT"
echo "   응답시간: avg ${AVG_LATENCY_MS}ms / min ${MIN_LATENCY_MS}ms / max ${MAX_LATENCY_MS}ms"
echo "   소요 시간: ${TOTAL_TIME}s (${DURATION_MS}ms)"
echo ""
echo "📋 평가: $STATUS"
echo "   $RECOMMENDATION"
echo ""

# API로 결과 전송
echo "💾 결과를 DB에 저장 중..."

JSON_PAYLOAD=$(cat <<EOF
{
    "test_type": "CONCURRENT_EXTERNAL",
    "iterations": $TOTAL_REQUESTS,
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
            "max": $MAX_LATENCY_MS
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
