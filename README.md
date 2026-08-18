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

## ก่อน deploy — เช็ค 3 ข้อ

| # | เช็คอะไร | ต้องได้ | ถ้าไม่ผ่าน |
|---|---|---|---|
| 1 | RAM ว่างบน host | >= 3 GB | ลด `mem_limit` ของ `clickhouse` และ `max_server_memory_usage` ลง (มีขั้นต่ำ ดูข้างล่าง) |
| 2 | Disk ว่าง | >= 20 GB | ตั้ง retention ให้สั้นกว่าที่แนะนำ |
| 3 | host ออกเน็ตไปที่ `github.com` **และ** `objects.githubusercontent.com` ได้ | ได้ทั้งคู่ | `user-scripts` จะ fail แล้ว `clickhouse` จะไม่ขึ้นเลย |

ข้อ 3 ต้องเปิดสองโดเมน — ลิงก์ release ของ GitHub redirect ไปโหลดไฟล์จริงที่
`objects.githubusercontent.com` เสมอ host ที่ allowlist ไว้แค่ `github.com`
จะผ่านการเช็คแบบผิวๆ แต่ยังโหลดไม่ได้อยู่ดี

ข้อ 1 ถ้าจำเป็นต้องลด `max_server_memory_usage` **อย่าให้ต่ำกว่า ~768 MiB**
เพราะ `mark_cache_size` (256 MiB) + `index_mark_cache_size` (128 MiB) จองไปแล้ว 384 MiB
จาก 1 GiB ที่ตั้งไว้ ถ้าต้องลดต่ำกว่านั้นจริง ต้องหั่นสอง cache นั้นลงตามสัดส่วนไปพร้อมกันด้วย
ไม่งั้นเหลือที่ให้ query จริงน้อยเกินไป

**เรื่องเวอร์ชัน Docker Compose** — ไฟล์นี้ต้องการ Compose >= 2.23.1 (พฤศจิกายน 2023)
ซึ่งเป็นรุ่นแรกที่รองรับ `configs.content` แต่ **เช็คล่วงหน้าไม่ได้** Portainer ไม่ได้โชว์เวอร์ชัน
Compose ที่ฝังมาที่ไหนใน UI เลย และเครื่องนี้ไม่มี shell ให้เข้าไปถาม วิธีที่เร็วที่สุดคือกด Deploy
ไปเลย ถ้าเก่าเกินไปจะ error ตั้งแต่ขั้น parse ทันที ไม่มีอะไรถูกสร้างค้างไว้ให้ต้องตามลบ
(ดูแถวแรกของตาราง "แก้ปัญหา")

## ขั้นตอน deploy

1. Portainer -> Stacks -> **Add stack** -> **Web editor**
2. ตั้งชื่อ stack เช่น `signoz`
3. วางเนื้อหาทั้งหมดของ `docker-compose.signoz-portainer.yaml` ลงในช่อง editor
4. (ถ้าจำเป็น) เพิ่ม Environment variables — ดูตารางข้างล่าง
5. กด **Deploy the stack**
6. รอ ~3-5 นาที ครั้งแรกต้องดึง image ~2 GB และรัน schema migration
7. พอ `signoz` ขึ้น ให้ทำ "หลัง deploy ขั้นที่ 1" ทันที อย่าเว้นช่วง (เหตุผลอยู่ท้ายหัวข้อนี้)

### Environment variables

ใส่เฉพาะตัวที่ต้องการเปลี่ยน ไม่ใส่ = ใช้ค่า default

| ตัวแปร | Default | ใช้ทำอะไร |
|---|---|---|
| `SIGNOZ_BIND_ADDR` | `0.0.0.0` | IP ที่ผูก port ไว้ ใส่ IP ของ LAN ถ้าเครื่องมี public IP |
| `SIGNOZ_UI_PORT` | `8080` | port ของ UI เปลี่ยนถ้าชนกับ service อื่น |
| `SIGNOZ_OTLP_GRPC_PORT` | `4317` | รับ telemetry แบบ gRPC |
| `SIGNOZ_OTLP_HTTP_PORT` | `4318` | รับ telemetry แบบ HTTP |

