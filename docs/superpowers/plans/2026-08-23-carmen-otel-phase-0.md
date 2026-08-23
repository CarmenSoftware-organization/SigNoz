# Carmen OTel — เฟส 0 (ฐานราก) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ได้ตัวเลขและที่อยู่จริงของ dev host, พิสูจน์ว่า telemetry วิ่งข้าม VM ได้, ปิดทางเข้าสาธารณะของ OTLP, และตรึง convention ให้เฟส 1-4 อ้างได้โดยไม่ต้องเดา

**Architecture:** เฟสนี้ไม่แตะโค้ดของ app สักบรรทัด เป็นงาน infra + การบันทึกข้อเท็จจริงล้วน ผลลัพธ์คือเอกสารสองไฟล์ (`docs/dev-host-facts.md`, `docs/otel-conventions.md`) ที่เฟส 1-4 อ่านค่าคงที่ทั้งหมดไปใช้ — endpoint, ชื่อ service, resource attribute, retention ที่ตั้งจริง

**Tech Stack:** Portainer UI (ทางเดียวที่เข้า VM SigNoz ได้), SSH + OpenRC (VM Carmen), curl, SigNoz UI

**Spec:** `docs/superpowers/specs/2026-08-23-carmen-otel-instrumentation-design.md`

## Global Constraints

- **Claude เข้าเครื่องเองไม่ได้** ทุกคำสั่งในแผนนี้ต้องให้ user รัน (พิมพ์ `!` นำหน้าใน session นี้) แล้ววางผลลัพธ์กลับมา หรือมอบให้ agent ที่มี credential จริง — **ห้ามเขียนค่าที่ยังไม่เห็นผลลัพธ์จริงลงเอกสาร**
- **VM SigNoz ไม่มี SSH** เข้าถึงได้ผ่าน Portainer UI (`http://dev.blueledgers.com:9000`) อย่างเดียว ตามที่ `README.md` ระบุไว้ตั้งแต่ตอนวาง stack — ทุก task ที่แตะ VM นั้นต้องทำผ่าน UI
- **VM Carmen มี SSH** (workflow `carmen-turborepo-backend-v2/.github/workflows/build.yml:36` ใช้ `dev.blueledgers.com` + `secrets.DEV_SSH_*`)
- **ไม่มี automated test ในเฟสนี้** verification เป็น manual ทั้งหมด (สอดคล้องกับ CLAUDE.md ของ user ที่ให้ข้าม test step) — ห้ามสร้างไฟล์ `*.test.*` / `*.spec.*`
- **SigNoz OSS ไม่มี ingestion key** การควบคุมทาง network คือมาตรการความปลอดภัยเดียวที่มี ทุกการตัดสินใจใน Task 4 จึงเป็น security control ไม่ใช่งานจัดระเบียบ
- **ค่าที่ค้นพบต้องมีที่อยู่เดียว** endpoint สุดท้ายถูกบันทึกเป็น `OTEL_EXPORTER_OTLP_ENDPOINT` ใน `docs/otel-conventions.md` เฟส 1-4 อ้างจากที่นั่นเท่านั้น ห้าม hardcode ซ้ำที่อื่น
- **branch:** `feature/carmen-otel-instrumentation-spec` (repo SigNoz) — commit ต่อจาก `96a5b8c`
- **ห้ามแก้ `docker-compose.signoz-portainer.yaml` นอกเหนือจาก Task 4** stack นี้ deploy ผ่าน Portainer web editor การแก้ไฟล์ใน repo ไม่มีผลกับของที่รันอยู่จนกว่าจะ Update the stack ด้วยมือ

## File Structure

| ไฟล์ | หน้าที่ |
|---|---|
| `docs/dev-host-facts.md` (สร้าง) | ข้อเท็จจริงที่**วัดได้จริง** ของทั้งสอง VM — RAM, disk, private IP, port ที่ publish, สถานะ retention, สถานะ Loki พร้อมวันที่วัด |
| `docs/otel-conventions.md` (สร้าง) | ค่าคงที่ที่เฟส 1-4 อ้าง — endpoint, `service.name` 12 ตัว, resource attribute, log attribute, กฎ "ไม่ตั้ง env = ไม่ start SDK" |
| `README.md` (แก้) | retention ที่ตั้งจริง + วิธีเข้า UI หลังปิด forward |
| `docs/superpowers/specs/2026-08-23-carmen-otel-instrumentation-design.md` (แก้) | อัปเดต §13 "เรื่องที่ยังไม่รู้" ให้เหลือเฉพาะที่ยังไม่รู้จริงหลังเฟสนี้ |

