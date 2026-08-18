# Design: SigNoz บน Portainer ด้วย Docker Compose ไฟล์เดียว

- **วันที่:** 2026-08-18
- **สถานะ:** อนุมัติแล้ว รอทำแผน implement
- **ผู้ออกแบบ:** samutpra + Claude

---

## 1. ปัญหาและบริบท

ต้องการรัน SigNoz (observability platform) เพื่อ monitor งาน development ของ Carmen
โดย deploy ผ่าน Portainer

ข้อจำกัดที่ยืนยันแล้ว:

| ข้อจำกัด | ค่า | ผลต่อการออกแบบ |
|---|---|---|
| Portainer environment | Standalone Docker + Stacks (ไม่ใช่ Swarm) | ใช้ `depends_on: condition:` ได้เต็มรูปแบบ |
| ช่องทางเข้าถึง host | **Portainer UI อย่างเดียว** ไม่มี SSH ไม่ต่อ Git | ทุกอย่างต้องอยู่ในไฟล์ compose ไฟล์เดียว |
| RAM ที่ใช้ได้ | ~4 GB หรือน้อยกว่า | ต้องตัด service และจูน memory ทุกตัว |
| การใช้งาน | monitor Carmen dev ไม่ใช่ production | retention สั้นได้ ไม่ต้อง HA |
| ตำแหน่ง Carmen services | คนละเครื่องกับ Portainer | ต้อง publish port OTLP ออกมา |

### อุปสรรคหลัก

SigNoz **เลิกแจก `docker-compose.yaml` แล้ว** ตั้งแต่ก่อน v0.137.1
(`deploy/README.md` ระบุว่า `install.sh` และ compose manifests ทั้งหมด deprecated)
ทางที่ upstream รองรับคือ **Foundry** (`foundryctl forge` / `foundryctl cast`)

Foundry ไม่ได้แทนที่ Docker — มันเป็นตัว **generate** manifest
`foundryctl forge` จะสร้าง `pours/deployment/compose.yaml` ออกมา ซึ่งเป็น compose file ปกติ
แต่ **ใช้กับ Portainer web editor ตรงๆ ไม่ได้** เพราะอ้าง relative bind mount 5 ไฟล์
ที่ไม่มีอยู่บน host:

```
./ingester/ingester.yaml
./ingester/opamp.yaml
./telemetrykeeper/clickhousekeeper/keeper-0.yaml
./telemetrystore/clickhouse/config-0-0.yaml
./telemetrystore/clickhouse/functions.yaml
```

**แนวทางที่เลือก:** ใช้ Foundry generate ของจริงเป็นต้นแบบ แล้วแปลงเป็นไฟล์เดียว
โดยฝัง config ทั้งหมดผ่าน `configs:` + `content:` ของ Compose Spec

### แนวทางที่พิจารณาแล้วไม่เลือก

| แนวทาง | เหตุผลที่ไม่เลือก |
|---|---|
| B: config-seeder init container + named volume | config ไปอยู่ใน `command:` heredoc → escaping YAML ซ้อน shell ซ้อน YAML, แก้ config ทีต้องลบ volume |
| C: bake config เข้า custom image + push registry | ต้องมี registry + CI, แก้ config ทีต้อง rebuild — overkill สำหรับ dev |
| Git-backed stack ของ Portainer | ตัดออกเพราะ Portainer ต่อ Git ไม่ได้ |
| วางไฟล์บน host ด้วย absolute path | ตัดออกเพราะไม่มี SSH |

**B ยังเป็น fallback** ถ้า Docker Compose ฝั่ง Portainer เก่ากว่า 2.23.1

---

## 2. สถาปัตยกรรม

### Topology — 6 services, single node

```
                    Portainer host (~4 GB)
 ┌──────────────────────────────────────────────────────────┐
 │  :8080 ──► signoz ────────────┐                          │
 │            (UI + query + alerts + opamp:4320)            │
 │                               │                          │
 │  :4317 ──► ingester ──────────┼──► clickhouse ◄── keeper │
 │  :4318     (otel-collector)   │      (:9000/:8123)  :9181│
 │                               └──────────┘               │
 │                                                          │
 │  [run-once]  user-scripts ──► โหลด histogramQuantile     │
 │  [run-once]  migrator ──────► สร้าง schema ON CLUSTER    │
 └──────────────────────────────────────────────────────────┘
                       network: signoz-network
```