ใน URL และคำสั่งข้างล่างนี้ `<host>` = IP หรือ hostname ของเครื่อง Portainer
และ `<ui-port>` = `8080` หรือค่าที่ตั้งไว้ใน `SIGNOZ_UI_PORT`
(port 4317/4318 ก็เปลี่ยนตาม `SIGNOZ_OTLP_*_PORT` เหมือนกัน)

**OTLP ไม่มี authentication** — SigNoz OSS ไม่มี ingestion key ใครที่ยิงถึง port 4317/4318
ยัดข้อมูลเข้ามาได้ไม่จำกัดจนดิสก์เต็ม ถ้าเครื่องอยู่บนอินเทอร์เน็ต ให้ตั้ง
`SIGNOZ_BIND_ADDR` เป็น IP ของ LAN interface หรือกันด้วย firewall

**สร้าง admin account ทันทีที่ UI ขึ้น อย่าปล่อยค้างไว้** — ก่อนจะมี account แรก
`POST /api/v1/register` (คำสั่งเดียวกับที่แจกไว้ในหัวข้อถัดไป) เปิดให้ใครก็ตามที่ยิงถึง port UI
เรียกได้โดยไม่ต้องยืนยันตัวตน ใครเรียกก่อนก็ได้เป็น admin ของ instance นี้ไป
ช่องโหว่นี้เปิดตั้งแต่วินาทีที่ `signoz` ขึ้นจนถึงวินาทีที่สมัคร account แรกเสร็จ
"รอ 3-5 นาที" ในขั้นตอน deploy จึงไม่ใช่ช่วงที่ว่างให้ไปทำอย่างอื่น ให้เฝ้าจนขึ้นแล้วสมัครเลย

**UI เป็น HTTP ล้วน ไม่มี TLS** รหัสผ่าน admin จึงวิ่งข้ามเน็ตเวิร์กแบบอ่านได้ตรงๆ
default ของ `SIGNOZ_BIND_ADDR` คือ `0.0.0.0` ซึ่งจำเป็น เพราะ service ของ Carmen อยู่คนละเครื่อง
และต้องยิงเข้ามาได้ — แต่ก่อนจะใส่รหัสผ่านจริง ควรมีอย่างน้อยหนึ่งอย่างนี้: ตั้ง `SIGNOZ_BIND_ADDR`
เป็น IP ของ LAN interface, กันด้วย firewall, หรือวาง reverse proxy ที่ terminate TLS ไว้ข้างหน้า

## หลัง deploy ขั้นที่ 1 — สร้าง admin account (ต้องทำก่อนทุกอย่าง)

**stack จะไม่รับ telemetry เลยจนกว่าจะทำขั้นนี้** และอาการที่เจอจะดูเหมือนระบบพัง

`ingester` มีไฟล์ config ฝังมากับ compose ก็จริง แต่ไฟล์นั้นเป็นแค่ **จุดตั้งต้น** ไม่ใช่ config
ที่ได้รันจริง ตัวที่ตัดสินว่า config ไหนได้รันคือ OpAMP server ที่ฝังอยู่ใน `signoz`
(`ws://signoz-signoz-0:4320/v1/opamp`) — ตอนเริ่ม collector จะรายงาน config ที่ฝังมาขึ้นไปให้
server แล้ว server ส่ง **effective config** กลับลงมาให้รัน (เขียนไว้ที่
`/var/tmp/collector-config.yaml` ตาม `--copy-path` เปิดเทียบกับไฟล์ต้นทางได้)

ตราบใดที่ยังไม่มี organization ในระบบ OpAMP server จะ resolve `orgId` ของ agent ไม่ได้
effective config ที่ส่งกลับมาจึงเป็นเวอร์ชันที่ **ทุก pipeline ถูกเขียนใหม่ให้เหลือ receiver
กับ exporter เป็น `nop` อย่างเดียว** ผลคือ receiver `otlp` ที่ใน compose ต่อเข้า pipeline
`traces` / `metrics` / `logs` ไว้ครบทุกเส้นแล้ว กลายเป็นไม่ได้ต่อกับอะไรเลยตอนรันจริง
**จึงไม่มีอะไร listen บน 4317/4318**

