# สถานะการ instrument — บันทึกผลจริง

**อัปเดต:** 2026-08-23
**spec:** `docs/superpowers/specs/2026-08-23-carmen-otel-instrumentation-design.md`
**convention:** `docs/otel-conventions.md`

**merge เข้า main และ push ครบ 8 repo แล้ว (23 ส.ค. 12:1x)** — CI deploy ขึ้น dev สำเร็จ
ทั้ง `carmen-turborepo-backend-v2`, `micro-report`, `micro-cronjobs`

ยืนยันจากภายนอกว่าโค้ดใหม่ขึ้นจริง: `POST /telemetry/v1/anonymous/logs` ตอบ **503**
(`anonymous telemetry disabled`) ซึ่งเป็น controller ตัวใหม่ตอบเอง เพราะยังไม่ได้ตั้ง
`OTEL_EXPORTER_OTLP_ENDPOINT` บนเครื่อง — พิสูจน์ทั้งว่า route ถูก deploy แล้วและ
สวิตช์ปิดทำงานถูกต้อง

**telemetry ยังไม่ทำงานจนกว่าจะตั้ง env ตามตารางข้างล่าง**

## สิ่งที่ทำไปแล้ว

| repo | branch | ได้อะไร |
|---|---|---|
| `micro-report` | `feature/otel-instrumentation` | otelzap + otelgin + OTLP/gRPC ครบสาม signal |
| `micro-cronjobs` | `feature/otel-instrumentation` | เหมือนบน + **root span ต่อรอบงาน** ที่ `JobExecutor.Execute` |
| `micro-data` | `feature/otel-instrumentation` | เหมือน micro-report |
| `carmen-turborepo-backend-v2` | `feature/otel-observability` | `packages/observability` + ยุบ logger 6 สำเนา + ถอด Loki + telemetry proxy ที่ gateway |
| `carmen-inventory-frontend-react` | `feature/otel-browser-telemetry` | web SDK แบบ dynamic import + ช่อง pre-login |
| `carmen-platform` | `feature/otel-browser-telemetry` | เหมือนบน (สวิตช์เป็น build-time) |
| `carmen-inventory-god-mode` | `feature/otel-instrumentation` | `instrumentation.ts` + log ทุก operation ที่ถูก audit |

## ต้องตั้งอะไรถึงจะทำงานจริง

**ไม่ตั้ง = ปิดสนิท** (ไม่ start SDK เลย ไม่ใช่ start แล้วยิงไม่ถึง) ทุกที่ยกเว้นที่ระบุ

| ที่ไหน | ตั้งอะไร |
|---|---|
| Go 3 ตัว (`.env` บน dev) | `OTEL_EXPORTER_OTLP_ENDPOINT=http://dev.blueledgers.com:40317` · `DEPLOYMENT_ENVIRONMENT=dev` |
| NestJS 6 ตัว (`.env` บน dev) | `OTEL_EXPORTER_OTLP_ENDPOINT=http://dev.blueledgers.com:40318` · `DEPLOYMENT_ENVIRONMENT=dev` |
| gateway (เพิ่มเติม) | `TELEMETRY_ANONYMOUS_ENABLED=false` ถ้าจะปิดช่อง pre-login |
| `carmen-inventory-frontend-react` | `"OTEL_ENABLED": true` ใน `public/config.json` ของ environment นั้น |
| `carmen-platform` | `REACT_APP_OTEL_ENABLED=true` **ตอน build** (ไม่ใช่ runtime — ดูข้อ 6 ข้างล่าง) |
| god-mode | `OTEL_EXPORTER_OTLP_ENDPOINT=http://dev.blueledgers.com:40318` |

`public/config*.json` และ `apps/*/.env` ถูก gitignore — **ต้องเติมด้วยมือทุกที่**

## กับดักที่เจอจริงระหว่างทำ (ทุกข้อเสียเวลาไปแล้ว)

**1. semconv ต้องตรงเวอร์ชันกับ SDK (Go)** — `resource.Merge` ตอบ error
`conflicting Schema URL` ทันทีตอน `Init` ถ้า import semconv คนละเวอร์ชันกับที่
`resource.Default()` ใช้ **compile ผ่านแต่รันไม่ได้** เจอตอนรันครั้งแรกเท่านั้น

