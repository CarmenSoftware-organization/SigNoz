#!/bin/sh
# ยิง trace ปลอม 1 span เข้า OTLP/HTTP เพื่อพิสูจน์เส้นทาง
# ingester -> ClickHouse -> query -> UI ว่าทำงานครบทั้งเส้น
#
# ใช้: ./smoke-test/send-trace.sh [endpoint]
#      ./smoke-test/send-trace.sh http://192.168.1.50:4318
set -eu

ENDPOINT="${1:-http://localhost:4318}"

NOW_NS=$(( $(date +%s) * 1000000000 ))
START_NS=$(( NOW_NS - 500000000 ))
TRACE_ID=$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')
SPAN_ID=$(head -c 8 /dev/urandom | od -An -tx1 | tr -d ' \n')

echo "ส่ง trace ไปที่ ${ENDPOINT}/v1/traces"
echo "  service.name = smoke-test"
echo "  trace_id     = ${TRACE_ID}"

HTTP_CODE=$(curl -sS -o /tmp/signoz-smoke-resp.json -w '%{http_code}' \
  -X POST "${ENDPOINT}/v1/traces" \
  -H 'Content-Type: application/json' \
  -d "{
  \"resourceSpans\": [{
    \"resource\": {
      \"attributes\": [
        {\"key\": \"service.name\", \"value\": {\"stringValue\": \"smoke-test\"}},
        {\"key\": \"deployment.environment\", \"value\": {\"stringValue\": \"dev\"}}
      ]
    },
    \"scopeSpans\": [{
      \"scope\": {\"name\": \"manual-smoke-test\"},
      \"spans\": [{
        \"traceId\": \"${TRACE_ID}\",
        \"spanId\": \"${SPAN_ID}\",
        \"name\": \"smoke-test-span\",
        \"kind\": 2,
        \"startTimeUnixNano\": \"${START_NS}\",
        \"endTimeUnixNano\": \"${NOW_NS}\",
        \"status\": {\"code\": 1}
      }]
    }]
  }]
}")

echo "HTTP ${HTTP_CODE}"
cat /tmp/signoz-smoke-resp.json
echo

if [ "${HTTP_CODE}" != "200" ]; then
  echo "ไม่ผ่าน: คาดหวัง HTTP 200" >&2
  exit 1
fi

echo
echo "ส่งสำเร็จ ต่อไปให้เปิด SigNoz UI -> Services"
echo "ควรเห็น service ชื่อ 'smoke-test' ภายใน ~30 วินาที"