จุดที่หลอกตาคือ `otlp` **ยังถูกนิยามอยู่ในไฟล์ effective config เหมือนเดิม** ถ้าเปิดไฟล์ไปดู
ต้องดูที่ `service.pipelines` ไม่ใช่ที่ block `receivers:` ตอนยังไม่มี organization จะเห็นแบบนี้:

```yaml
service:
  pipelines:
    traces:
      exporters:
        - nop
      receivers:
        - nop
```

ส่วน pipeline ใน compose ของเราต่อ `otlp` ไว้ครบถูกต้องอยู่แล้ว นั่นไม่ใช่จุดผิด ไม่ต้องไปแก้
สิ่งที่ขาดคือ organization ไม่ใช่ config

อาการ: `curl: (56) Recv failure: Connection reset by peer`
และใน log ของ `signoz` จะเห็น `"cannot create agent without orgId"` ซ้ำทุก 30 วินาที

เลือกทำอย่างใดอย่างหนึ่ง:

**ทางที่ 1 — ผ่าน UI (แนะนำ)** เปิด `http://<host>:<ui-port>` แล้วกรอกหน้าสมัครที่ขึ้นมาให้

**ทางที่ 2 — ผ่าน API** ถ้าเข้าเบราว์เซอร์ไม่ได้:

```bash
curl -X POST http://<host>:<ui-port>/api/v1/register \
  -H 'Content-Type: application/json' \
  -d '{"email":"you@example.com","password":"<password>","orgName":"Carmen","name":"Admin"}'
```

password ต้องยาว >= 12 ตัวและมีตัวพิมพ์ใหญ่ พิมพ์เล็ก ตัวเลข และสัญลักษณ์

หลังสร้างเสร็จรอประมาณ 30 วินาที (รอบ poll ของ OpAMP) `signoz` จะ push pipeline จริงลงไป
ยืนยันได้จาก log ของ `ingester` ที่จะขึ้น `Config has changed, reloading` ตามด้วย
`Starting GRPC/HTTP server` จากนั้น 4317/4318 ถึงจะเปิดรับจริง

ตรวจสถานะได้จาก:

```bash
curl -sS http://<host>:<ui-port>/api/v1/version
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

ยิง trace ปลอมเข้าไป 1 span ไม่ต้องลง SDK อะไรเลย

script นี้รันจาก **เครื่องของเราที่ clone repo นี้ไว้** ไม่ใช่บนเครื่อง Portainer
(เครื่องนั้นไม่มี shell ให้ใช้อยู่แล้ว) ขอแค่ยิงถึง port 4318 ของ host ได้ก็พอ:

```bash
./smoke-test/send-trace.sh http://<host>:4318
```

ถ้ามี shell แต่ไม่ได้ clone repo ไว้ ใช้ `curl` เปล่าๆ ก็ได้ผลเหมือนกัน:

```bash
NOW=$(( $(date +%s) * 1000000000 ))
curl -sS -w '\nHTTP %{http_code}\n' -X POST "http://<host>:4318/v1/traces" \
  -H 'Content-Type: application/json' \
  -d "{\"resourceSpans\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"smoke-test\"}}]},\"scopeSpans\":[{\"spans\":[{\"traceId\":\"5b8efff798038103d269b633813fc60c\",\"spanId\":\"eee19b7ec3c1b174\",\"name\":\"smoke-test-span\",\"kind\":2,\"startTimeUnixNano\":\"$(( NOW - 500000000 ))\",\"endTimeUnixNano\":\"$NOW\",\"status\":{\"code\":1}}]}]}]}"