แยกสองไฟล์เพราะอายุต่างกัน: `dev-host-facts.md` เป็นภาพ ณ วันที่วัดและจะเก่า ส่วน
`otel-conventions.md` เป็นสัญญาที่ต้องนิ่งตลอดเฟส 1-4 ถ้ารวมกันคนจะไม่กล้าอัปเดตครึ่งแรก
เพราะกลัวกระทบครึ่งหลัง

---

### Task 1: เก็บข้อเท็จจริงของ VM SigNoz (ผ่าน Portainer)

**Files:**
- Create: `docs/dev-host-facts.md`

**Interfaces:**
- Produces: `SIGNOZ_LAN_IP` (private IP ของ VM SigNoz), `SIGNOZ_RAM_FREE_MB`, `SIGNOZ_DISK_FREE_GB`, `SIGNOZ_PUBLISHED_PORTS` — Task 2, 3, 4 ใช้ทั้งหมด

- [ ] **Step 1: เปิด Portainer แล้วอ่านหน้า Host**

เปิด `http://dev.blueledgers.com:9000` → เลือก environment → เมนู **Host** → แท็บ **Details**

จดค่า: Total memory, CPU, และ **Docker version + Compose version** (Compose ต้อง >= 2.23.1 ตามที่ `README.md` ระบุ — ถ้าต่ำกว่านี้ stack ที่รันอยู่จะไม่ใช่ของที่คิด)

- [ ] **Step 2: อ่าน RAM ที่เหลือจริงจากหน้า Containers**

Portainer → **Containers** → เปิดคอลัมน์ Memory usage

จดค่าที่ container ทั้ง 6 ของ stack ใช้รวมกัน (`signoz`, `signoz-ingester`, `signoz-clickhouse`, `signoz-zookeeper`, `signoz-schema-migrator*`, `signoz-user-scripts` — ชื่อจริงดูจาก UI)

**เกณฑ์ตัดสิน:** ถ้า RAM ว่างบน host < 500 MB หลังหักทุก container แล้ว **หยุด** — การเพิ่ม
telemetry ของ 12 app เข้าไปจะทำให้ ClickHouse โดน OOM kill ให้แจ้ง user ก่อนไป Task 2

- [ ] **Step 3: อ่าน disk ที่เหลือ**

Portainer → **Volumes** ดูขนาดที่ SigNoz ใช้ไปแล้ว และหน้า **Host → Details** สำหรับพื้นที่รวม

ถ้า Portainer ไม่โชว์ disk ว่างของ host (บางเวอร์ชันไม่โชว์) ใช้ทางอ้อม: Portainer →
**Containers** → `signoz-clickhouse` → **Console** → เชื่อมเป็น `/bin/sh` แล้วรัน:

```sh
df -h /var/lib/clickhouse
```

- [ ] **Step 4: อ่าน private IP ของ VM SigNoz**

Portainer → **Containers** → `signoz-clickhouse` → **Console** (`/bin/sh`) แล้วรัน:

```sh
ip -4 addr show 2>/dev/null | grep inet || cat /proc/net/fib_trie | grep -A1 32 | head -20
```

นี่ได้ IP ของ container ไม่ใช่ของ host — ค่าที่ต้องการคือ **IP ของ host** ให้ดูจาก
Portainer → **Home** → คอลัมน์ URL ของ environment แทน (ถ้าเป็น `unix:///var/run/docker.sock`
แปลว่า Portainer รันบน host เดียวกัน ให้ใช้ gateway IP ของ bridge network:
`ip route | grep default` ใน console เดียวกัน)

- [ ] **Step 5: จดว่า stack publish port อะไรไว้บ้าง**

Portainer → **Containers** → คอลัมน์ **Published Ports** ของ `signoz` และ `signoz-ingester`

จดให้ครบว่าผูกกับ IP ไหน (`0.0.0.0:40318->4318/tcp` ต่างจาก `192.168.x.x:40318->4318/tcp` มาก)

- [ ] **Step 6: ตรวจว่า retention ถูกตั้งไปแล้วหรือยัง**

เปิด `http://dev.blueledgers.com:48080` → **Settings** → **Retention**

