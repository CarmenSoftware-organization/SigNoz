# OTel conventions ของ Carmen

ค่าคงที่ทุกตัวที่เฟส 1-4 ต้องใช้ **อ่านจากที่นี่ที่เดียว ห้าม hardcode ซ้ำที่อื่น**

ที่มา: `docs/superpowers/specs/2026-08-23-carmen-otel-instrumentation-design.md`
ตัวเลขที่วัดได้: `docs/dev-host-facts.md`

## Endpoint

| env var | ค่า | ใช้กับ |
|---|---|---|
| `OTEL_EXPORTER_OTLP_ENDPOINT` | `http://dev.blueledgers.com:40317` (gRPC) | Go x3 |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | `http://dev.blueledgers.com:40318` (HTTP) | NestJS x6, god-mode |
| `OTEL_ENDPOINT` ใน `public/config.json` | ยังไม่เคาะ — ขึ้นกับว่าเฟส 4 ยิงตรงหรือผ่าน gateway | carmen-spa, carmen-platform |

**พิสูจน์แล้วว่าใช้ได้จริงจากนอก LAN เมื่อ 2026-08-23** (ดู `dev-host-facts.md`)

endpoint นี้เป็น **public ไม่มี auth** ตามการตัดสินใจ "เปิดไว้ก่อน ยังไม่แตะ infra"
ถ้าวันหนึ่งปิด public จะต้องเปลี่ยนเป็น private IP ของ VM SigNoz — **แก้ที่ไฟล์นี้ไฟล์เดียว**
แล้วทุก repo ตามมา นั่นคือเหตุผลที่ห้าม hardcode

**ไม่ตั้ง env = SDK ไม่ start เลย** ไม่ใช่ start แล้วยิงไม่ถึง — exporter ที่ยิงไม่ถึงจะ retry
แล้วบวม memory เงียบ ๆ

## service.name (12 ตัว ห้ามตั้งชื่อใหม่)

```
backend-gateway · micro-business · micro-cluster · micro-file · micro-keycloak
micro-notification · micro-report · micro-cronjobs · micro-data
carmen-spa · carmen-platform · god-mode
```

ชื่อพวกนี้ตรงกับชื่อใน `start-dev.sh`, `rc-service` และไฟล์ log ที่คนดูอยู่ทุกวันโดยตั้งใจ

## Resource attributes

| attribute | ค่า | ยืนยันแล้ว |
|---|---|---|
| `service.namespace` | `carmen` | |
| `deployment.environment` | `dev` | ✅ เข้าเป็น type `Resource` |
| `service.version` | git short sha ตอน build | |

## Log attributes

| attribute | มาจาก | ยืนยันแล้ว |
|---|---|---|
| `carmen.tenant_id` | `IAMInfo.tenant_id` ของ `BackendLogger` | ✅ เข้าเป็น type `Tag` (String) filter ได้ |
| `carmen.user_id` | `IAMInfo.user_id` | ✅ เหมือนกัน |
| `carmen.auth` | `anonymous` เฉพาะที่มาทางช่อง pre-login | ยังไม่ถึงเฟสนั้น |

prefix `carmen.` ทั้งหมด เพื่อกันชนกับ OTel semantic conventions ในอนาคต

**log ที่มี `traceId`/`spanId` ใน record จะผูกกับ trace ให้อัตโนมัติ** — หน้า Log details
ขึ้นไอคอนลิงก์ไปยัง trace (พิสูจน์แล้ว) นี่คือเหตุผลหลักที่เลือก SigNoz แทน Loki

## Retention ที่ตั้งจริง (2026-08-23, disk ว่าง 60 GB จาก 98 GB)

| signal | ค่า | API ที่เป็นตัวจริง |
|---|---|---|
| Traces | 3 วัน | v1 (`traces_ttl_duration_hrs: 72`) |
| Logs | 7 วัน | **v2 custom retention** (`default_ttl_days: 7`) |
| Metrics | 1 เดือน | v1 (`metrics_ttl_duration_hrs: 720`) |

อย่าอ่านค่า logs จาก v1 (คืน `-1` เสมอ) และอย่าเชื่อหน้าจอ — เหตุผลอยู่ใน `dev-host-facts.md`