```

คาดหวัง `HTTP 200` แล้วรอ ~30 วินาที เข้า UI -> **Services** ต้องเห็น service
ชื่อ `smoke-test` โผล่ขึ้นมา ถ้าเห็น = เส้นทาง ingester -> ClickHouse -> query -> UI
ทำงานครบทั้งเส้น

## ต่อ Carmen services เข้ามา

Carmen รันคนละเครื่อง ให้ตั้ง endpoint ชี้มาที่ host ของ Portainer

| Repo | Tech | endpoint |
|---|---|---|
| `micro-cronjobs` / `micro-report` / `micro-data` | Go + Gin | `otelgin` + `otlptracegrpc` ชี้ `<host>:4317` — **เริ่มที่นี่ก่อน** |
| `carmen` (micro-business) | NestJS + Prisma | `OTEL_EXPORTER_OTLP_ENDPOINT=http://<host>:4318` + `@prisma/instrumentation` |
| `carmen-turborepo-backend-v2` | NestJS + Bun | เหมือนบน แต่ดูข้อควรรู้เรื่อง Bun ด้านล่างก่อน |

**ทำไมเริ่มที่ Go:** auto-instrumentation ของ Go เป็น middleware ที่เรียกใช้ตรงๆ
ไม่ต้องพึ่งกลไก patch runtime แบบฝั่ง Node จึงไม่มีเงื่อนไขซ่อนอยู่
ได้ span จริงเร็วที่สุดและใช้ยืนยันว่าฝั่ง SigNoz พร้อมรับข้อมูลแล้ว
ก่อนไปเจอความซับซ้อนของฝั่ง JavaScript

**ข้อควรรู้เรื่อง Bun:** OTel auto-instrumentation ของ Node พึ่งการ monkey-patch `require`
ซึ่ง Bun รองรับไม่ครบ อาจเก็บ span ไม่ได้แม้ SDK จะ start ผ่าน
ทางออกเดียวที่เหลือคือ manual instrumentation เฉพาะจุดที่สำคัญ — สร้าง span เอง
ตรง handler และ query ที่อยากเห็น ไม่พึ่ง auto-instrumentation
(ถ้ามี reverse proxy หรือ gateway คั่นหน้าอยู่ การเก็บ trace ที่ชั้นนั้นแทน
จะได้ coverage ครบโดยไม่ต้องแตะโค้ด แต่ตอนนี้ยังไม่มีในสถาปัตยกรรม)

**ถ้าจะเอา React frontend เข้าด้วย** ต้องเพิ่ม CORS ใน `configs.ingester-config`
ที่ receiver `otlp.protocols.http` ไม่งั้น browser จะโดนปฏิเสธตอน preflight `OPTIONS`:

```yaml
      http:
        endpoint: "0.0.0.0:4318"
        cors:
          allowed_origins:
            - http://localhost:5173
```

แก้ในช่อง editor ของ Portainer แล้วกด **Update the stack** — `ingester` ต้องขึ้นใหม่
ถึงจะรายงานไฟล์ที่แก้แล้วขึ้น OpAMP server และได้ effective config ที่มี CORS กลับลงมาใช้

## แก้ปัญหา

ลำดับที่ควรไล่ดู log: `keeper` -> `user-scripts` -> `clickhouse` -> `migrator` -> `signoz` -> `ingester`

**วิธีรันคำสั่งบนเครื่อง Portainer ทั้งที่ไม่มี SSH:** Portainer -> **Containers**
-> คลิกชื่อคอนเทนเนอร์ -> **Console** -> เลือก command `/bin/bash` (ถ้าไม่มีให้ใช้ `/bin/sh`)
-> **Connect** จะได้ shell ข้างในคอนเทนเนอร์นั้น นี่คือ shell ทางเดียวที่มีบนเครื่องนั้น
และบางข้อข้างล่างต้องใช้

