# SigNoz on Portainer — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** สร้าง Docker Compose ไฟล์เดียวที่ paste ลง Portainer web editor แล้วรัน SigNoz ได้ทันที บนเครื่อง ~4 GB โดยไม่ต้องมีไฟล์ใดๆ บน host

**Architecture:** SigNoz เลิกแจก compose แล้ว ทางที่ upstream รองรับ (Foundry) generate compose ที่ bind-mount config 5 ไฟล์จาก host ซึ่ง Portainer web editor ไม่มี แผนนี้ vendor ไฟล์ต้นฉบับจาก upstream ไว้ให้ตรวจสอบได้ แล้ว flatten config ทั้งหมดเข้าไฟล์ compose ผ่าน `configs:` + `content:` พร้อมตัด Postgres ออกใช้ SQLite และจูน memory ทุก service ให้อยู่ในงบ ~2.6 GB

**Tech Stack:** Docker Compose Spec (`configs.content`), ClickHouse 25.12.5, ClickHouse Keeper 25.12.5, SigNoz v0.137.1, signoz-otel-collector v0.144.8

**Spec:** `docs/superpowers/specs/2026-08-18-signoz-portainer-design.md`

## หมายเหตุเรื่องการทดสอบ

โปรเจกต์นี้เป็น infrastructure config ไม่มี automated test และตาม working preference
ของเจ้าของโปรเจกต์ **ห้ามสร้างไฟล์ `*.test.*` / `*.spec.*`**

แต่ **static check และ manual verification ไม่ถูกข้าม** — ทุก task จบด้วยขั้นตอนตรวจสอบจริง
(`docker compose config`, ยก stack ขึ้น, query ClickHouse, ยิง trace เข้าไปดู)
ขั้นตอนเหล่านี้คือ gate ของ task ห้ามข้าม ห้าม commit ถ้ายังไม่ผ่าน

## Global Constraints

- **Docker Compose >= 2.23.1** ทั้งฝั่ง dev และฝั่ง Portainer (เวอร์ชันแรกที่รองรับ `configs.content`)
- **Portainer environment:** Standalone Docker + Stacks ไม่ใช่ Swarm
- **Image tags ต้อง pin เสมอ ห้ามใช้ `latest`:** `signoz/signoz:v0.137.1`,
  `signoz/signoz-otel-collector:v0.144.8`, `clickhouse/clickhouse-server:25.12.5`,
  `clickhouse/clickhouse-keeper:25.12.5`
- **งบ memory รวมตอนรัน <= 2.6 GB** — `mem_limit` ต่อ service:
  clickhouse `1400m`, signoz `600m`, ingester `400m`, keeper `200m`,
  migrator `256m`, user-scripts `256m`
- **ห้ามใช้ `max_server_memory_usage_to_ram_ratio`** ใช้ `max_server_memory_usage` เป็นไบต์ตายตัวเท่านั้น
  (ratio อ่าน RAM ของ host ไม่ใช่ cgroup)
- **`background_pool_size` x `background_merges_mutations_concurrency_ratio` ต้อง >= 25**
  ClickHouse เช็คตอน boot ที่ `MergeTreeSettings.cpp` sanityCheck เทียบกับ default ของ
  `number_of_free_entries_in_pool_to_execute_optimize_entire_partition` (25) ถ้าต่ำกว่านี้
  server จะไม่ start เลย (exit 36) ค่าที่ใช้: 4 x 7 = 28
- **ห้ามมี relative bind mount ใดๆ** ใน compose ไฟล์ deliverable — config ทุกตัวต้องผ่าน `configs.content`
- **ห้ามมี `${...}` ที่ไม่ใช่ตัวแปรของ Portainer** อยู่ใน `configs.content`
- **ห้ามใส่ `name:` ระดับบนสุด** ใน compose (ให้ Portainer ตั้งชื่อ stack เอง)
- **ชื่อไฟล์ target ของ ClickHouse ห้ามเปลี่ยน:** ต้องเป็น
  `/etc/clickhouse-server/config-0-0.yaml` และ `/etc/clickhouse-server/functions.yaml`
- Hostname ที่ config อ้างถึงต้อง resolve ได้ ประกาศเป็น network alias ทุกตัว:
  `signoz-telemetrystore-clickhouse-0-0`, `signoz-telemetrykeeper-clickhousekeeper-0`,
  `signoz-signoz-0`, `signoz-ingester`

---

## File Structure

| ไฟล์ | หน้าที่ | สร้างใน task |
|---|---|---|
| `reference/upstream/PROVENANCE.md` | บันทึกว่าไฟล์อ้างอิงมาจาก commit ไหน ดึงมาเมื่อไหร่ | Task 1 |
| `reference/upstream/compose.yaml` | compose ที่ Foundry generate (ต้นฉบับ ห้ามแก้) | Task 1 |
| `reference/upstream/ingester.yaml` | config otel-collector ต้นฉบับ | Task 1 |
| `reference/upstream/opamp.yaml` | config opamp ต้นฉบับ | Task 1 |
| `reference/upstream/keeper-0.yaml` | config keeper ต้นฉบับ | Task 1 |
| `reference/upstream/config-0-0.yaml` | config ClickHouse ต้นฉบับ | Task 1 |
| `reference/upstream/functions.yaml` | นิยาม UDF ต้นฉบับ | Task 1 |
| `docker-compose.signoz-portainer.yaml` | **deliverable หลัก** สร้างทีละชั้น | Task 2→5 |
| `smoke-test/send-trace.sh` | ยิง trace ปลอมเข้า OTLP/HTTP เพื่อพิสูจน์เส้นทางทั้งเส้น | Task 4 |
| `.env.example` | เอกสารตัวแปรที่ตั้งได้ในช่อง env ของ Portainer | Task 5 |
| `README.md` | checklist ก่อน deploy, ขั้นตอน, retention, ตารางแก้ปัญหา | Task 6 |

`reference/upstream/` มีไว้เพื่อ **ตรวจสอบย้อนกลับได้** — เวลาอัปเกรด SigNoz
จะ diff ไฟล์ต้นฉบับชุดใหม่กับชุดเก่าเพื่อดูว่า upstream เปลี่ยนอะไร แล้วค่อยตัดสินใจว่า
ต้องแก้ compose ของเราตรงไหน ห้ามแก้ไฟล์ใน `reference/` ด้วยมือเด็ดขาด

Compose ถูกสร้างเป็นชั้นๆ ตามลำดับที่ debug จริง: storage → schema → app → portainer
แต่ละชั้นยกขึ้นรันได้และตรวจสอบได้ด้วยตัวเอง

---

## Task 1: Vendor upstream reference artifacts

**Files:**
- Create: `reference/upstream/PROVENANCE.md`
- Create: `reference/upstream/compose.yaml`
- Create: `reference/upstream/ingester.yaml`
- Create: `reference/upstream/opamp.yaml`
- Create: `reference/upstream/keeper-0.yaml`
- Create: `reference/upstream/config-0-0.yaml`
- Create: `reference/upstream/functions.yaml`

