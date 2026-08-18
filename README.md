# SigNoz บน Portainer

Docker Compose ไฟล์เดียวสำหรับรัน SigNoz บน Portainer (Standalone Docker + Stacks)
ออกแบบมาสำหรับเครื่อง ~4 GB ที่เข้าถึงได้ผ่าน Portainer UI อย่างเดียว
ไม่มี SSH ไม่ต่อ Git

- **ไฟล์ที่ใช้ deploy:** `docker-compose.signoz-portainer.yaml`
- **การออกแบบและเหตุผล:** `docs/superpowers/specs/2026-08-18-signoz-portainer-design.md`
- **ไฟล์ต้นฉบับจาก upstream:** `reference/upstream/`

## ทำไมไม่ใช้ compose ของ SigNoz ตรงๆ

SigNoz เลิกแจก `docker-compose.yaml` แล้ว เปลี่ยนไปใช้ Foundry (`foundryctl forge`)
ซึ่ง generate compose ที่ bind-mount config 5 ไฟล์จาก host — ไฟล์ที่ Portainer web editor
ไม่มีทางสร้างให้ได้ ไฟล์นี้จึงฝัง config ทั้งหมดไว้ข้างในผ่าน `configs:` + `content:`

## ก่อน deploy — เช็ค 4 ข้อ

| # | เช็คอะไร | ต้องได้ | ถ้าไม่ผ่าน |
|---|---|---|---|
| 1 | เวอร์ชัน Docker Compose ของ Portainer | **>= 2.23.1** | ใช้ไฟล์นี้ไม่ได้ ต้องอัปเกรด Portainer |
| 2 | RAM ว่างบน host | >= 3 GB | ลด `mem_limit` ของ `clickhouse` และ `max_server_memory_usage` ลง |
| 3 | Disk ว่าง | >= 20 GB | ตั้ง retention ให้สั้นกว่าที่แนะนำ |
| 4 | host ออกเน็ตไปที่ github.com ได้ | ได้ | `user-scripts` จะ fail แล้ว `clickhouse` จะไม่ขึ้นเลย |

ข้อ 1 สำคัญที่สุด — `configs.content` เพิ่งรองรับใน Compose 2.23.1 (พฤศจิกายน 2023)
ถ้าเก่ากว่านี้ stack จะ deploy ไม่ผ่านตั้งแต่ขั้น parse

## ขั้นตอน deploy

1. Portainer -> Stacks -> **Add stack** -> **Web editor**
2. ตั้งชื่อ stack เช่น `signoz`
3. วางเนื้อหาทั้งหมดของ `docker-compose.signoz-portainer.yaml` ลงในช่อง editor
4. (ถ้าจำเป็น) เพิ่ม Environment variables — ดูตารางข้างล่าง
5. กด **Deploy the stack**
6. รอ ~3-5 นาที ครั้งแรกต้องดึง image ~2 GB และรัน schema migration

### Environment variables

ใส่เฉพาะตัวที่ต้องการเปลี่ยน ไม่ใส่ = ใช้ค่า default

| ตัวแปร | Default | ใช้ทำอะไร |
|---|---|---|
| `SIGNOZ_BIND_ADDR` | `0.0.0.0` | IP ที่ผูก port ไว้ ใส่ IP ของ LAN ถ้าเครื่องมี public IP |
| `SIGNOZ_UI_PORT` | `8080` | port ของ UI เปลี่ยนถ้าชนกับ service อื่น |
| `SIGNOZ_OTLP_GRPC_PORT` | `4317` | รับ telemetry แบบ gRPC |
| `SIGNOZ_OTLP_HTTP_PORT` | `4318` | รับ telemetry แบบ HTTP |

**OTLP ไม่มี authentication** — SigNoz OSS ไม่มี ingestion key ใครที่ยิงถึง port 4317/4318
ยัดข้อมูลเข้ามาได้ไม่จำกัดจนดิสก์เต็ม ถ้าเครื่องอยู่บนอินเทอร์เน็ต ให้ตั้ง
`SIGNOZ_BIND_ADDR` เป็น IP ของ LAN interface หรือกันด้วย firewall

## หลัง deploy ขั้นที่ 1 — สร้าง admin account (ต้องทำก่อนทุกอย่าง)

**stack จะไม่รับ telemetry เลยจนกว่าจะทำขั้นนี้** และอาการที่เจอจะดูเหมือนระบบพัง

`ingester` ไม่ได้อ่าน config จากไฟล์ตรงๆ แต่รับ config จาก OpAMP server ที่ฝังอยู่ใน `signoz`
(`ws://signoz-signoz-0:4320/v1/opamp`) ตราบใดที่ยังไม่มี organization ในระบบ OpAMP server
จะ resolve `orgId` ของ agent ไม่ได้ แล้วส่ง **no-op pipeline** ลงมาแทน — receiver `otlp`
ถูกนิยามไว้ในไฟล์แต่ไม่ได้ถูกต่อเข้า pipeline ไหนเลย **จึงไม่มีอะไร listen บน 4317/4318**