### รายการ service

| Service | หน้าที่ | lifecycle |
|---|---|---|
| `signoz` | UI + query engine + alert manager + opamp server (:4320) | long-running |
| `ingester` | otel-collector รับ OTLP แล้วเขียนลง ClickHouse | long-running |
| `clickhouse` | เก็บ traces / logs / metrics / metadata | long-running |
| `keeper` | ClickHouse Keeper — coordination สำหรับ `ON CLUSTER` DDL | long-running |
| `user-scripts` | โหลด binary `histogramQuantile` ลง shared volume | run-once |
| `migrator` | สร้างและอัปเดต schema ของ ClickHouse | run-once (ทุกครั้งที่ deploy) |

### การตัดสินใจเชิงโครงสร้าง

**ตัด `postgres` ออก ใช้ SQLite แทน**
ยืนยันจาก `pkg/sqlstore/config.go` ของ SigNoz v0.137.1 ว่า default provider คือ `sqlite`
path `/var/lib/signoz/signoz.db` mode `wal` — แค่ mount volume ที่ `/var/lib/signoz`
ไม่ต้องตั้ง DSN ใดๆ ประหยัด RAM ~250 MB
SigNoz ใช้ที่นี่เก็บแค่ dashboard / alert rule / user เท่านั้น telemetry จริงอยู่ใน ClickHouse

**คง `keeper` ไว้ ตัดไม่ได้**
`config-0-0.yaml` ประกาศ `remote_servers.cluster` ไว้ และ migrator สร้างตารางด้วย
`ON CLUSTER cluster` ซึ่งต้องมี coordination service เสมอ แม้จะรัน node เดียว
(ClickHouse Keeper เบากว่า ZooKeeper เดิมมากเพราะไม่ใช่ JVM)

---

## 3. งบประมาณ memory

เป้าหมาย: host 4 GB กัน OS + Portainer ไว้ ~600 MB

| Service | `mem_limit` | จูนเพิ่ม |
|---|---:|---|
| `clickhouse` | 1.4 g | ดูตารางค่าจูนด้านล่าง |
| `signoz` | 600 m | — |
| `ingester` | 400 m | `send_batch_size` 50000 → 5000, เพิ่ม `memory_limiter` ทั้งใน `processors:` และใน `service.pipelines.*.processors` ทุก pipeline (เป็นตัวแรกเสมอ) |
| `keeper` | 200 m | `snapshots_to_keep: 2` |
| `migrator` / `user-scripts` | 256 m | run-once คืน RAM หลังจบ |
| **รวมตอนรัน** | **~2.6 g** | headroom ~800 MB สำหรับ merge / query spike |

**ต้องใช้ `max_server_memory_usage` เป็นตัวเลขไบต์ตายตัว ห้ามใช้ ratio**
`max_server_memory_usage_to_ram_ratio` อ่าน RAM ของ host ไม่ใช่ของ cgroup
บนเครื่อง 4 GB มันจะคำนวณจาก 4 GB แล้วจองเกิน `mem_limit` → โดน OOM-kill

### ค่าจูน ClickHouse ทั้งหมด

ยืนยันชื่อและค่า default จาก source ของ ClickHouse `v25.12.5.44-stable` โดยตรง
(`src/Core/ServerSettings.cpp`, `src/Core/Defines.h`) ทุกตัวเป็น server setting ระดับ root ของ config

| Setting | default ของ ClickHouse | ค่าที่เราตั้ง | เหตุผล |
|---|---:|---:|---|
| `max_server_memory_usage` | `0` (ไม่จำกัด) | `1073741824` (1 GiB) | เพดานตายตัว ไม่พึ่ง ratio |
| `mark_cache_size` | `5 GiB` | `268435456` (256 MiB) | default ตั้งมาสำหรับ server ระดับ production |
| `index_mark_cache_size` | `5 GiB` | `134217728` (128 MiB) | ตัวคู่ของ mark cache รวมกัน default 10 GiB |
| `background_pool_size` | `16` | `4` | จำกัด merge ที่รันพร้อมกัน |
| `background_merges_mutations_concurrency_ratio` | `2` | `2` | คงเดิม |
| `background_common_pool_size` | `8` | `2` | งาน GC ของ MergeTree |
| `background_schedule_pool_size` | `512` | `32` | 512 thread เป็นตัวเลขสำหรับ cluster ใหญ่ |