**Interfaces:**
- Consumes: ไม่มี
- Produces: ไฟล์อ้างอิง 6 ตัวใน `reference/upstream/` ที่ task 2-4 จะคัดลอกเนื้อหาไปดัดแปลง

- [ ] **Step 1: ดึงไฟล์ต้นฉบับจาก commit ที่ pin ไว้**

```bash
mkdir -p reference/upstream
SHA=6480868715f3f8ade6e0592f8e27197a986635d0
BASE="https://raw.githubusercontent.com/SigNoz/foundry/${SHA}/docs/examples/docker/compose/pours/deployment"

curl -fsS "${BASE}/compose.yaml"                                    -o reference/upstream/compose.yaml
curl -fsS "${BASE}/ingester/ingester.yaml"                          -o reference/upstream/ingester.yaml
curl -fsS "${BASE}/ingester/opamp.yaml"                             -o reference/upstream/opamp.yaml
curl -fsS "${BASE}/telemetrykeeper/clickhousekeeper/keeper-0.yaml"  -o reference/upstream/keeper-0.yaml
curl -fsS "${BASE}/telemetrystore/clickhouse/config-0-0.yaml"       -o reference/upstream/config-0-0.yaml
curl -fsS "${BASE}/telemetrystore/clickhouse/functions.yaml"        -o reference/upstream/functions.yaml
```

- [ ] **Step 2: ยืนยันว่าได้ไฟล์ครบและไม่ใช่หน้า 404**

```bash
wc -l reference/upstream/*.yaml
```

คาดหวัง (บรรทัดอาจต่างได้ ±2 ถ้า upstream ขยับ แต่ลำดับขนาดต้องใกล้เคียงนี้):

```
     177 reference/upstream/compose.yaml
      96 reference/upstream/config-0-0.yaml
      13 reference/upstream/functions.yaml
     132 reference/upstream/ingester.yaml
      22 reference/upstream/keeper-0.yaml
       1 reference/upstream/opamp.yaml
```

ถ้าไฟล์ไหนได้ 0 บรรทัดหรือมีคำว่า `404: Not Found` แปลว่า path ที่ upstream เปลี่ยน
**หยุดแล้วรายงาน** อย่าเดา path ใหม่เอง

- [ ] **Step 3: ยืนยันว่ากับดัก `${env:...}` ยังอยู่จริงในต้นฉบับ**

```bash
grep -n 'env:' reference/upstream/ingester.yaml
```

คาดหวัง:

```
17:    low_cardinal_exception_grouping: ${env:LOW_CARDINAL_EXCEPTION_GROUPING}
```

ถ้าไม่เจอ แปลว่า upstream แก้ไปแล้ว — บันทึกไว้ใน PROVENANCE.md แต่ยังทำ task ต่อได้

- [ ] **Step 4: เขียน PROVENANCE.md**

```bash
cat > reference/upstream/PROVENANCE.md <<'EOF'
# ที่มาของไฟล์ในโฟลเดอร์นี้

ไฟล์ทั้งหมดในโฟลเดอร์นี้เป็น **ต้นฉบับจาก upstream ห้ามแก้ด้วยมือ**
มีไว้เพื่อ diff ตอนอัปเกรด SigNoz เท่านั้น

| รายการ | ค่า |
|---|---|
| repo | https://github.com/SigNoz/foundry |
| commit | `6480868715f3f8ade6e0592f8e27197a986635d0` (branch `main`) |
| path | `docs/examples/docker/compose/pours/deployment/` |
| ดึงมาเมื่อ | 2026-08-18 |

ไฟล์เหล่านี้คือผลลัพธ์ของ `foundryctl forge` ที่ SigNoz commit ไว้เป็นตัวอย่าง
เทียบเท่ากับการรัน Foundry เอง โดยไม่ต้องติดตั้ง `foundryctl`

## ความต่างจาก compose ที่เราใช้จริง

`docker-compose.signoz-portainer.yaml` ที่ root ของ repo **ไม่ใช่** ไฟล์เหล่านี้
ความต่างที่ตั้งใจ:

1. ตัด service `signoz-metastore-postgres-0` ออก ใช้ SQLite ที่เป็น default ของ SigNoz แทน
2. config ทั้ง 5 ไฟล์ถูก inline เข้า compose ผ่าน `configs.content` แทน bind mount
3. `low_cardinal_exception_grouping` เขียนค่า `false` ตายตัว แทน `${env:...}`
   (ถ้าไม่ทำ Docker Compose จะ parse ไม่ผ่านเพราะ `:` ในชื่อตัวแปร)
4. ปิด system log tables ของ ClickHouse ทั้งหมดยกเว้น `query_log` ด้วยการลบ key ทิ้ง
   (`src/Interpreters/SystemLog.cpp` สร้าง log ต่อเมื่อมี section ใน config)
5. เพิ่มการจูน memory: `max_server_memory_usage`, `mark_cache_size`,
   `index_mark_cache_size`, `background_*_pool_size`, `memory_limiter` processor
6. pin image tag ทุกตัว (upstream ใช้ `latest` แม้ในไฟล์ที่ชื่อ `.lock`)
7. ทำ port และ bind address เป็นตัวแปรสำหรับช่อง env ของ Portainer

## วิธีอัปเดตตอนอัปเกรด SigNoz

```bash
# ดึงชุดใหม่ทับ แล้วดูว่า upstream เปลี่ยนอะไร
git diff reference/upstream/
```

ถ้า `config-0-0.yaml` หรือ `ingester.yaml` เปลี่ยน ต้องเอาความเปลี่ยนแปลงนั้น
มาใส่ใน `configs.content` ของ compose เราด้วยมือ พร้อมคงการดัดแปลง 7 ข้อข้างบนไว้
EOF
```

- [ ] **Step 5: Commit**

```bash
git add reference/
git commit -m "chore: vendor upstream SigNoz Foundry manifests for reference"
```

---

## Task 2: ชั้น storage — ClickHouse + Keeper

**Files:**
- Create: `docker-compose.signoz-portainer.yaml`

**Interfaces:**
- Consumes: `reference/upstream/config-0-0.yaml`, `reference/upstream/keeper-0.yaml` (คัดลอกเนื้อหามาดัดแปลง)
- Produces:
  - compose services: `keeper`, `clickhouse`
  - network alias: `signoz-telemetrystore-clickhouse-0-0` (พอร์ต 9000 native, 8123 http),
    `signoz-telemetrykeeper-clickhousekeeper-0` (พอร์ต 9181 client, 9234 raft)
  - volumes: `signoz-telemetrykeeper-0-data`, `signoz-telemetrystore-0-0-data`
  - configs: `keeper-config`, `clickhouse-config`
  - network: `signoz-network`