อาการ: `curl: (56) Recv failure: Connection reset by peer`
และใน log ของ `signoz` จะเห็น `"cannot create agent without orgId"` ซ้ำทุก 30 วินาที

เลือกทำอย่างใดอย่างหนึ่ง:

**ทางที่ 1 — ผ่าน UI (แนะนำ)** เปิด `http://<host>:8080` แล้วกรอกหน้าสมัครที่ขึ้นมาให้

**ทางที่ 2 — ผ่าน API** ถ้าเข้าเบราว์เซอร์ไม่ได้:

```bash
curl -X POST http://<host>:8080/api/v1/register \
  -H 'Content-Type: application/json' \
  -d '{"email":"you@example.com","password":"<password>","orgName":"Carmen","name":"Admin"}'
```

password ต้องยาว >= 12 ตัวและมีตัวพิมพ์ใหญ่ พิมพ์เล็ก ตัวเลข และสัญลักษณ์

หลังสร้างเสร็จรอประมาณ 30 วินาที (รอบ poll ของ OpAMP) `signoz` จะ push pipeline จริงลงไป
ยืนยันได้จาก log ของ `ingester` ที่จะขึ้น `Config has changed, reloading` ตามด้วย
`Starting GRPC/HTTP server` จากนั้น 4317/4318 ถึงจะเปิดรับจริง

ตรวจสถานะได้จาก:

```bash
curl -sS http://<host>:8080/api/v1/version
```

`"setupCompleted":false` = ยังไม่ได้สร้าง admin, `true` = เรียบร้อย

## หลัง deploy ขั้นที่ 2 — ตั้ง retention (ห้ามข้าม)

ค่า default ของ SigNoz คือ traces/logs 15 วัน metrics 30 วัน ซึ่งมากเกินไปสำหรับเครื่อง 4 GB
ถ้าไม่ตั้ง ดิสก์จะเต็มแล้ว ClickHouse จะเข้าสถานะ read-only

เข้า SigNoz UI -> **Settings** -> **Retention** แล้วตั้ง:

| ประเภท | ค่าที่แนะนำ |
|---|---|
| Traces | 3 วัน |
| Logs | 3 วัน |
| Metrics | 7 วัน |

ClickHouse ลบข้อมูลด้วย TTL ที่ทำงานตอน background merge ดิสก์จะไม่ลดลงทันที
หลังลด retention ต้องรอ merge รอบถัดไป

## ตรวจว่าใช้งานได้จริง

ทำหลังจากสร้าง admin account แล้วเท่านั้น ไม่งั้นจะได้ connection reset

ยิง trace ปลอมเข้าไป 1 span ไม่ต้องลง SDK อะไรเลย:

```bash
./smoke-test/send-trace.sh http://<host>:4318
```

คาดหวัง `HTTP 200` แล้วรอ ~30 วินาที เข้า UI -> **Services** ต้องเห็น service
ชื่อ `smoke-test` โผล่ขึ้นมา ถ้าเห็น = เส้นทาง ingester -> ClickHouse -> query -> UI
ทำงานครบทั้งเส้น

## ต่อ Carmen services เข้ามา

Carmen รันคนละเครื่อง ให้ตั้ง endpoint ชี้มาที่ host ของ Portainer

| Repo | Tech | endpoint |
|---|---|---|
| `api-gateway-apisix` | APISIX | เปิด plugin `opentelemetry` ชี้ `http://<host>:4318` — **เริ่มที่นี่ก่อน** ได้ trace ครอบทุก request โดยไม่แก้โค้ด |
| `carmen-turborepo-backend-v2` | NestJS + Bun | `OTEL_EXPORTER_OTLP_ENDPOINT=http://<host>:4318` |
| `carmen` (micro-business) | NestJS + Prisma | เหมือนบน + `@prisma/instrumentation` |
| `micro-cronjobs` / `micro-report` / `micro-data` | Go + Gin | `otelgin` + `otlptracegrpc` ชี้ `<host>:4317` |

**ข้อควรรู้เรื่อง Bun:** OTel auto-instrumentation ของ Node พึ่งการ monkey-patch `require`
ซึ่ง Bun รองรับไม่ครบ อาจเก็บ span ไม่ได้แม้ SDK จะ start ผ่าน
ทางถอย: พึ่ง trace จาก APISIX ที่ edge แทน หรือ manual instrumentation เฉพาะจุด