`uncompressed_cache_size` **ไม่ต้องตั้ง** — `DEFAULT_UNCOMPRESSED_CACHE_MAX_SIZE` เป็น `0` อยู่แล้ว

### ปิด system log tables ของ ClickHouse

config ที่ Foundry generate เปิดไว้ทั้งหมด: `metric_log`, `trace_log`, `text_log`,
`query_thread_log`, `query_views_log`, `latency_log`, `session_log`,
`processors_profile_log`, `part_log`, `asynchronous_metric_log`, `query_metric_log`,
`error_log`, `zookeeper_log`

**เก็บไว้เฉพาะ `query_log`** (มีประโยชน์ตอน debug ว่า query ไหนช้า) ที่เหลือปิดหมด
ประหยัดทั้ง RAM buffer และลด background merge ที่เป็นสาเหตุหลักของ OOM บนเครื่องเล็ก

**วิธีปิดคือลบ key ทิ้งเฉยๆ ไม่ต้องใช้ `remove="1"`** — `src/Interpreters/SystemLog.cpp:167`
เขียนไว้ว่า `if (!config.has(config_prefix))` แล้ว log ว่า *"Not creating X.Y since corresponding
section is missing from config"* แปลว่า system log ถูกสร้างต่อเมื่อมี section ใน config เท่านั้น
config ของ SigNoz ที่ list ทุก log ไว้คือตัวที่เปิดมันด้วยตัวเอง

ใช้ได้เพราะ `CLICKHOUSE_CONFIG` ชี้ไปที่ `config-0-0.yaml` ซึ่ง **แทนที่** config หลักของ image ทั้งหมด
ไม่ใช่การ merge ทับ

---

## 4. การฝัง config

### การ map ทั้ง 5 ตัว

| `configs:` key | target ในคอนเทนเนอร์ | service | เปลี่ยนชื่อได้ |
|---|---|---|---|
| `ingester-config` | `/etc/otel-collector-config.yaml` | ingester | ได้ (`--config=`) |
| `ingester-opamp` | `/etc/opamp-config.yaml` | ingester | ได้ (`--manager-config=`) |
| `keeper-config` | `/etc/clickhouse-keeper/keeper.yaml` | keeper | ได้ (`--config-file=`) |
| `clickhouse-config` | `/etc/clickhouse-server/config-0-0.yaml` | clickhouse | **ไม่ได้** |
| `clickhouse-functions` | `/etc/clickhouse-server/functions.yaml` | clickhouse | **ไม่ได้** |

สองตัวสุดท้ายเปลี่ยนชื่อไม่ได้เพราะ `config-0-0.yaml` อ้างอิงตัวเอง:

```yaml
user_directories:
  users_xml:
    path: config-0-0.yaml                            # ชี้กลับมาที่ตัวเอง
user_defined_executable_functions_config: '*functions.yaml'   # glob ใน /etc/clickhouse-server/
```

ต้องตั้ง `CLICKHOUSE_CONFIG=/etc/clickhouse-server/config-0-0.yaml` ให้ตรงกัน
ถ้าพลาด ClickHouse จะขึ้นโดยไม่มี user `default` → ทุก service ต่อไม่ได้

### กับดัก: `${env:...}` ทำให้ deploy ไม่ผ่าน

`ingester.yaml` ของ upstream มีบรรทัด:

```yaml
low_cardinal_exception_grouping: ${env:LOW_CARDINAL_EXCEPTION_GROUPING}
```

Docker Compose interpolate `${...}` ทั้งไฟล์ รวมถึงข้างใน `content:` ที่ตั้งใจให้เป็นข้อความดิบ
และ `env:LOW_...` มี `:` ซึ่งผิดไวยากรณ์ → deploy ไม่ผ่านตั้งแต่ parse

**ยืนยันด้วยการทดสอบจริง** (Docker Compose v5.3.1):

```
$ docker compose -f t-raw.yaml config
invalid interpolation format for configs.probe.content.
You may need to escape any $ with another $.
low_cardinal_exception_grouping: ${env:LOW_CARDINAL_EXCEPTION_GROUPING}
```

escape เป็น `$$` แล้ว parse ผ่าน และรันคอนเทนเนอร์ `cat` ไฟล์ออกมาได้ `${env:...}` ตัวจริงกลับมาถูกต้อง