ชั้นนี้ยังไม่มี `functions.yaml`, ไม่มี `user-scripts` และไม่มี `depends_on` ของ user-scripts
— จะเพิ่มใน Task 3 พร้อมกัน ตอนนี้ `user_defined_executable_functions_config: '*functions.yaml'`
จะ glob ไม่เจออะไร ซึ่งไม่ใช่ error

- [ ] **Step 1: สร้างไฟล์ compose ชั้น storage**

```yaml
# docker-compose.signoz-portainer.yaml
#
# SigNoz single-node สำหรับ Portainer (Standalone Docker + Stacks)
# config ทุกตัว inline อยู่ในไฟล์นี้ — ไม่ต้องมีไฟล์ใดๆ บน host
#
# ห้ามใส่ `name:` ระดับบนสุด ปล่อยให้ Portainer ตั้งชื่อ stack เอง

networks:
  signoz-network:
    name: signoz-network

volumes:
  signoz-telemetrykeeper-0-data:
    name: signoz-telemetrykeeper-0-data
  signoz-telemetrystore-0-0-data:
    name: signoz-telemetrystore-0-0-data

configs:

  keeper-config:
    content: |
      listen_host: 0.0.0.0
      logger:
        level: information
        console: true
      keeper_server:
        four_letter_word_white_list: "*"
        coordination_settings:
          operation_timeout_ms: 10000
          raft_logs_level: warning
          session_timeout_ms: 30000
          force_sync: false
          snapshot_distance: 100000
          snapshots_to_keep: 2
        log_storage_path: /var/lib/clickhouse-keeper/coordination/log
        raft_configuration:
          server:
            - hostname: signoz-telemetrykeeper-clickhousekeeper-0
              port: 9234
              id: 0
        server_id: 0
        snapshot_storage_path: /var/lib/clickhouse-keeper/coordination/snapshots
        tcp_port: 9181

  clickhouse-config:
    content: |
      path: /var/lib/clickhouse/
      tmp_path: /var/lib/clickhouse/tmp/
      user_files_path: /var/lib/clickhouse/user_files/
      user_scripts_path: /var/lib/clickhouse/user_scripts/
      format_schema_path: /var/lib/clickhouse/format_schemas/
      dictionaries_config: '*_dictionary.xml'
      user_defined_executable_functions_config: '*functions.yaml'
      display_name: cluster
      listen_host: 0.0.0.0
      http_port: 8123
      tcp_port: 9000
      interserver_http_port: 9009
      distributed_ddl:
        path: /clickhouse/task_queue/ddl
      logger:
        console: 1
        count: 3
        size: 100M
        level: information
        formatting:
          type: console
      macros:
        replica: "00"
        shard: "00"
      max_server_memory_usage: 1073741824
      mark_cache_size: 268435456
      index_mark_cache_size: 134217728
      background_pool_size: 4
      background_merges_mutations_concurrency_ratio: 7
      background_common_pool_size: 2
      background_schedule_pool_size: 32
      profiles:
        default:
          allow_simdjson: 0
          load_balancing: random
          log_queries: 1
      quotas:
        default:
          interval:
            duration: 3600
            errors: 0
            execution_time: 0
            queries: 0
            read_rows: 0
            result_rows: 0
      user_directories:
        users_xml:
          path: config-0-0.yaml
      users:
        default:
          access_management: 1
          named_collection_control: 1
          networks:
            ip: ::/0
          password: ""
          profile: default
          quota: default
          show_named_collection: 1
          show_named_collection_secrets: 1
      remote_servers:
        cluster:
          shard:
            - replica:
                - host: signoz-telemetrystore-clickhouse-0-0
                  port: 9000
      zookeeper:
        node:
          - host: signoz-telemetrykeeper-clickhousekeeper-0
            port: 9181
      query_log:
        flush_interval_milliseconds: 30000
        partition_by: toYYYYMM(event_date)
        ttl: "event_date + INTERVAL 1 DAY DELETE"

services:

  keeper:
    container_name: signoz-telemetrykeeper-clickhousekeeper-0
    image: clickhouse/clickhouse-keeper:25.12.5
    restart: unless-stopped
    mem_limit: 200m
    entrypoint:
      - /usr/bin/clickhouse-keeper
      - --config-file=/etc/clickhouse-keeper/keeper.yaml
    networks:
      signoz-network:
        aliases:
          - signoz-telemetrykeeper-clickhousekeeper-0
    configs:
      - source: keeper-config
        target: /etc/clickhouse-keeper/keeper.yaml
    volumes:
      - signoz-telemetrykeeper-0-data:/var/lib/clickhouse-keeper
    healthcheck:
      test: ["CMD", "clickhouse-keeper-client", "-h", "localhost", "-p", "9181", "-q", "ls"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

  clickhouse:
    container_name: signoz-telemetrystore-clickhouse-0-0
    image: clickhouse/clickhouse-server:25.12.5
    restart: unless-stopped
    mem_limit: 1400m
    environment:
      - CLICKHOUSE_SKIP_USER_SETUP=1
      - CLICKHOUSE_CONFIG=/etc/clickhouse-server/config-0-0.yaml
    depends_on:
      keeper:
        condition: service_healthy
    networks:
      signoz-network:
        aliases:
          - signoz-telemetrystore-clickhouse-0-0
    configs:
      - source: clickhouse-config
        target: /etc/clickhouse-server/config-0-0.yaml
    volumes:
      - signoz-telemetrystore-0-0-data:/var/lib/clickhouse
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:8123/ping"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
```

- [ ] **Step 2: static check — parse ให้ผ่านก่อนแตะ network**

```bash
docker compose -f docker-compose.signoz-portainer.yaml config >/dev/null && echo PARSE_OK
```

คาดหวัง: `PARSE_OK`

ถ้าเจอ `invalid interpolation format` แปลว่ามี `${` หลุดเข้าไปใน `content:`
ให้หาว่าอยู่บรรทัดไหนแล้วแก้ — ชั้นนี้ **ไม่ควรมี `${` เลยแม้แต่ตัวเดียว**

- [ ] **Step 3: ยกขึ้นจริง**

```bash
docker compose -f docker-compose.signoz-portainer.yaml up -d
docker compose -f docker-compose.signoz-portainer.yaml ps
```

คาดหวัง: ทั้ง `keeper` และ `clickhouse` สถานะ `Up` และ `(healthy)` ภายใน ~90 วินาที

- [ ] **Step 4: ยืนยันว่า ClickHouse ต่อ Keeper ได้จริง**

```bash
docker exec signoz-telemetrystore-clickhouse-0-0 clickhouse-client -q "SELECT 1"
docker exec signoz-telemetrystore-clickhouse-0-0 clickhouse-client -q \
  "SELECT cluster, shard_num, host_name FROM system.clusters FORMAT PrettyCompact"
docker exec signoz-telemetrystore-clickhouse-0-0 clickhouse-client -q \
  "SELECT name FROM system.zookeeper WHERE path = '/' FORMAT PrettyCompact"
```