**ถ้าจะเอา React frontend เข้าด้วย** ต้องเพิ่ม CORS ใน `configs.ingester-config`
ที่ receiver `otlp.protocols.http` ไม่งั้น browser จะโดนปฏิเสธตอน preflight `OPTIONS`:

```yaml
      http:
        endpoint: "0.0.0.0:4318"
        cors:
          allowed_origins:
            - http://localhost:5173
```

## แก้ปัญหา

ลำดับที่ควรไล่ดู log: `keeper` -> `user-scripts` -> `clickhouse` -> `migrator` -> `signoz` -> `ingester`

| อาการ | สาเหตุจริง | ทางแก้ |
|---|---|---|
| Portainer error ทันทีตอนกด Deploy | Compose < 2.23.1 ไม่รู้จัก `configs.content` | อัปเกรด Portainer |
| `clickhouse` ไม่ขึ้นเลย `user-scripts` restart วน | โหลด `histogramQuantile` จาก GitHub ไม่ได้ | เช็คเน็ตขาออกของ host |
| `clickhouse` ตายเป็นรอบ **exit 137** | OOM-kill | ลด `max_server_memory_usage` ใน `configs.clickhouse-config` |
| Deploy ไม่ผ่าน "port is already allocated" | port ชนของเดิม | ตั้ง `SIGNOZ_UI_PORT` / `SIGNOZ_OTLP_*_PORT` ใหม่ |
| `migrator` restart วนไม่จบ | ClickHouse ยังไม่พร้อม | ปกติหายเอง ถ้าเกิน 5 นาทีให้ดู log |
| UI ขึ้นแต่ไม่มีข้อมูล / query error | ดิสก์เต็ม ClickHouse เป็น read-only | ลด retention แล้วรอ merge |
| ยิง trace แล้ว `curl: (56) Connection reset by peer` ที่ 4318 | ยังไม่ได้สร้าง admin account → collector รัน no-op pipeline ไม่มีอะไร listen | ทำขั้นตอน "หลัง deploy ขั้นที่ 1" ให้เสร็จก่อน |
| ยิง trace แล้ว HTTP 200 แต่ UI ไม่เห็น service | `ingester` เขียนลง ClickHouse ไม่ได้ | ดู log ของ `ingester` หาคำว่า `clickhouse` |
| `keeper` ตาย exit 137 ก่อนตัวอื่น | 200m คือ limit ที่ตึงที่สุดในทั้ง stack | ขึ้นเป็น `300m` — งบรวมยังเหลือเยอะ |

**exit code 137 = 128 + 9 (SIGKILL)** เป็นลายเซ็นของ OOM-killer เสมอ
ถ้าเห็นเลขนี้แปลว่า kernel เป็นคนฆ่าเพราะ memory ไม่ใช่แอปพังเอง
ส่วน **143 = 128 + 15 (SIGTERM)** คือการปิดตามปกติ

## Backup

| Volume | เนื้อหา | ต้อง backup |
|---|---|---|
| `signoz-metastore-sqlite-0-data` | dashboard, alert rule, user | **ใช่ ตัวเดียวที่ต้อง** |
| `signoz-telemetrystore-0-0-data` | ข้อมูล ClickHouse | ไม่ (ใหญ่สุด แต่ generate ใหม่ได้) |
| `signoz-telemetrykeeper-0-data` | keeper coordination | ไม่ |
| `signoz-telemetrystore-user-scripts` | binary `histogramQuantile` | ไม่ (โหลดใหม่ได้) |

volume ที่เล็กที่สุดคือตัวที่สำคัญที่สุด เพราะเป็นตัวเดียวที่เก็บงานที่คนสร้างเอง

## อัปเกรด

เวอร์ชันที่ใช้อยู่ตอนนี้ (ทดสอบร่วมกันแล้ว):

| Image | Tag |
|---|---|
| `signoz/signoz` | `v0.137.1` |
| `signoz/signoz-otel-collector` | `v0.144.8` |
| `clickhouse/clickhouse-server` | `25.12.5` |
| `clickhouse/clickhouse-keeper` | `25.12.5` |

`signoz` กับ `signoz-otel-collector` **เดินคนละสาย version ต้องขยับพร้อมกันเสมอ**

ขั้นตอน: แก้ tag ใน Portainer editor -> **Update the stack**
`migrator` จะรัน schema migration ให้อัตโนมัติตอนขึ้น

ก่อนอัปเกรดควร diff ไฟล์ต้นฉบับก่อน ดู `reference/upstream/PROVENANCE.md`

## Reset ทั้งหมด

ลบ stack ใน Portainer แล้วลบ volume ทั้ง 4 ตัว จากนั้น deploy ใหม่
ข้อมูล telemetry และ dashboard จะหายหมด