**การตัดสินใจ: ไม่ escape แต่เขียนค่าตายตัว `low_cardinal_exception_grouping: false`**
เหตุผล: การ escape แก้ปัญหาแค่ครึ่งเดียว — ต่อให้ parse ผ่าน otel-collector ก็ยัง crash
ตอน start ถ้าไม่ได้ตั้ง env var นั้น การกำจัด indirection ทิ้งจบทั้งสองปัญหา
และ Portainer ไม่ต้องจำว่าต้องตั้ง env อะไรบ้าง

---

## 5. Version pinning

`casting.yaml.lock` ของ Foundry เขียน `image: signoz/signoz:latest`, `version: latest` ตรงๆ
— **แม้แต่ไฟล์ที่ชื่อ lock ก็ไม่ได้ lock จริง** บน Portainer อันตรายเพราะปุ่ม
"Update the stack" จะ pull ทับแล้วอาจกระโดดข้าม schema migration

pin ตามที่ตรวจสอบจาก Docker Hub เมื่อ 2026-08-18:

| Image | Tag |
|---|---|
| `signoz/signoz` | `v0.137.1` |
| `signoz/signoz-otel-collector` | `v0.144.8` |
| `clickhouse/clickhouse-server` | `25.12.5` |
| `clickhouse/clickhouse-keeper` | `25.12.5` |

`signoz` กับ `signoz-otel-collector` เดินคนละสาย version — เวลาอัปเกรดต้องขยับพร้อมกันเสมอ
จดคู่ที่ใช้ไว้ใน README

---

## 6. การปรับให้เข้ากับ Portainer

- **ตัด `name: signoz` ระดับบนสุดออก** — ปล่อยให้ Portainer ตั้งชื่อ stack เอง
- **คง `networks.signoz-network.name: signoz-network` ไว้** — ชื่อ network ตายตัว
  เผื่อคอนเทนเนอร์ Carmen ต่อเข้ามาภายหลังด้วย `external: true`
- **ทำ port เป็นตัวแปร** เพื่อแก้ในช่อง Environment variables ของ Portainer ได้โดยไม่ต้องแก้ YAML

| ตัวแปร | ค่า default | ใช้ทำอะไร |
|---|---|---|
| `SIGNOZ_UI_PORT` | `8080` | port ของ UI บน host |
| `SIGNOZ_OTLP_GRPC_PORT` | `4317` | OTLP/gRPC |
| `SIGNOZ_OTLP_HTTP_PORT` | `4318` | OTLP/HTTP |
| `SIGNOZ_BIND_ADDR` | `0.0.0.0` | จำกัดให้ฟังเฉพาะ LAN ได้ |

### ข้อกำหนดเบื้องต้น

**Docker Compose ฝั่ง Portainer ต้อง >= 2.23.1** (ปล่อยพฤศจิกายน 2023)
เป็นเวอร์ชันแรกที่รองรับ `configs.content` ถ้าเก่ากว่านี้ต้องถอยไปแนวทาง B

---

## 7. Data flow และการต่อจาก Carmen

Carmen dev services รันคนละเครื่องกับ Portainer จึงต้อง publish port ออกมา

| Port | Protocol | ใช้กับ |
|---|---|---|
| `4317` | OTLP/gRPC | Go services (`micro-cronjobs`, `micro-report`, `micro-data`) |
| `4318` | OTLP/HTTP | NestJS, APISIX, browser |

**ไม่มี authentication** — SigNoz OSS ไม่มี ingestion key ใครยิงถึง port นี้ยัดข้อมูลเข้ามาได้ไม่จำกัด
ถ้าเครื่องมี public IP ให้ตั้ง `SIGNOZ_BIND_ADDR` เป็น IP ของ LAN interface

### แผนที่การ instrument (นอกสโคปของ spec นี้ บันทึกไว้เพื่อรอบถัดไป)