**2. `deployment.environment` ไม่ใช่ `deployment.environment.name`** — semconv 1.43
เปลี่ยนชื่อคีย์แล้ว แต่ **SigNoz index ตัวชื่อเดิม** ทุก repo จึงตั้งคีย์นี้ตรง ๆ
ไม่ผ่าน helper ของ semconv ยึดตามที่ปลายทางเข้าใจ ไม่ใช่ spec ล่าสุด

**3. พึ่ง signal handler อย่างเดียว = ข้อมูลหาย** — NodeSDK ลง handler ของตัวเองไว้ด้วย
ตัวไหนเรียก `process.exit` ก่อน อีกตัวถูกตัดกลางคัน **ยิง log 4 อันไม่ถึงสักอันโดยไม่มี
error ใด ๆ** ต้อง export `shutdownTelemetry()` ให้เรียกตรง ๆ ได้เสมอ

**4. `NODE_ENV` ใช้เป็น `deployment.environment` ไม่ได้** — บน dev มันถูกตั้งเป็น
`production` (ดู `docker-compose.yml`) ถ้าใช้ ข้อมูล dev จะไปปนกับ prod

**5. ของเดิมที่ยิงผิดที่มาตลอด** — `gateway` กับ `micro-business` มี `tracing.ts`
และ `.env` ตั้ง `OTEL_EXPORTER_OTLP_ENDPOINT=http://dev.blueledgers.com:4318` อยู่แล้ว
**ไม่มีอะไรฟังที่ 4318** (ที่ publish คือ 40318) ทั้งคู่จึงรัน SDK ยิงเข้าที่ตายแล้ว retry
มาตลอด — ถอดออกและแทนที่แล้ว

**6. สวิตช์ของ `carmen-platform` เป็น build-time** — Vite แทน `import.meta.env` ตอน
build ถ้าไม่ตั้ง `REACT_APP_OTEL_ENABLED=true` ตอนนั้น เงื่อนไขกลายเป็น false แล้ว
dynamic import ถูกตัดทิ้งทั้งก้อน (ไม่มี chunk telemetry ออกมาเลย) **เปิดทีหลังต้อง
build ใหม่ ไม่ใช่แก้ config** ต่างจาก SPA หลักที่เป็น runtime

**7. header ของ exporter ต้องเป็นฟังก์ชัน** — ฝั่งเบราว์เซอร์ถ้าส่ง object ที่ประเมิน
ค่าแล้ว token จะถูกแช่ตั้งแต่ init แล้ว 401 เงียบ ๆ หลัง refresh รอบแรก

**9. Go toolchain บน dev เตี้ยกว่าที่ dependency ต้องการ** — การเพิ่ม OTel ดันกราฟ
module ทั้งชุดไปเกินที่เครื่องรองรับ (ไม่ใช่แค่ OTel v1.45 เอง แต่ gin, `golang.org/x/*`
และ grpc-gateway ที่พ่วงมาด้วย) deploy ล้มด้วย
`go.mod requires go >= 1.25.0 (running go 1.24.13; GOTOOLCHAIN=local)`

โชคดีที่สคริปต์ deploy มี `set -e` จึงล้มก่อนถึงขั้น restart — binary เก่ายังเสิร์ฟต่อ
ไม่มีอะไรล่ม แต่ก็ไม่มีอะไรขึ้นเช่นกัน

แก้ด้วย `export GOTOOLCHAIN=auto` ในเส้นทาง deploy ทั้งสาม (workflow ของ micro-report
กับ micro-cronjobs และ `deploy/deploy.sh` ของ micro-data) ให้ go โหลด toolchain ที่
ต้องการมาเอง แทนการรั้งทั้ง dependency graph ไว้ให้เข้ากับเครื่องเดียว — เครื่องเข้าถึง
module proxy อยู่แล้วเพราะ build ต้องใช้ จึงไม่ต้องแก้อะไรบนเซิร์ฟเวอร์
ทางนี้ยังแก้ `micro-data` ที่ติด `rogpeppe/go-internal` ซึ่งไม่เกี่ยวกับ OTel เลยไปด้วย

