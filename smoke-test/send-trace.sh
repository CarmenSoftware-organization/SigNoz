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

RESP_BODY=$(mktemp)
trap 'rm -f "$RESP_BODY"' EXIT

echo "ส่ง trace ไปที่ ${ENDPOINT}/v1/traces"
echo "  service.name = smoke-test"
echo "  trace_id     = ${TRACE_ID}"

# ต้องมี || HTTP_CODE=000 ไม่งั้น set -e จะฆ่า script ทันทีที่ curl ต่อไม่ติด
# ซึ่งเป็นอาการที่เจอบ่อยที่สุดตอน stack ยังไม่ได้สร้าง admin account
HTTP_CODE=$(curl -sS -o "$RESP_BODY" -w '%{http_code}' \
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
}") || HTTP_CODE=000

echo "HTTP ${HTTP_CODE}"
cat "$RESP_BODY"
echo

if [ "${HTTP_CODE}" = "000" ]; then
  cat >&2 <<'MSG'

ไม่ผ่าน: ต่อ endpoint ไม่ได้เลย ไม่ได้รับ HTTP status กลับมา

สาเหตุที่พบบ่อยที่สุดคือยังไม่ได้สร้าง admin account ของ SigNoz
collector ตัวนี้รับ config จาก OpAMP server ที่ฝังอยู่ใน signoz
ตราบใดที่ยังไม่มี organization มันจะรัน no-op pipeline
และไม่มีอะไร listen บน 4317/4318 เลย

แก้: เปิด SigNoz UI แล้วสมัคร admin หรือเรียก API
  curl -X POST <signoz-url>/api/v1/register -H 'Content-Type: application/json' \
    -d '{"email":"...","password":"...","orgName":"...","name":"..."}'

เช็คสถานะ: curl -sS <signoz-url>/api/v1/version แล้วดูฟิลด์ setupCompleted
รอประมาณ 30 วินาทีหลังสมัครเสร็จ แล้วรัน script นี้ใหม่

ถ้า setupCompleted เป็น true อยู่แล้ว ให้ตรวจว่า container ingester ขึ้นจริง
และ port ถูก publish ออกมาที่ host หรือไม่
MSG
  exit 1
fi

if [ "${HTTP_CODE}" != "200" ]; then
  echo "ไม่ผ่าน: คาดหวัง HTTP 200 แต่ได้ ${HTTP_CODE}" >&2
  exit 1
fi

echo
echo "ส่งสำเร็จ ต่อไปให้เปิด SigNoz UI -> Services"
echo "ควรเห็น service ชื่อ 'smoke-test' ภายใน ~30 วินาที"