| Repo | Tech | วิธีต่อ |
|---|---|---|
| `api-gateway-apisix` | APISIX | เปิด plugin `opentelemetry` — **แนะนำเริ่มที่นี่** ได้ trace ครอบทุก request โดยไม่แก้โค้ด |
| `carmen-turborepo-backend-v2` | NestJS 11 + Bun | `@opentelemetry/sdk-node` + `OTEL_EXPORTER_OTLP_ENDPOINT` — ดูความเสี่ยงด้านล่าง |
| `carmen` (micro-business) | NestJS + Prisma | เหมือนบน + `@prisma/instrumentation` |
| `micro-cronjobs` / `micro-report` / `micro-data` | Go + Gin | `otelgin` + `otlptracegrpc` → `:4317` |
| `carmen-inventory-frontend-react` | React 19 + Vite | ต้องเพิ่ม CORS ที่ receiver ก่อน ดูด้านล่าง |

**ความเสี่ยง: OTel auto-instrumentation บน Bun**
`carmen-turborepo-backend-v2` รันบน Bun ซึ่ง OTel auto-instrumentation ของ Node
พึ่งการ monkey-patch `require` (`require-in-the-middle`) ที่ Bun รองรับไม่ครบ
อาจเก็บ span ของ HTTP/Prisma ไม่ได้เลยแม้ SDK จะ start ผ่าน
ทางถอย: (ก) พึ่ง trace จาก APISIX ที่ edge แทน หรือ (ข) manual instrumentation เฉพาะจุดสำคัญ

**ถ้าจะเอา React frontend เข้าด้วย ต้องเพิ่ม CORS**
receiver ตัว default ไม่มี `cors` เลย browser จะโดนปฏิเสธตอน preflight `OPTIONS`
ต้องเพิ่มใน `ingester-config`:

```yaml
      http:
        endpoint: 0.0.0.0:4318
        cors:
          allowed_origins:
            - http://localhost:5173
```

---

## 8. Operations

### Retention — ขั้นตอนบังคับหลัง deploy

ตั้งใน compose ไม่ได้ ต้องเข้า SigNoz UI → Settings → Retention
default คือ traces/logs 15 วัน, metrics 30 วัน ซึ่งมากเกินไปสำหรับเครื่องนี้

**ค่าที่กำหนด: traces 3 วัน · logs 3 วัน · metrics 7 วัน**

ถ้าลืมตั้ง disk จะเต็มแล้ว ClickHouse จะเข้าสถานะ read-only
หมายเหตุ: ClickHouse ลบข้อมูลด้วย TTL ที่ทำงานตอน background merge
disk จะไม่ลดทันทีหลังลด retention ต้องรอ merge รอบถัดไป

### เรื่องอื่น

| เรื่อง | วิธีทำ |
|---|---|
| อัปเกรด | แก้ tag ใน Portainer editor → Update stack → `migrator` รัน migration อัตโนมัติ ต้องขยับ `signoz` กับ `signoz-otel-collector` พร้อมกัน |
| Backup | volume `signoz-metastore-sqlite-0-data` เท่านั้น (dashboard/alert ที่สร้างเอง) ClickHouse volume เป็น telemetry ชั่วคราว ไม่ต้อง backup |
| ดู log ตอนพัง | เรียงลำดับ: `keeper` → `user-scripts` → `clickhouse` → `migrator` → `signoz` → `ingester` |
| Reset ทั้งหมด | ลบ stack + ลบ volume ทั้ง 4 ตัว แล้ว deploy ใหม่ |

### Volumes

| Volume | เนื้อหา | สำคัญ |
|---|---|---|
| `signoz-telemetrystore-0-0-data` | ข้อมูล ClickHouse | ใหญ่สุด แต่ generate ใหม่ได้ |
| `signoz-metastore-sqlite-0-data` | dashboard, alert rule, user | **เล็กแต่สำคัญที่สุด** |
| `signoz-telemetrykeeper-0-data` | keeper coordination log/snapshot | สร้างใหม่ได้ |
| `signoz-telemetrystore-user-scripts` | binary `histogramQuantile` | โหลดใหม่ได้ |

---

## 9. Failure modes

| # | อาการที่เห็น | สาเหตุจริง | ทางแก้ |
|---|---|---|---|
| 1 | Portainer error ทันทีตอน Deploy | compose < 2.23.1 ไม่รู้จัก `configs.content` | ถอยไปแนวทาง B |
| 2 | `clickhouse` ไม่ขึ้น, `user-scripts` restart วน | โหลด `histogramQuantile` จาก GitHub ไม่ได้ | เช็คเน็ตขาออกของ host |
| 3 | `clickhouse` ตายเป็นรอบ **exit 137** | OOM-kill | ลด `max_server_memory_usage` |
| 4 | "port is already allocated" | port ชนของเดิม | เปลี่ยนค่าในช่อง env ของ Portainer |
| 5 | `migrator` restart วนไม่จบ | ClickHouse ยังไม่พร้อม / cluster config ผิด | ปกติหายเอง ถ้าไม่หาย = ปัญหา `ON CLUSTER` |
| 6 | UI ขึ้นแต่ไม่มีข้อมูล / query error | disk เต็ม ClickHouse read-only | ลด retention |