จดค่าปัจจุบันของ Traces / Logs / Metrics — ถ้ายังเป็น default (traces/logs 15 วัน,
metrics 30 วัน) แปลว่าขั้นตอนบังคับหลัง deploy ไม่เคยถูกทำ ให้บันทึกไว้

- [ ] **Step 7: เขียนผลลง `docs/dev-host-facts.md`**

สร้างไฟล์ตามโครงนี้ **โดยกรอกเฉพาะค่าที่เห็นจริง** ช่องที่ยังไม่ได้วัดให้เขียน
`ยังไม่ได้วัด` ไม่ใช่เดา:

```markdown
# ข้อเท็จจริงของ dev host

**วัดเมื่อ:** 2026-08-23
**วัดยังไง:** Portainer UI (VM SigNoz — ไม่มี SSH) + SSH (VM Carmen)

> ค่าพวกนี้เก่าได้ ถ้าตัวเลขไม่ตรงกับที่เห็นตอนทำงานจริง ให้เชื่อของจริงแล้วอัปเดตไฟล์นี้

## VM SigNoz

| รายการ | ค่า |
|---|---|
| private IP ของ host | |
| RAM รวม / ว่าง | |
| disk รวม / ว่าง (`/var/lib/clickhouse`) | |
| Docker / Compose version | |
| published ports ของ `signoz` | |
| published ports ของ `signoz-ingester` | |
| retention ปัจจุบัน (traces / logs / metrics) | |

## VM Carmen

| รายการ | ค่า |
|---|---|
| private IP | |
| RAM รวม / ว่าง | |
| disk ว่าง | |
| ยิงถึง `<SIGNOZ_LAN_IP>:4318` ได้ไหม | |
| Loki (`:3998`) รันอยู่ที่ VM ไหน / กิน RAM เท่าไร | |
```

- [ ] **Step 8: Commit**

```bash
cd ../SigNoz
git add docs/dev-host-facts.md
git commit -m "docs: record measured facts of the dev host"
```

---

### Task 2: พิสูจน์ว่า telemetry วิ่งจาก VM Carmen ถึง SigNoz ได้

**Files:**
- Modify: `docs/dev-host-facts.md` (เติมส่วน VM Carmen)

**Interfaces:**
- Consumes: `SIGNOZ_LAN_IP` จาก Task 1
- Produces: `OTEL_EXPORTER_OTLP_ENDPOINT` — ค่าที่พิสูจน์แล้วว่าใช้ได้ เฟส 1-4 ใช้ค่านี้ตัวเดียว

**ทำไมต้องมาก่อนการปิด port:** ถ้าปิดทางสาธารณะก่อนแล้วเส้นทาง LAN ใช้ไม่ได้ จะไม่เหลือทางไหนเลย
และจะแยกไม่ออกว่าพังเพราะอะไร

- [ ] **Step 1: SSH เข้า VM Carmen แล้วเก็บข้อมูลเครื่อง**

```bash
ssh <DEV_SSH_USER>@dev.blueledgers.com -p <DEV_SSH_PORT>
ip -4 addr show | grep inet
free -m
df -h
```

- [ ] **Step 2: ตรวจว่ายิงถึง VM SigNoz ผ่าน LAN ได้ไหม**

บน VM Carmen (แทน `<SIGNOZ_LAN_IP>` ด้วยค่าจาก Task 1):

```bash
curl -sS -o /dev/null -w 'OTLP/HTTP %{http_code}\n' --max-time 5 http://<SIGNOZ_LAN_IP>:4318/
curl -sS -o /dev/null -w 'UI %{http_code}\n' --max-time 5 http://<SIGNOZ_LAN_IP>:8080/
```

คาดหวัง `OTLP/HTTP 404` (receiver ฟังอยู่ แต่ `/` ไม่ใช่ path ที่มันรับ) และ `UI 200`

**ถ้าได้ `000`:** VM สองตัวคุยกันไม่ได้ผ่าน port นั้น ลองพอร์ตที่ publish จริงจาก Task 1
Step 5 แทน (อาจเป็น `40318` ไม่ใช่ `4318` ถ้า publish แบบ host port) ถ้ายังไม่ได้ **หยุด
แล้วแจ้ง user** — ทั้ง design พึ่งเส้นทางนี้ ไม่มีทางอ้อม

- [ ] **Step 3: ยิง span จริงเข้าไป**