คาดหวัง: `1`, แถว cluster ชื่อ `cluster` ที่ host เป็น `signoz-telemetrystore-clickhouse-0-0`,
และ query `system.zookeeper` ต้องไม่ error (ถ้า error = ต่อ Keeper ไม่ได้)

- [ ] **Step 5: ยืนยันว่าการจูน memory ถูกใช้จริง**

```bash
docker exec signoz-telemetrystore-clickhouse-0-0 clickhouse-client -q \
  "SELECT name, value FROM system.server_settings
   WHERE name IN ('max_server_memory_usage','mark_cache_size','index_mark_cache_size',
                  'background_pool_size','background_merges_mutations_concurrency_ratio',
                  'background_common_pool_size','background_schedule_pool_size')
   ORDER BY name FORMAT PrettyCompact"
```

คาดหวังค่าเหล่านี้เป๊ะๆ:

```
background_common_pool_size                      2
background_merges_mutations_concurrency_ratio    7
background_pool_size                             4
background_schedule_pool_size                    32
index_mark_cache_size           134217728
mark_cache_size                 268435456
max_server_memory_usage         1073741824
```

ถ้าได้ค่า default (`16`, `2`, `8`, `512`, `5368709120`, `0`) แปลว่า ClickHouse ไม่ได้อ่าน
config ของเรา ให้เช็คว่า `CLICKHOUSE_CONFIG` ชี้ path ถูกต้องหรือไม่ **อย่าไปต่อจนกว่าจะผ่าน**

- [ ] **Step 6: ยืนยันว่า system log tables ถูกปิดจริง**

```bash
docker exec signoz-telemetrystore-clickhouse-0-0 clickhouse-client -q \
  "SELECT name FROM system.tables WHERE database = 'system' AND name LIKE '%_log' ORDER BY name"
```

คาดหวัง: ว่างเปล่า หรือมีแค่ `query_log` เท่านั้น
ห้ามมี `metric_log`, `trace_log`, `text_log`, `part_log`, `query_thread_log`,
`asynchronous_metric_log`, `processors_profile_log`

(ตาราง system log ถูกสร้างแบบ lazy ตอน flush ครั้งแรก ถ้ายังว่างอยู่ก็ถือว่าผ่าน)

- [ ] **Step 7: ล้างของทิ้งแล้ว commit**

```bash
docker compose -f docker-compose.signoz-portainer.yaml down
git add docker-compose.signoz-portainer.yaml
git commit -m "feat: add storage layer (ClickHouse + Keeper) with inline configs and memory tuning"
```

---

## Task 3: ชั้น schema — user-scripts + migrator

**Files:**
- Modify: `docker-compose.signoz-portainer.yaml`

**Interfaces:**
- Consumes: services `keeper`, `clickhouse` จาก Task 2
- Produces:
  - compose services: `user-scripts` (run-once), `migrator` (run-once)
  - volume: `signoz-telemetrystore-user-scripts`
  - config: `clickhouse-functions`
  - ClickHouse databases: `signoz_traces`, `signoz_logs`, `signoz_metrics`,
    `signoz_metadata`, `signoz_meter`
  - ClickHouse UDF: `histogramQuantile(Array(Float64), Array(Float64), Float64) -> Float64`

- [ ] **Step 1: เพิ่ม volume ใหม่**

เพิ่มเข้าไปในบล็อก `volumes:` ที่มีอยู่:

```yaml
  signoz-telemetrystore-user-scripts:
    name: signoz-telemetrystore-user-scripts
```

- [ ] **Step 2: เพิ่ม config นิยาม UDF**

เพิ่มเข้าไปในบล็อก `configs:` ที่มีอยู่ ต่อจาก `clickhouse-config`:

```yaml
  clickhouse-functions:
    content: |
      functions:
        argument:
          - name: buckets
            type: Array(Float64)
          - name: counts
            type: Array(Float64)
          - name: quantile
            type: Float64
        command: ./histogramQuantile
        format: CSV
        name: histogramQuantile
        return_type: Float64
        type: executable
```

- [ ] **Step 3: ต่อ config และ volume เข้ากับ service `clickhouse`**

แก้ service `clickhouse` — เพิ่มบรรทัดที่ทำเครื่องหมายไว้:

```yaml
  clickhouse:
    container_name: signoz-telemetrystore-clickhouse-0-0
    image: clickhouse/clickhouse-server:25.12.5
    restart: unless-stopped
    mem_limit: 1400m
    environment:
      - CLICKHOUSE_SKIP_USER_SETUP=1
      - CLICKHOUSE_CONFIG=/etc/clickhouse-server/config-0-0.yaml
    depends_on:
      keeper:
        condition: service_healthy
      user-scripts:                              # เพิ่ม
        condition: service_completed_successfully  # เพิ่ม
    networks:
      signoz-network:
        aliases:
          - signoz-telemetrystore-clickhouse-0-0
    configs:
      - source: clickhouse-config
        target: /etc/clickhouse-server/config-0-0.yaml
      - source: clickhouse-functions                        # เพิ่ม
        target: /etc/clickhouse-server/functions.yaml       # เพิ่ม
    volumes:
      - signoz-telemetrystore-0-0-data:/var/lib/clickhouse
      - signoz-telemetrystore-user-scripts:/var/lib/clickhouse/user_scripts:ro   # เพิ่ม
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:8123/ping"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
```

- [ ] **Step 4: เพิ่ม service `user-scripts` และ `migrator`**

ต่อท้ายบล็อก `services:`

`$$` ในนี้ **ห้ามแก้เป็น `$` เด็ดขาด** — Docker Compose จะแปลง `$$` เป็น `$` ตัวเดียว
ตอนส่งให้ shell ถ้าเขียน `$` ตัวเดียว Compose จะพยายาม interpolate เองแล้ว parse ไม่ผ่าน

```yaml
  user-scripts:
    container_name: signoz-telemetrystore-clickhouse-user-scripts
    image: clickhouse/clickhouse-server:25.12.5
    restart: on-failure
    mem_limit: 256m
    networks:
      - signoz-network
    volumes:
      - signoz-telemetrystore-user-scripts:/var/lib/clickhouse/user_scripts
    command:
      - bash
      - -c
      - |-
        version="v0.0.1"
        node_os=$$(uname -s | tr '[:upper:]' '[:lower:]')
        node_arch=$$(uname -m | sed s/aarch64/arm64/ | sed s/x86_64/amd64/)
        echo "Fetching histogram-binary for $${node_os}/$${node_arch}"
        cd /tmp
        wget -O histogram-quantile.tar.gz "https://github.com/SigNoz/signoz/releases/download/histogram-quantile%2F$${version}/histogram-quantile_$${node_os}_$${node_arch}.tar.gz"
        tar -xvzf histogram-quantile.tar.gz
        mv histogram-quantile /var/lib/clickhouse/user_scripts/histogramQuantile

  migrator:
    container_name: signoz-telemetrystore-migrator
    image: signoz/signoz-otel-collector:v0.144.8
    restart: on-failure
    mem_limit: 256m
    depends_on:
      clickhouse:
        condition: service_healthy
    networks:
      - signoz-network
    environment:
      - SIGNOZ_OTEL_COLLECTOR_CLICKHOUSE_DSN=tcp://signoz-telemetrystore-clickhouse-0-0:9000
      - SIGNOZ_OTEL_COLLECTOR_TIMEOUT=10m
    entrypoint:
      - /bin/sh
    command:
      - -c
      - |
        /signoz-otel-collector migrate ready &&
        /signoz-otel-collector migrate bootstrap &&
        /signoz-otel-collector migrate sync up &&
        /signoz-otel-collector migrate async up
```