**หมายเหตุ:** workflow `Deploy micro-cronjob` (ตัวที่ deploy ไป AWS ไม่ใช่ dev) ยังล้มอยู่
ที่ `Configure AWS credentials` — **ล้มทุกครั้งย้อนไปถึงมิถุนายน 2026** เป็นของเดิม
ไม่เกี่ยวกับงานนี้

**8. `propagateTraceHeaderCorsUrls`** — web SDK ไม่ใส่ `traceparent` ให้ request ข้าม
origin โดย default ลืมแล้วจะได้ trace เบราว์เซอร์กับ backend เป็นคนละเส้น

## ที่จงใจไม่ทำ

- **ไม่ปิด port สาธารณะ** (เฟส 0 Task 4) — เจ้าของระบบสั่งให้เปิดไว้ก่อน
  รายการที่ยังเปิดอยู่และความเสี่ยงอยู่ใน `dev-host-facts.md`
- **ไม่ push ไม่ merge** ทุก repo อยู่บน branch รอตรวจ
- **ไม่แตะ `.env` บน dev server** — แก้แต่ `.env.example` และไฟล์ในเครื่อง local
- **ไม่ไล่ให้ auto-instrumentation ทำงานเต็มรูปแบบบน Bun** (god-mode) เป็น spike แยก

## พิสูจน์แล้วด้วยข้อมูลจริงบน dev (23 ส.ค. 13:38)

หลัง restart ครบทุก service พร้อม env — **8 service รายงานเข้า SigNoz**
(cronjobs, business, gateway, data, keycloak, cluster, notification, file)

| ข้อสมมติที่ค้างมาตลอด | ผล |
|---|---|
| `otelgin` / `HttpInstrumentation` เก็บ span ของ request จริง | ✅ ทุก service มี span จาก traffic จริง |
| **trace ไหลข้าม service** | ✅ trace `0e157127…` = 4 span 2 service: `POST backend-gateway 35.23ms` → `POST micro-cluster 24.67ms` โดย `parent_span_id` ผูกกันจริง |
| DB query span | ✅ `pg.query:SELECT/BEGIN/COMMIT`, `pg.connect`, `pg-pool.connect` ซ้อนอยู่ใต้ span ของ service |
| root span ของ cron | ✅ `micro-cronjobs` P99 376 ms จากงานตามตารางจริง ไม่ใช่ span ที่สร้างเอง |
| shutdown flush | ✅ เห็น `shutting down…` / `scheduler stopped` ใน SigNoz — บั๊กที่เคยทำ log หายเกลี้ยง แก้ถูกแล้ว |
| `deployment.environment` | ✅ facet `dev` ใช้ filter ได้ |

span ที่ยืนยัน propagation มี `http.url: http://localhost:5014/rpc/…` และ
`http.user_agent: axios/1.19.0` — คือ `@repo/nest-http-transport` ตามที่ spec คาดไว้ว่า
"RPC เป็น HTTP จริง จึงได้ propagation ฟรี" ข้อนั้นถูกต้อง

## ที่ยังไม่ได้พิสูจน์

ทุกอย่างข้างบนทดสอบจาก **เครื่อง dev ของผู้พัฒนา ยิงข้ามอินเทอร์เน็ตเข้า SigNoz**
ยังไม่มีอะไรรันบน VM จริงเลย — สิ่งที่ยังไม่รู้:

- **volume จริงต่อวันเท่าไร** — ตัวตัดสินว่า retention (traces 3 วัน / logs 7 วัน) พอหรือไม่
  ต้องปล่อยให้เดินสักวันสองวันแล้วดู disk
- **ฝั่ง browser** — SPA, carmen-platform, god-mode ยังไม่ได้ deploy ด้วยสวิตช์เปิด
- span ระดับ Prisma โดยเฉพาะ (ที่เห็นคือ `pg.*` จาก PgInstrumentation ซึ่งครอบคลุมกว่า
  แต่ไม่ได้บอกชื่อ model/operation ของ Prisma)