`smoke-test/send-trace.sh` อยู่ในเครื่อง dev ไม่ได้ ให้ใช้ curl ตรง (เนื้อในเดียวกับ script
`smoke-test/send-trace.sh:26-49`):

```bash
NOW=$(( $(date +%s) * 1000000000 ))
curl -sS -w '\nHTTP %{http_code}\n' -X POST "http://<SIGNOZ_LAN_IP>:4318/v1/traces" \
  -H 'Content-Type: application/json' \
  -d "{\"resourceSpans\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"phase0-from-carmen-vm\"}},{\"key\":\"deployment.environment\",\"value\":{\"stringValue\":\"dev\"}}]},\"scopeSpans\":[{\"spans\":[{\"traceId\":\"5b8efff798038103d269b633813fc60c\",\"spanId\":\"eee19b7ec3c1b174\",\"name\":\"phase0-span\",\"kind\":2,\"startTimeUnixNano\":\"$(( NOW - 500000000 ))\",\"endTimeUnixNano\":\"$NOW\",\"status\":{\"code\":1}}]}]}]}"
```

คาดหวัง `HTTP 200`

**ถ้าได้ connection reset:** ยังไม่ได้สร้าง admin account ของ SigNoz — pipeline ทั้งหมดถูก
rewrite เป็น `nop` (อธิบายไว้ละเอียดใน `README.md` หัวข้อ "หลัง deploy ขั้นที่ 1") ให้ไป
สร้าง account ก่อนแล้วกลับมาทำ step นี้ใหม่

- [ ] **Step 4: ยืนยันปลายทางว่าข้อมูลถึงจริง**

รอ ~30 วินาที แล้วเปิด `http://dev.blueledgers.com:48080` → **Services**

ต้องเห็น service ชื่อ `phase0-from-carmen-vm` โผล่ขึ้นมา

**ยิงได้ HTTP 200 ไม่ได้แปลว่าข้อมูลถึง ClickHouse** — ingester ตอบ 200 ตั้งแต่รับ payload
step นี้จึงเป็นตัวพิสูจน์เส้นทางจริง ไม่ใช่ step 3

- [ ] **Step 5: เติมผลลง `docs/dev-host-facts.md` แล้ว commit**

```bash
cd ../SigNoz
git add docs/dev-host-facts.md
git commit -m "docs: confirm the Carmen VM can reach SigNoz over the LAN"
```

---

### Task 3: ตั้ง retention ตามตัวเลข disk จริง และตัดสินชะตา Loki server

**Files:**
- Modify: `README.md` (หัวข้อ "หลัง deploy ขั้นที่ 2 — ตั้ง retention")
- Modify: `docs/dev-host-facts.md`

**Interfaces:**
- Consumes: `SIGNOZ_DISK_FREE_GB` จาก Task 1

**ความขัดแย้งที่ต้องตัดสินใน task นี้:** `README.md:141-152` แนะนำ traces 3 / logs 3 /
metrics 7 วัน ส่วน spec §9.2 เสนอ logs 7 / traces 3 / metrics 30 วัน spec ระบุเองแล้วว่า
**ตัวเลขของ README คือค่าตั้งต้นที่ปลอดภัยกว่า** ให้ขยับขึ้นเฉพาะเมื่อ disk รองรับ

- [ ] **Step 1: เลือกตัวเลขจากตารางนี้ ไม่ต้องคิดเอง**

| disk ว่างจริง | traces | logs | metrics |
|---|---|---|---|
| < 20 GB | 2 วัน | 2 วัน | 7 วัน |
| 20–50 GB | 3 วัน | 3 วัน | 7 วัน (ค่าของ README) |
| > 50 GB | 3 วัน | 7 วัน | 30 วัน (ค่าของ spec) |

- [ ] **Step 2: ตั้งค่าใน UI**

`http://dev.blueledgers.com:48080` → **Settings** → **Retention** → ใส่ค่าจาก Step 1 → Save

- [ ] **Step 3: ยืนยันว่าค่าถูกบันทึก**

refresh หน้าเดิม แล้วอ่านค่ากลับมาให้ตรงกับที่ตั้ง

**disk จะไม่ลดลงทันที** ClickHouse ลบด้วย TTL ตอน background merge — ถ้าเดิมเป็น default
15 วันและมีข้อมูลค้าง ต้องรอ merge รอบถัดไป อย่าตีความว่าตั้งไม่ติด

- [ ] **Step 4: ตัดสินชะตา Loki server**