- [ ] **Step 5: static check**

```bash
docker compose -f docker-compose.signoz-portainer.yaml config >/dev/null && echo PARSE_OK
```

คาดหวัง: `PARSE_OK`

- [ ] **Step 6: ยกขึ้นจากศูนย์ (ต้องล้าง volume เก่าก่อนเพื่อทดสอบ ordering จริง)**

```bash
docker compose -f docker-compose.signoz-portainer.yaml down -v
docker compose -f docker-compose.signoz-portainer.yaml up -d
docker compose -f docker-compose.signoz-portainer.yaml ps -a
```

คาดหวัง: `user-scripts` และ `migrator` สถานะ `Exited (0)`,
`keeper` และ `clickhouse` สถานะ `Up (healthy)`

`migrator` อาจ restart 1-2 รอบก่อนสำเร็จเป็นเรื่องปกติ ให้รอถึง ~3 นาที
ถ้ายังวนไม่จบให้ดู `docker logs signoz-telemetrystore-migrator`

- [ ] **Step 7: ยืนยันว่า schema ถูกสร้าง**

```bash
docker exec signoz-telemetrystore-clickhouse-0-0 clickhouse-client -q "SHOW DATABASES"
```

คาดหวังว่าต้องมีครบทั้ง 5 ตัวนี้: `signoz_traces`, `signoz_logs`, `signoz_metrics`,
`signoz_metadata`, `signoz_meter`

- [ ] **Step 8: ยืนยันว่า UDF `histogramQuantile` ใช้งานได้**

```bash
docker exec signoz-telemetrystore-clickhouse-0-0 clickhouse-client -q \
  "SELECT histogramQuantile([1.0, 2.0, 5.0, inf], [10.0, 40.0, 80.0, 100.0], 0.5)"
```

คาดหวัง: **`2.75` เป๊ะๆ**

input ต้องเป็น cumulative histogram แบบ Prometheus คือ count เพิ่มขึ้นเรื่อยๆ
และ bucket สุดท้ายเป็น `inf` ถ้าใส่ array ที่ไม่ตรง domain นี้ binary จะคืน `nan`
ซึ่งเป็นค่า Float64 ที่ถูกต้องตาม IEEE-754 ไม่ใช่ error — จึงผ่าน gate แบบ
"ขอแค่ไม่ error" ได้ทั้งที่ยังไม่ได้พิสูจน์ว่าคำนวณถูก ค่า `2.75` จึงเป็น gate ที่แท้จริง

ตรวจเพิ่มอีกเคสเพื่อความมั่นใจ:

```bash
docker exec signoz-telemetrystore-clickhouse-0-0 clickhouse-client -q \
  "SELECT histogramQuantile([0.0, 1.0, 2.0, 5.0, inf], [0.0, 10.0, 20.0, 30.0, 30.0], 0.5)"
```

คาดหวัง: **`1.5`**

ถ้าได้ `Unknown function histogramQuantile` แปลว่า `functions.yaml` ไม่ได้ถูกอ่าน
ถ้าได้ error ประมาณ `Cannot execute` แปลว่า binary ไม่ได้อยู่ใน volume —
ดู `docker logs signoz-telemetrystore-clickhouse-user-scripts`

- [ ] **Step 9: Commit**

```bash
docker compose -f docker-compose.signoz-portainer.yaml down
git add docker-compose.signoz-portainer.yaml
git commit -m "feat: add schema layer (histogramQuantile UDF + ClickHouse migrator)"
```

---

## Task 4: ชั้น app — SigNoz + ingester และ smoke test

**Files:**
- Modify: `docker-compose.signoz-portainer.yaml`
- Create: `smoke-test/send-trace.sh`

**Interfaces:**
- Consumes: ทุก service จาก Task 2-3
- Produces:
  - compose services: `signoz`, `ingester`
  - volume: `signoz-metastore-sqlite-0-data`
  - configs: `ingester-config`, `ingester-opamp`
  - network alias: `signoz-signoz-0` (HTTP API 8080, opamp 4320), `signoz-ingester` (OTLP 4317/4318)
  - host port: `8080` (UI), `4317` (OTLP/gRPC), `4318` (OTLP/HTTP) — จะทำเป็นตัวแปรใน Task 5
  - script: `smoke-test/send-trace.sh [endpoint]` ค่า default `http://localhost:4318`

- [ ] **Step 1: เพิ่ม volume ของ SQLite metastore**

เพิ่มเข้าไปในบล็อก `volumes:`:

```yaml
  signoz-metastore-sqlite-0-data:
    name: signoz-metastore-sqlite-0-data
```

- [ ] **Step 2: เพิ่ม config ของ ingester**

เพิ่มต่อท้ายบล็อก `configs:`

ความต่างจากต้นฉบับ 3 จุด — **ห้ามลืม**:
1. `low_cardinal_exception_grouping: false` (ต้นฉบับเป็น `${env:...}` ซึ่งทำให้ Compose parse ไม่ผ่าน)
2. เพิ่ม processor `memory_limiter` และใส่เป็น **ตัวแรก** ของทุก pipeline ที่รับจาก
   receiver `otlp` คือ `traces`, `metrics`, `logs` — **ไม่ใส่ใน `metrics/meter`**
   เพราะ pipeline นั้นรับจาก connector `signozmeter` ซึ่งข้อมูลผ่าน memory_limiter
   มาแล้วจาก pipeline ต้นทาง ใส่ซ้ำจะนับ memory ซ้ำ (YAML ข้างล่างถูกต้องแล้ว ทำตามนั้น)
3. ลด `send_batch_size` จาก 50000 → 5000 และ batch/meter จาก 20000 → 2000