| อาการ | สาเหตุจริง | ทางแก้ |
|---|---|---|
| Portainer error ทันทีตอนกด Deploy (ข้อความพาดพิง `configs` / `content`) | Compose ของ Portainer เก่ากว่า 2.23.1 จึงไม่รู้จัก `configs.content` | อัปเกรด Portainer — เช็คเวอร์ชันล่วงหน้าไม่ได้ ต้องลอง deploy ถึงจะรู้ |
| `clickhouse` ไม่ขึ้นเลย `user-scripts` restart วน | โหลด `histogramQuantile` จาก GitHub ไม่ได้ | เช็คเน็ตขาออกของ host |
| `clickhouse` ตายเป็นรอบ **exit 137** | OOM-kill | ลด `max_server_memory_usage` ใน `configs.clickhouse-config` |
| Deploy ไม่ผ่าน "port is already allocated" | port ชนของเดิม | ตั้ง `SIGNOZ_UI_PORT` / `SIGNOZ_OTLP_*_PORT` ใหม่ |
| `migrator` restart วนไม่จบ | ClickHouse ยังไม่พร้อม | ปกติหายเอง ถ้าเกิน 5 นาทีให้ดู log |
| UI ขึ้นแต่ไม่มีข้อมูล / query error | ดิสก์ **ใกล้** เต็ม ClickHouse เป็น read-only | ลด retention แล้วรอ merge รอบถัดไป |
| เหมือนแถวบน แต่ลด retention แล้วรอเป็นชั่วโมงดิสก์ก็ไม่ลดสักที | ดิสก์เต็มจริง (เหลือ 0) merge เขียน part ใหม่ไม่ได้ TTL เลยไม่ได้ทำงาน | ต้องคืนพื้นที่ด้วยมือก่อน — ดู "ดิสก์เต็มจริง" ข้างล่าง |
| ยิง trace แล้ว `curl: (56) Connection reset by peer` ที่ 4318 | ยังไม่ได้สร้าง admin account → collector รัน no-op pipeline ไม่มีอะไร listen | ทำขั้นตอน "หลัง deploy ขั้นที่ 1" ให้เสร็จก่อน |
| ยิง trace แล้ว HTTP 200 แต่ UI ไม่เห็น service | `ingester` เขียนลง ClickHouse ไม่ได้ | ดู log ของ `ingester` หาคำว่า `clickhouse` |
| `keeper` ตาย exit 137 ก่อนตัวอื่น | 200m คือ limit ที่ตึงที่สุดในทั้ง stack | ขึ้นเป็น `300m` — งบรวมยังเหลือเยอะ |
| `ingester` exit 137 หรือ restart ซ้ำๆ ตอนมี traffic จริง | cache ของ span metrics โตตาม cardinality ของ span ไม่ใช่ตาม rate | ลด `dimensions_cache_size` ใน `configs.ingester-config` ลงอีก หรือขึ้น `mem_limit` ของ `ingester` เป็น `600m` (งบรับไหว) |

**exit code 137 = 128 + 9 (SIGKILL)** เป็นลายเซ็นของ OOM-killer เสมอ
ถ้าเห็นเลขนี้แปลว่า kernel เป็นคนฆ่าเพราะ memory ไม่ใช่แอปพังเอง
ส่วน **143 = 128 + 15 (SIGTERM)** คือการปิดตามปกติ

**`ingester` โดน OOM แล้วจะไม่ดูเหมือนตาย** เพราะตั้ง `restart: unless-stopped` ไว้
มันจะ crash-loop ขึ้นใหม่เรื่อยๆ ใน Portainer จึงเห็นเป็น "running" อยู่ดี
อาการที่เห็นจริงคือ telemetry ขาดเป็นช่วงๆ ไม่ใช่คอนเทนเนอร์ที่ตายชัดๆ
ให้ดูคอลัมน์ uptime ว่ารีเซ็ตบ่อยไหม และดู exit code ในหน้า container ประกอบ

`dimensions_cache_size` (ค่าที่ตั้งไว้ 10000) เก็บ latency histogram 17 bucket
พร้อม counter ต่อ 1 ชุดค่า dimension ที่ไม่ซ้ำกัน ยิ่ง service / environment / version
แตกแขนงมากยิ่งกินเยอะ และ `memory_limiter` ช่วยตรงนี้ไม่ได้ เพราะมันแค่ปฏิเสธข้อมูลใหม่
ไม่ได้ปล่อยของที่ processor ถือไว้อยู่แล้วคืน