เกณฑ์: **Loki กิน RAM เท่าไร และ RAM ว่างบน VM SigNoz เหลือเท่าไร** (ทั้งสองค่าอยู่ใน
`docs/dev-host-facts.md` จาก Task 1)

| สถานการณ์ | ทำ |
|---|---|
| Loki อยู่ VM เดียวกับ SigNoz **และ** RAM ว่าง < 1 GB | ปิด Loki เลย — มันคืน RAM ให้ตัวที่มาแทนพอดี |
| Loki อยู่คนละ VM หรือ RAM ว่างพอ | ปล่อยไว้ก่อน ปิดตอนเฟส 2 ที่ลบ transport ออกจากโค้ด |

**ลบ transport ในโค้ด ≠ ปิด server** — เฟสนี้ตัดสินเฉพาะเรื่อง server เท่านั้น โค้ดเป็นงานเฟส 2

- [ ] **Step 5: อัปเดต README ให้ตรงกับที่ตั้งจริง แล้ว commit**

แก้ตาราง `README.md:147-151` ให้เป็นค่าที่ตั้งจริง พร้อมเพิ่มบรรทัดว่าค่านี้ตั้งบน disk
เท่าไร ณ วันไหน — ค่าแนะนำลอย ๆ ที่ไม่บอกที่มา คือค่าที่คนถัดไปจะเปลี่ยนโดยไม่รู้ว่าทำไม

```bash
cd ../SigNoz
git add README.md docs/dev-host-facts.md
git commit -m "docs: set retention from the measured disk figure"
```

---

### Task 4: ปิดทางเข้า OTLP จากอินเทอร์เน็ต

**Files:**
- Modify: `docker-compose.signoz-portainer.yaml` (เฉพาะกรณีทางเลือก B)
- Modify: `README.md` (วิธีเข้า UI หลังปิด forward)
- Modify: `docs/dev-host-facts.md`

**Interfaces:**
- Consumes: `OTEL_EXPORTER_OTLP_ENDPOINT` ที่พิสูจน์แล้วจาก Task 2

**สถานะวันนี้:** `curl` จากเครื่องนอก LAN ถึง `dev.blueledgers.com:40318` ได้ (ตอบ 404 =
receiver ฟังอยู่) SigNoz OSS ไม่มี ingestion key ใครก็ตามที่ยิงถึงยัดข้อมูลเข้ามาได้จนดิสก์เต็ม

- [ ] **Step 1: เลือกทางตามสิทธิ์ที่มีจริง**

**ทางเลือก A — แก้ที่ NAT (ถ้าเข้าถึง router/firewall ได้):** ลบ port forward ของ
`40317` และ `40318` ออก เก็บไว้เฉพาะ `48080` ชั่วคราวจนกว่าจะทำ Step 4

**ทางเลือก B — แก้ที่ Portainer (ถ้าแตะ NAT ไม่ได้):** เปลี่ยน host port ที่ stack publish
ไปเป็นเลขที่ NAT ไม่ได้ forward ไว้ เช่น `14317`/`14318` — port ที่ NAT ส่งมาจะกลายเป็น
ปลายทางที่ไม่มีอะไรฟัง

```
Portainer → Stacks → signoz → Editor
  แก้ Environment variables:  SIGNOZ_OTLP_GRPC_PORT=14317
                              SIGNOZ_OTLP_HTTP_PORT=14318
  → Update the stack
```

**หมายเหตุสำคัญ: การตั้ง `SIGNOZ_BIND_ADDR` เป็น private IP ไม่ช่วยในกรณีนี้** เพราะ NAT
ทำ DNAT เขียน destination เป็น IP ของ VM อยู่แล้ว การผูก port ไว้กับ IP นั้นจึงยังรับ
traffic ที่ forward มาเหมือนเดิม — ต้องเอา forward ออกหรือย้ายพอร์ตเท่านั้น

- [ ] **Step 2: ถ้าเลือกทางเลือก B ให้แก้ค่า default ใน repo ให้ตรงกัน**

แก้ `.env.example` และตาราง Environment variables ใน `README.md` ให้เป็นเลขใหม่ พร้อม
เขียนเหตุผลว่าทำไมถึงไม่ใช่ 40317/40318 — ไม่งั้นคนถัดไปจะ "แก้กลับให้ตรงกับเอกสาร"
แล้วเปิดรูเดิมโดยไม่รู้ตัว

- [ ] **Step 3: ยืนยันจากนอก LAN ว่าปิดจริง**