```yaml
  ingester-config:
    content: |
      connectors:
        signozmeter:
          metrics_flush_interval: 1h
          dimensions:
            - name: service.name
            - name: deployment.environment
            - name: host.name
      receivers:
        otlp:
          protocols:
            grpc:
              endpoint: "0.0.0.0:4317"
            http:
              endpoint: "0.0.0.0:4318"
      processors:
        memory_limiter:
          check_interval: 2s
          limit_mib: 300
          spike_limit_mib: 60
        batch:
          send_batch_size: 5000
          send_batch_max_size: 5500
          timeout: 5s
        batch/meter:
          send_batch_size: 2000
          send_batch_max_size: 2500
          timeout: 5s
        signozspanmetrics/delta:
          metrics_exporter: signozclickhousemetrics
          metrics_flush_interval: 60s
          latency_histogram_buckets:
            - 100us
            - 1ms
            - 2ms
            - 6ms
            - 10ms
            - 50ms
            - 100ms
            - 250ms
            - 500ms
            - 1000ms
            - 1400ms
            - 2000ms
            - 5s
            - 10s
            - 20s
            - 40s
            - 60s
          dimensions_cache_size: 100000
          aggregation_temporality: AGGREGATION_TEMPORALITY_DELTA
          enable_exp_histogram: true
          dimensions:
            - name: service.namespace
              default: default
            - name: deployment.environment
              default: default
            - name: signoz.collector.id
            - name: service.version
      exporters:
        clickhousetraces:
          datasource: tcp://signoz-telemetrystore-clickhouse-0-0:9000/signoz_traces
          low_cardinal_exception_grouping: false
          use_new_schema: true
          timeout: 45s
          sending_queue:
            enabled: false
        signozclickhousemetrics:
          dsn: tcp://signoz-telemetrystore-clickhouse-0-0:9000/signoz_metrics
          timeout: 45s
          sending_queue:
            enabled: false
        clickhouselogsexporter:
          dsn: tcp://signoz-telemetrystore-clickhouse-0-0:9000/signoz_logs
          use_new_schema: true
          timeout: 45s
          sending_queue:
            enabled: false
        signozclickhousemeter:
          dsn: tcp://signoz-telemetrystore-clickhouse-0-0:9000/signoz_meter
          timeout: 45s
          sending_queue:
            enabled: false
        metadataexporter:
          enabled: true
          dsn: tcp://signoz-telemetrystore-clickhouse-0-0:9000/signoz_metadata
          timeout: 45s
          cache:
            provider: in_memory
      extensions:
        signoz_health_check:
          endpoint: "0.0.0.0:13133"
        pprof:
          endpoint: "0.0.0.0:1777"
      service:
        telemetry:
          logs:
            encoding: json
        extensions:
          - signoz_health_check
          - pprof
        pipelines:
          traces:
            receivers:
              - otlp
            processors:
              - memory_limiter
              - signozspanmetrics/delta
              - batch
            exporters:
              - clickhousetraces
              - signozmeter
              - metadataexporter
          metrics:
            receivers:
              - otlp
            processors:
              - memory_limiter
              - batch
            exporters:
              - signozclickhousemetrics
              - signozmeter
              - metadataexporter
          logs:
            receivers:
              - otlp
            processors:
              - memory_limiter
              - batch
            exporters:
              - clickhouselogsexporter
              - signozmeter
              - metadataexporter
          metrics/meter:
            receivers:
              - signozmeter
            processors:
              - batch/meter
            exporters:
              - signozclickhousemeter

  ingester-opamp:
    content: |
      server_endpoint: ws://signoz-signoz-0:4320/v1/opamp
```

- [ ] **Step 3: เพิ่ม service `signoz` และ `ingester`**

ต่อท้ายบล็อก `services:`

```yaml
  signoz:
    container_name: signoz-signoz-0
    image: signoz/signoz:v0.137.1
    restart: unless-stopped
    mem_limit: 600m
    depends_on:
      clickhouse:
        condition: service_healthy
      migrator:
        condition: service_completed_successfully
    environment:
      - SIGNOZ_SQLSTORE_PROVIDER=sqlite
      - SIGNOZ_SQLSTORE_SQLITE_PATH=/var/lib/signoz/signoz.db
      - SIGNOZ_TELEMETRYSTORE_PROVIDER=clickhouse
      - SIGNOZ_TELEMETRYSTORE_CLICKHOUSE_DSN=tcp://signoz-telemetrystore-clickhouse-0-0:9000
    ports:
      - "8080:8080"
    volumes:
      - signoz-metastore-sqlite-0-data:/var/lib/signoz
    networks:
      signoz-network:
        aliases:
          - signoz-signoz-0
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:8080/api/v1/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s

  ingester:
    container_name: signoz-ingester
    image: signoz/signoz-otel-collector:v0.144.8
    restart: unless-stopped
    mem_limit: 400m
    depends_on:
      signoz:
        condition: service_healthy
    environment:
      - SIGNOZ_OTEL_COLLECTOR_CLICKHOUSE_DSN=tcp://signoz-telemetrystore-clickhouse-0-0:9000
      - SIGNOZ_OTEL_COLLECTOR_TIMEOUT=10m
    entrypoint:
      - /bin/sh
    command:
      - -c
      - |
        /signoz-otel-collector migrate sync check &&
        /signoz-otel-collector --config=/etc/otel-collector-config.yaml --manager-config=/etc/opamp-config.yaml --copy-path=/var/tmp/collector-config.yaml
    ports:
      - "4317:4317"
      - "4318:4318"
    configs:
      - source: ingester-config
        target: /etc/otel-collector-config.yaml
      - source: ingester-opamp
        target: /etc/opamp-config.yaml
    networks:
      signoz-network:
        aliases:
          - signoz-ingester
```

- [ ] **Step 4: เขียน script ยิง trace ทดสอบ**

```bash
mkdir -p smoke-test
cat > smoke-test/send-trace.sh <<'EOF'
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
EOF
chmod +x smoke-test/send-trace.sh
```

- [ ] **Step 5: static check**

```bash
docker compose -f docker-compose.signoz-portainer.yaml config >/dev/null && echo PARSE_OK
```

คาดหวัง: `PARSE_OK`

ถ้าเจอ `invalid interpolation format` ให้เช็คว่าลืมแก้ `${env:LOW_CARDINAL_EXCEPTION_GROUPING}`
เป็น `false` หรือเปล่า

- [ ] **Step 6: ยกทั้ง stack ขึ้นจากศูนย์**

```bash
docker compose -f docker-compose.signoz-portainer.yaml down -v
docker compose -f docker-compose.signoz-portainer.yaml up -d
docker compose -f docker-compose.signoz-portainer.yaml ps -a
```

คาดหวัง: 6 service — `keeper`, `clickhouse`, `signoz`, `ingester` เป็น `Up`
ส่วน `user-scripts`, `migrator` เป็น `Exited (0)` ใช้เวลารวม ~3-5 นาทีในการขึ้นครั้งแรก

- [ ] **Step 7: ยืนยัน health ของ SigNoz**

```bash
curl -sS -o /dev/null -w '%{http_code}\n' http://localhost:8080/api/v1/health
```

คาดหวัง: `200`

- [ ] **Step 8: ยืนยันว่า SigNoz ใช้ SQLite ไม่ใช่ Postgres**