### ดิสก์เต็มจริง — ต้องคืนพื้นที่ก่อน

ClickHouse ลบข้อมูลตาม TTL ตอน background merge และ merge ต้องเขียน part ใหม่ให้เสร็จก่อน
ถึงจะลบ part เก่าทิ้งได้ พอดิสก์เหลือ 0 จริงๆ มันไม่มีที่ให้เขียน part ใหม่ การลด retention
ตอนนั้นจึงแก้แค่ metadata ของตาราง แล้วไม่มีอะไรเกิดขึ้นตามมาอีกเลย รอไปก็เท่านั้น
ต้องคืนพื้นที่ด้วยมือก่อน:

1. Portainer -> **Containers** -> `signoz-telemetrystore-clickhouse-0-0` -> **Console**
   -> `/bin/bash` -> **Connect**
2. เปิด client แล้วดูว่า partition ไหนกินที่:

   ```bash
   clickhouse-client
   ```

   ```sql
   SELECT database, table, partition, formatReadableSize(sum(bytes_on_disk)) AS size
   FROM system.parts
   WHERE active AND database LIKE 'signoz%'
   GROUP BY database, table, partition
   ORDER BY sum(bytes_on_disk) DESC
   LIMIT 20;
   ```

3. drop partition ที่เก่าที่สุดทิ้ง ใช้ชื่อ database / table / partition ตามที่ query ข้างบนแสดง
   ตรงๆ (`system.parts` แสดงเฉพาะตาราง local อยู่แล้ว ไม่ใช่ตัว `distributed_*`)
   ตารางที่ใหญ่ที่สุดมักเป็น `signoz_traces.signoz_index_v3` และชื่อ partition เป็นวันที่:

   ```sql
   ALTER TABLE signoz_traces.signoz_index_v3 DROP PARTITION '2026-08-13';
   ```

   `DROP PARTITION` ลบไฟล์ทิ้งตรงๆ ไม่ต้อง merge ก่อน จึงทำงานได้แม้ดิสก์เหลือ 0
   ลบทีละ partition แล้ววนกลับไป query ข้อ 2 ใหม่จนมีที่ว่างพอ

4. พอมีที่ว่างแล้วค่อยกลับไปตั้ง retention ตามหัวข้อ "หลัง deploy ขั้นที่ 2" ไม่งั้นอีกไม่นานก็วนกลับมาที่เดิม

**ทางลัดที่หยาบกว่า** ถ้าไม่อยากยุ่งกับ SQL: ลบ stack, ลบ volume `signoz-telemetrystore-0-0-data`
ตัวเดียว แล้ว deploy ใหม่ — telemetry ที่เก็บไว้หายหมด แต่ dashboard / alert rule / user
**ไม่หาย** เพราะอยู่คนละ volume (`signoz-metastore-sqlite-0-data`)

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

**ทุกครั้งที่ Update the stack `user-scripts` จะรันใหม่หมด** ไม่ใช่แค่ตอน deploy ครั้งแรก
แปลว่า host ต้องออกเน็ตไป `github.com` / `objects.githubusercontent.com` ได้ทุกรอบที่ deploy
ถ้าเน็ตขาดจังหวะนั้น `user-scripts` จะ retry ไม่จบ และ `clickhouse` ที่รอ
`service_completed_successfully` อยู่ก็จะไม่ขึ้น — stack ที่เพิ่งทำงานอยู่ดีๆ จะล้มทั้งชุด
เพราะแค่ขยับ tag ตอนเน็ตไม่ดี

ก่อนอัปเกรดควร diff ไฟล์ต้นฉบับก่อน ดู `reference/upstream/PROVENANCE.md`

## Reset ทั้งหมด

ลบ stack ใน Portainer แล้วลบ volume ทั้ง 4 ตัว จากนั้น deploy ใหม่
ข้อมูล telemetry และ dashboard จะหายหมด