รันจากเครื่องนอกวง (เครื่องของ user ไม่ใช่บน VM):

```bash
for p in 40317 40318; do
  printf "%s: " "$p"
  curl -s -o /dev/null -w "%{http_code}\n" --max-time 6 "http://dev.blueledgers.com:$p/" || echo "ปิดแล้ว"
done
```

ต้องได้ `000`/`ปิดแล้ว` ทั้งสองพอร์ต **ถ้ายังได้ 404 = ยังเปิดอยู่ อย่าเดินต่อ**

- [ ] **Step 4: ยืนยันว่าเส้นทาง LAN ยังใช้ได้หลังปิด**

ทำ Task 2 Step 3-4 ซ้ำอีกครั้ง (`service.name` ใช้ `phase0-after-lockdown` เพื่อแยกจากรอบแรก)
ต้องยังเห็น service ใหม่โผล่ใน UI

ถ้ารอบนี้ไม่ผ่านแต่รอบแรกผ่าน แปลว่า Step 1 ปิดกว้างเกินไป — ย้อนกลับก่อน อย่าปล่อยค้าง

**ถ้าเลือกทางเลือก B ค่า `OTEL_EXPORTER_OTLP_ENDPOINT` ที่ Task 2 พิสูจน์ไว้เปลี่ยนไปแล้ว** (host port ไม่ใช่เลขเดิม) ค่าที่ต้องบันทึกใน Task 5 คือค่าที่ผ่าน step นี้ ไม่ใช่ค่าจาก Task 2

- [ ] **Step 5: จัดการทางเข้า UI (`48080`)**

ตาม spec §5 ข้อ 3: ปิด forward ของ `48080` แล้วเข้าผ่าน SSH tunnel

```bash
ssh -L 48080:<SIGNOZ_LAN_IP>:8080 <DEV_SSH_USER>@dev.blueledgers.com -p <DEV_SSH_PORT>
# แล้วเปิด http://localhost:48080 บนเครื่องตัวเอง
```

เขียนคำสั่งนี้ลง `README.md` หัวข้อใหม่ "เข้า UI หลังปิด forward" — คนที่เข้าไม่ได้แล้ว
ไม่รู้วิธี จะไปเปิด forward กลับ

- [ ] **Step 6: บันทึกสิ่งที่ทำและสิ่งที่ยังเปิดอยู่ แล้ว commit**

ใน `docs/dev-host-facts.md` เพิ่มหัวข้อ "สถานะการเปิดสู่อินเทอร์เน็ต" ระบุให้ครบว่าพอร์ตไหน
ยังเปิดและทำไม — **ถ้ามีอะไรที่ปิดไม่ได้เพราะไม่มีสิทธิ์ ให้เขียนไว้ตรง ๆ ว่าเป็นความเสี่ยง
ที่ยอมรับไว้** ไม่ใช่เว้นว่างให้ดูเหมือนปิดครบ

```bash
cd ../SigNoz
git add -A
git commit -m "fix: close the public OTLP path and document how to reach the UI"
```

---

### Task 5: ตรึง convention ให้เฟส 1-4 อ้าง

**Files:**
- Create: `docs/otel-conventions.md`
- Modify: `docs/superpowers/specs/2026-08-23-carmen-otel-instrumentation-design.md` (§13)

**Interfaces:**
- Consumes: `OTEL_EXPORTER_OTLP_ENDPOINT` (Task 2), retention ที่ตั้งจริง (Task 3), พอร์ตสุดท้าย (Task 4)
- Produces: เอกสารที่เฟส 1-4 อ่านค่าคงที่ทุกตัวไปใช้

- [ ] **Step 1: เขียน `docs/otel-conventions.md`**