```bash
docker exec signoz-signoz-0 ls -la /var/lib/signoz/
```

คาดหวัง: เห็นไฟล์ `signoz.db` (และอาจมี `signoz.db-wal`, `signoz.db-shm`)
ถ้าไม่มีแปลว่า SQLite provider ไม่ได้ทำงาน

- [ ] **Step 9: smoke test เส้นทางทั้งเส้น**

```bash
./smoke-test/send-trace.sh
```

คาดหวัง: `HTTP 200`

จากนั้นรอ ~30 วินาที แล้วยืนยันว่าข้อมูลลง ClickHouse จริง:

```bash
docker exec signoz-telemetrystore-clickhouse-0-0 clickhouse-client -q \
  "SELECT count() FROM signoz_traces.distributed_signoz_index_v3 WHERE resource_string_service\$\$name = 'smoke-test'"
```

ถ้าชื่อตารางหรือคอลัมน์ไม่ตรง (schema ของ SigNoz เปลี่ยนตามเวอร์ชัน) ให้ใช้วิธีที่ทนกว่า:

```bash
docker exec signoz-telemetrystore-clickhouse-0-0 clickhouse-client -q \
  "SELECT name FROM system.tables WHERE database = 'signoz_traces' ORDER BY name"
docker exec signoz-telemetrystore-clickhouse-0-0 clickhouse-client -q \
  "SELECT count() FROM signoz_traces.signoz_index_v3"
```

คาดหวัง: count มากกว่า 0

สุดท้ายยืนยันว่า query path ของ SigNoz มองเห็น service นี้จริง ใช้ API ไม่ใช่เบราว์เซอร์
เพราะรันซ้ำได้และให้หลักฐานที่ตรวจสอบได้ (เบราว์เซอร์เรียก endpoint เดียวกันนี้):

```bash
curl -sS -X POST http://localhost:8080/api/v1/services \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer <token>" \
  -d '{"start":<start_ns>,"end":<end_ns>}'
```

ต้องมี `"serviceName":"smoke-test"` พร้อม `numCalls` มากกว่า 0
**นี่คือ gate ของ task นี้ ห้าม commit ถ้ายังไม่เห็น**

หมายเหตุ: ต้องสร้าง admin account ก่อนถึงจะเรียก API นี้ได้ (ดู README ขั้นที่ 1)
ถ้ายังไม่ได้สร้าง จะต่อ port 4318 ไม่ติดตั้งแต่แรกอยู่แล้ว

- [ ] **Step 10: วัด memory จริงเทียบกับงบ**

```bash
docker stats --no-stream --format 'table {{.Name}}\t{{.MemUsage}}\t{{.MemPerc}}'
```

บันทึกตัวเลขไว้รายงานตอนจบ task ผลรวมของ 4 service ที่รันค้างควรอยู่แถว ~2.6 GB หรือต่ำกว่า
ถ้าเกินอย่างชัดเจนให้รายงาน อย่าเพิ่งแก้เอง

- [ ] **Step 11: Commit**

```bash
docker compose -f docker-compose.signoz-portainer.yaml down
git add docker-compose.signoz-portainer.yaml smoke-test/
git commit -m "feat: add app layer (SigNoz UI + OTLP ingester) with smoke test script"
```

---

## Task 5: ปรับให้เข้ากับ Portainer

**Files:**
- Modify: `docker-compose.signoz-portainer.yaml`
- Create: `.env.example`

**Interfaces:**
- Consumes: compose ที่สมบูรณ์จาก Task 4
- Produces: ตัวแปรที่ตั้งได้ในช่อง Environment variables ของ Portainer
  - `SIGNOZ_BIND_ADDR` (default `0.0.0.0`)
  - `SIGNOZ_UI_PORT` (default `8080`)
  - `SIGNOZ_OTLP_GRPC_PORT` (default `4317`)
  - `SIGNOZ_OTLP_HTTP_PORT` (default `4318`)

ตัวแปรพวกนี้ Docker Compose เป็นคน interpolate ตอน deploy ต่างจาก `$$` ใน `content:`
ที่ตั้งใจให้เป็นข้อความดิบ อย่าสับสนสองอย่างนี้

- [ ] **Step 1: ทำ port ของ `signoz` เป็นตัวแปร**

แก้บล็อก `ports:` ของ service `signoz`:

```yaml
    ports:
      - "${SIGNOZ_BIND_ADDR:-0.0.0.0}:${SIGNOZ_UI_PORT:-8080}:8080"
```

- [ ] **Step 2: ทำ port ของ `ingester` เป็นตัวแปร**

แก้บล็อก `ports:` ของ service `ingester`:

```yaml
    ports:
      - "${SIGNOZ_BIND_ADDR:-0.0.0.0}:${SIGNOZ_OTLP_GRPC_PORT:-4317}:4317"
      - "${SIGNOZ_BIND_ADDR:-0.0.0.0}:${SIGNOZ_OTLP_HTTP_PORT:-4318}:4318"
```

- [ ] **Step 3: ยืนยันว่าไม่มี `name:` ระดับบนสุด และไม่มี bind mount**

```bash
grep -nE '^name:' docker-compose.signoz-portainer.yaml || echo "OK: ไม่มี name ระดับบนสุด"
grep -nE '^\s+-\s+\./' docker-compose.signoz-portainer.yaml || echo "OK: ไม่มี relative bind mount"
```

คาดหวัง: ได้ `OK:` ทั้งสองบรรทัด ถ้าเจอ match แปลว่ายังมีของที่ Portainer ใช้ไม่ได้ค้างอยู่

- [ ] **Step 4: เขียน `.env.example`**

```bash
cat > .env.example <<'EOF'
# ตัวแปรสำหรับ docker-compose.signoz-portainer.yaml
#
# บน Portainer: ไม่ต้องใช้ไฟล์นี้ ให้กรอกในช่อง "Environment variables"
#               ตอนสร้าง Stack แทน ใส่เฉพาะตัวที่ต้องการเปลี่ยนจาก default
# บนเครื่อง dev: ก๊อปเป็น .env แล้วแก้ค่า

# IP ที่จะให้ผูก port ไว้
# ใช้ 0.0.0.0 = เปิดทุก interface
# ถ้าเครื่องมี public IP ให้ใส่ IP ของ LAN interface แทน เช่น 192.168.1.50
# เพราะ OTLP ไม่มี authentication ใครยิงถึงก็ยัดข้อมูลเข้ามาได้
SIGNOZ_BIND_ADDR=0.0.0.0

# port ของ SigNoz UI บน host — เปลี่ยนถ้า 8080 ชนกับ service อื่น
SIGNOZ_UI_PORT=8080

# port รับ telemetry
SIGNOZ_OTLP_GRPC_PORT=4317
SIGNOZ_OTLP_HTTP_PORT=4318
EOF
```

- [ ] **Step 5: ยืนยันว่าตัวแปรทำงาน — ทั้งตอนใช้ default และตอน override**