`user-scripts` เป็น hard dependency ของ `clickhouse` ผ่าน
`depends_on: condition: service_completed_successfully` — ได้ ordering ที่ถูกต้อง
แต่แลกด้วยการที่ transient failure (เน็ตหลุดตอนโหลด binary) จะบล็อกทั้ง stack

exit code 137 = 128 + 9 (SIGKILL) เป็นลายเซ็นของ OOM-killer เสมอ
ส่วน 143 = 128 + 15 (SIGTERM) คือการปิดปกติ

---

## 10. แผนการตรวจสอบ

ไม่เขียน automated test (ตาม working preference) แต่ manual verification ทำครบ 3 ด่าน

**ด่าน 1 — parse บนเครื่อง dev (บังคับ)**

```bash
docker compose -f docker-compose.signoz-portainer.yaml config
```

จับ YAML ผิด, interpolation ผิด, key สะกดผิด โดยไม่ต้องดึง image
เป็นด่านที่จับกับดัก `${env:...}` ได้ตั้งแต่แรก

**ด่าน 2 — ยกทั้ง stack ขึ้นจริงบน Mac (แนะนำ)**

พิสูจน์ว่า service ขึ้นครบ 6 ตัว, migration ผ่าน, UI เปิดได้ที่ `localhost:8080`
ข้อจำกัด: Mac มี RAM มากกว่า 4 GB ด่านนี้พิสูจน์ **correctness** ได้
แต่พิสูจน์ **ว่าอยู่ในงบ RAM** ไม่ได้ ต้องไปวัดจริงบน Portainer

**ด่าน 3 — smoke test หลัง deploy บน Portainer**

ยิง trace ปลอม 1 span ด้วย `curl` เปล่าๆ ไม่ต้องลง SDK:

```bash
curl -X POST http://<host>:4318/v1/traces \
  -H 'Content-Type: application/json' \
  -d @test-trace.json
```

เข้า UI → Services ต้องเห็น service ทดสอบภายใน ~30 วินาที
ถ้าเห็น = ครบทั้งเส้น ingester → ClickHouse → query → UI ทำงานจริง

---

## 11. สิ่งที่ส่งมอบ

1. `docker-compose.signoz-portainer.yaml` — ไฟล์เดียว paste ลง Portainer ได้เลย
2. `README.md` — checklist ก่อน deploy, ตาราง env vars, ขั้นตอนตั้ง retention,
   ตารางแก้ปัญหาตามข้อ 9, ตัวอย่าง payload สำหรับ smoke test
3. spec ฉบับนี้

## 12. นอกสโคป

- การ instrument Carmen services ทุกตัว (บันทึกแผนที่ไว้ในข้อ 7 แล้ว)
- CORS สำหรับ React frontend (บันทึกวิธีทำไว้ในข้อ 7 แล้ว)
- Reverse proxy / TLS / authentication หน้า SigNoz UI
- `signoz-mcp-server` (Foundry มีให้แต่ปิดไว้ default)
- High availability, multi-shard, multi-replica

## 13. เรื่องที่ยังไม่รู้ ต้องเช็คตอน implement

| เรื่อง | ทำไมสำคัญ | เช็คยังไง |
|---|---|---|
| เวอร์ชัน Docker Compose ของ Portainer | ต้อง >= 2.23.1 ไม่งั้นทั้งแนวทางใช้ไม่ได้ | ดูในหน้า Portainer |
| disk ว่างบน host | ClickHouse โตเรื่อยๆ ถ้าเต็มจะ read-only | ดูใน Portainer → Host |
| CPU architecture ของ host | amd64/arm64 | ทั้ง 4 image มีทั้งสอง arch — น่าจะไม่มีปัญหา |
| RAM ที่เหลือจริงหลังหัก Portainer | งบ 2.6 g ตั้งบนสมมติฐานว่าเหลือ ~3.4 g | ดูใน Portainer → Host |