```markdown
# OTel conventions ของ Carmen

ค่าคงที่ทุกตัวที่เฟส 1-4 ต้องใช้ **อ่านจากที่นี่ที่เดียว ห้าม hardcode ซ้ำที่อื่น**
ที่มา: `docs/superpowers/specs/2026-08-23-carmen-otel-instrumentation-design.md`

## Endpoint

| env var | ค่า | ใช้กับ |
|---|---|---|
| `OTEL_EXPORTER_OTLP_ENDPOINT` | (กรอกค่าที่พิสูจน์แล้วจากเฟส 0 Task 2) | NestJS x6, Go x3, god-mode |
| `OTEL_ENDPOINT` ใน `public/config.json` | (กรอก) | carmen-spa, carmen-platform (ผ่าน gateway) |

**ไม่ตั้ง = SDK ไม่ start เลย** ไม่ใช่ start แล้วยิงไม่ถึง — exporter ที่ยิงไม่ถึงจะ retry
แล้วบวม memory เงียบ ๆ บนเครื่องที่ RAM ตึงอยู่แล้ว

## service.name (12 ตัว ห้ามตั้งชื่อใหม่)

backend-gateway · micro-business · micro-cluster · micro-file · micro-keycloak ·
micro-notification · micro-report · micro-cronjobs · micro-data · carmen-spa ·
carmen-platform · god-mode

ชื่อพวกนี้ตรงกับชื่อใน `start-dev.sh`, `rc-service`, และไฟล์ log ที่คนดูอยู่ทุกวันโดยตั้งใจ

## Resource attributes

| attribute | ค่า |
|---|---|
| `service.namespace` | `carmen` |
| `deployment.environment` | `dev` |
| `service.version` | git short sha ตอน build |

## Log attributes

| attribute | มาจาก |
|---|---|
| `carmen.tenant_id` | `IAMInfo.tenant_id` |
| `carmen.user_id` | `IAMInfo.user_id` |
| `carmen.auth` | `anonymous` เฉพาะที่มาทางช่อง pre-login |

prefix `carmen.` ทั้งหมด เพื่อกันชนกับ OTel semantic conventions ในอนาคต

## Retention ที่ตั้งจริง

(กรอกค่าจากเฟส 0 Task 3 พร้อมวันที่และ disk ที่ใช้ตัดสิน)
```

- [ ] **Step 2: กรอกค่าจริงลงทุกช่องที่เขียน `(กรอก...)`**

ถ้าช่องไหนยังไม่มีค่าจริง **อย่าใส่ค่าสมมติ** ให้เขียนว่ายังไม่มีและชี้ว่าติดที่ task ไหน

- [ ] **Step 3: ตัด §13 ของ spec ให้เหลือเฉพาะที่ยังไม่รู้จริง**

เปิด `docs/superpowers/specs/2026-08-23-carmen-otel-instrumentation-design.md` §13 แล้วลบแถวที่
เฟสนี้ตอบไปแล้ว (private IP, RAM, disk, retention, ใครคุม NAT) เหลือไว้เฉพาะที่ยังค้างจริง
เช่น Prisma preview feature — แล้วเพิ่มบรรทัดชี้ไปที่ `docs/dev-host-facts.md`

ตรวจ §5 ข้อ 2 ด้วย: ข้อนั้นถูกแก้เป็น "ไม่ช่วยในสถาปัตยกรรมนี้" ไปแล้วตอนเขียน plan ถ้า Task 4 ค้นพบอะไรที่ทำให้ข้อสรุปนั้นผิด ต้องแก้กลับพร้อมเหตุผล

spec ที่ยังบอกว่า "ไม่รู้" ทั้งที่รู้แล้ว จะทำให้คนทำเฟสถัดไปไปวัดซ้ำ

- [ ] **Step 4: Commit**

```bash
cd ../SigNoz
git add docs/otel-conventions.md docs/superpowers/specs/2026-08-23-carmen-otel-instrumentation-design.md
git commit -m "docs: lock the OTel conventions phases 1-4 depend on"
```

---

## เกณฑ์ผ่านของเฟส 0

ครบทั้ง 5 ข้อจึงเริ่มเฟส 1 ได้:

1. `docs/dev-host-facts.md` มีตัวเลขจริงครบ ไม่มีช่องที่เดาเอา
2. ยิง span จาก VM Carmen แล้วเห็น service โผล่ใน SigNoz UI จริง
3. `curl` จากนอก LAN ไปที่ OTLP port **ไม่ถึง**
4. retention ในหน้า Settings ตรงกับตัวเลขที่ตัดสินจาก disk จริง
5. `docs/otel-conventions.md` กรอกครบ ไม่มี `(กรอก...)` เหลือ

**ห้ามเริ่มเฟส 1 ถ้าข้อ 2 ไม่ผ่าน** — เฟส 1 คือการเสียบ SDK ลง `micro-report` ถ้าเส้นทาง
ยังไม่ได้พิสูจน์ เวลาไม่เห็นข้อมูลจะแยกไม่ออกว่าเพราะ SDK หรือเพราะ network