```bash
docker compose -f docker-compose.signoz-portainer.yaml config | grep -A3 'published'
```

คาดหวัง: เห็น `published: "8080"`, `"4317"`, `"4318"` และ `host_ip: 0.0.0.0`

```bash
SIGNOZ_UI_PORT=18080 SIGNOZ_BIND_ADDR=127.0.0.1 \
  docker compose -f docker-compose.signoz-portainer.yaml config | grep -A3 'published'
```

คาดหวัง: เห็น `published: "18080"` และ `host_ip: 127.0.0.1`
ถ้ายังเป็น 8080 แปลว่า syntax ของตัวแปรผิด

- [ ] **Step 6: ยกขึ้นจริงด้วย port ที่ override เพื่อพิสูจน์ว่าใช้ได้จริง ไม่ใช่แค่ config ผ่าน**

```bash
docker compose -f docker-compose.signoz-portainer.yaml down -v
SIGNOZ_UI_PORT=18080 docker compose -f docker-compose.signoz-portainer.yaml up -d
```

รอให้ขึ้นครบ (~3-5 นาที) แล้ว:

```bash
curl -sS -o /dev/null -w '%{http_code}\n' http://localhost:18080/api/v1/health
```

คาดหวัง: `200`

- [ ] **Step 7: Commit**

```bash
docker compose -f docker-compose.signoz-portainer.yaml down
git add docker-compose.signoz-portainer.yaml .env.example
git commit -m "feat: parameterise ports and bind address for Portainer stack env vars"
```

---

## Task 6: README และการตรวจสอบรอบสุดท้าย

**Files:**
- Create: `README.md`

**Interfaces:**
- Consumes: deliverable ทั้งหมดจาก Task 1-5
- Produces: เอกสารที่คนอื่นเอาไป deploy เองได้โดยไม่ต้องถาม

- [ ] **Step 1: เขียน README.md**

```bash
cat > README.md <<'EOF'
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
EOF
```

- [ ] **Step 2: ตรวจสอบรอบสุดท้าย — ทำตาม README จากศูนย์**

```bash
docker compose -f docker-compose.signoz-portainer.yaml down -v
docker volume ls | grep signoz
```

คาดหวัง: ไม่เหลือ volume ของ signoz เลย

```bash
docker compose -f docker-compose.signoz-portainer.yaml up -d
```

รอจนขึ้นครบ แล้ว:

```bash
docker compose -f docker-compose.signoz-portainer.yaml ps -a
curl -sS -o /dev/null -w '%{http_code}\n' http://localhost:8080/api/v1/health
```

คาดหวัง: 4 service `Up`, 2 service `Exited (0)`, health `200`

**ยังยิง smoke test ตอนนี้ไม่ได้** เพราะ `down -v` ลบ volume ของ SQLite ไปด้วย
`setupCompleted` จึงกลับเป็น `false` และ collector รัน no-op pipeline อยู่
ต้องทำตามลำดับที่ README เขียนไว้ ซึ่งก็คือประเด็นของด่านนี้พอดี — ตรวจว่า README
พาคนทำได้จริงตั้งแต่ศูนย์ ไม่ใช่แค่มีข้อมูลครบ

ทำ "หลัง deploy ขั้นที่ 1" ตามที่ README เขียน:

ตั้งรหัสผ่านชั่วคราวไว้ใน env ก่อน อย่าเขียนค่าจริงลงไฟล์ใดๆ ในโปรเจกต์:

```bash
SMOKE_PW=$(head -c 18 /dev/urandom | base64 | tr -d "\n")Aa1#
```

```bash
curl -sS http://localhost:8080/api/v1/version
```

คาดหวัง: `"setupCompleted":false`

```bash
curl -sS -X POST http://localhost:8080/api/v1/register \
  -H 'Content-Type: application/json' \
  -d "{\"email\":\"admin@example.com\",\"password\":\"$SMOKE_PW\",\"orgName\":\"Carmen\",\"name\":\"Admin\"}"
curl -sS http://localhost:8080/api/v1/version
```

คาดหวัง: `"setupCompleted":true`

รอประมาณ 30 วินาทีให้ OpAMP push pipeline จริงลงไป แล้วค่อยยิง:

```bash
./smoke-test/send-trace.sh
```

คาดหวัง: `HTTP 200`

ถ้าได้ `HTTP 000` แปลว่า OpAMP ยังไม่ push config ใหม่ รออีก 30 วินาทีแล้วลองใหม่
ถ้ายังไม่ได้ ให้ดู log ของ `ingester` หา `Config has changed, reloading`

**ด่านนี้คือการพิสูจน์ว่า README ใช้งานได้จริง** ถ้าต้องทำอะไรที่ README ไม่ได้เขียนไว้
เพื่อให้ผ่าน แปลว่า README ยังไม่ครบ — ให้แก้ README ไม่ใช่แค่ทำแล้วผ่านไป

- [ ] **Step 3: ตรวจว่าไม่มีอะไรที่ Portainer ใช้ไม่ได้หลงเหลือ**

```bash
echo "--- ต้องว่างทั้งหมด ---"
grep -nE '^name:'          docker-compose.signoz-portainer.yaml
grep -nE '^\s+-\s+\./'     docker-compose.signoz-portainer.yaml
grep -nE ':latest'         docker-compose.signoz-portainer.yaml
grep -nE '\$\{env:'        docker-compose.signoz-portainer.yaml
echo "--- จบ ---"
```

คาดหวัง: ไม่มี output ระหว่างสองบรรทัด `---` เลยแม้แต่บรรทัดเดียว

- [ ] **Step 4: ยืนยันว่า mem_limit ครบทุก service**

```bash
grep -c 'mem_limit' docker-compose.signoz-portainer.yaml
```

คาดหวัง: `6`

- [ ] **Step 5: Commit**

```bash
docker compose -f docker-compose.signoz-portainer.yaml down
git add README.md
git commit -m "docs: add deployment README with pre-flight checks and troubleshooting"
```

---

## สรุปสิ่งที่ได้เมื่อจบทุก task

| ไฟล์ | บทบาท |
|---|---|
| `docker-compose.signoz-portainer.yaml` | paste ลง Portainer web editor ได้ทันที ไม่ต้องมีไฟล์บน host |
| `README.md` | checklist ก่อน deploy, env vars, retention, แก้ปัญหา, อัปเกรด |
| `smoke-test/send-trace.sh` | พิสูจน์เส้นทางทั้งเส้นโดยไม่ต้องลง SDK |
| `.env.example` | เอกสารตัวแปรสำหรับ dev |
| `reference/upstream/` | ต้นฉบับ upstream ไว้ diff ตอนอัปเกรด |

**งานที่เหลือหลังจากนี้ (คนละรอบ):** instrument Carmen services ทีละตัว
เริ่มจาก Go services ตามที่ README ระบุไว้
