# ข้อเท็จจริงของ dev host

**วัดเมื่อ:** 2026-08-23 (~10:40 +07)
**วัดยังไง:** Portainer UI + Docker API ผ่าน proxy ของ Portainer (`/api/endpoints/3/docker/*`) และ `curl` จากนอก LAN
**disk วัดเพิ่มเมื่อ:** 2026-08-23 ~10:49 ผ่าน Portainer Console ของ `signoz-telemetrystore-clickhouse-0-0`

> ค่าพวกนี้เก่าได้ ถ้าตัวเลขไม่ตรงกับที่เห็นตอนทำงานจริง ให้เชื่อของจริงแล้วอัปเดตไฟล์นี้

---

## VM ที่รัน Docker + SigNoz

| รายการ | ค่า |
|---|---|
| hostname | `container` (ชี้ว่าน่าจะเป็น LXC ไม่ใช่ VM เต็ม) |
| OS | Ubuntu 24.04.4 LTS · kernel 6.8.0-134-generic · x86_64 |
| CPU | 4 |
| RAM total | **7.75 GiB** (Portainer โชว์ 8.3 GB แบบ decimal) |
| cgroup | v2, driver `systemd` |
| Docker | 29.6.1 (API 1.55) · overlay2 · logging driver `json-file` |
| Docker root | `/var/lib/docker` |
| Portainer | CE 2.27.8 LTS · endpoint id **3** · เชื่อมผ่าน `/var/run/docker.sock` |
| stacks / containers | 7 stacks · 18 containers (รัน 16) · 26 volumes · 27 images |
| Docker footprint | images 9.08 GB · volumes 2.37 GB |
| **disk** | **98 GB รวม · ใช้ 34 GB · ว่าง 60 GB (37%)** บน `/dev/mapper/ubuntu--vg-ubuntu--lv` |

**สมมติฐานเดิมของ spec รอบวาง stack ("เครื่อง ~4 GB") ผิด — มี RAM มากกว่านั้นเท่าตัว**

disk เป็น LV เดียวที่ทุกอย่างใช้ร่วมกัน (`/var/lib/docker` อยู่บนนั้นด้วย) — Docker กินไป
ราว 11.5 GB (images 9.08 + volumes 2.37) ที่เหลืออีกราว 22 GB เป็นของอย่างอื่นบนเครื่อง
**ดิสก์เต็มจะกระทบทุก stack บนเครื่องนี้พร้อมกัน ไม่ใช่แค่ SigNoz**

---

## RAM ที่ใช้จริง

**รวม 2,440 MB จาก 7,941 MB → ว่างราว 5.5 GB**

| container | ใช้ (MB) | limit (MB) |
|---|---|---|
| keycloak_dev | 619 | ไม่จำกัด |
| wikijs-wiki-1 | 390 | ไม่จำกัด |
| minio | 281 | ไม่จำกัด |
| wikijs-developer-wiki-1 | 275 | ไม่จำกัด |
| **signoz-telemetrystore-clickhouse-0-0** | **170** | **1400** |
| wiki-carmen-colud-wiki-1 | 157 | ไม่จำกัด |
| wikijs-support-wiki-1 | 130 | ไม่จำกัด |
| **signoz-telemetrykeeper-clickhousekeeper-0** | **103** | **200** |
| portainer | 67 | ไม่จำกัด |
| wikijs-developer-db-1 | 54 | ไม่จำกัด |
| **signoz-signoz-0** | **53** | **600** |
| keycloak-postgres-1 | 42 | ไม่จำกัด |
| **signoz-ingester** | **31** | **400** |
| wikijs-db-1 · wikijs-support-db-1 · wiki-carmen-colud-db-1 | 25 · 24 · 19 | ไม่จำกัด |

**SigNoz ใช้จริงแค่ 357 MB จากงบ 2,600 MB** — เพราะยังไม่มีใครส่งข้อมูลเข้าไป ตัวเลขนี้จะโตขึ้น
มากเมื่อเฟส 1-4 เริ่มยิงของจริง ให้ถือ 2,600 MB เป็นค่าที่ต้องเผื่อ ไม่ใช่ 357 MB

**container ที่ไม่ใช่ SigNoz ไม่มี memory limit สักตัว** — ทุกตัวเห็นเพดานเป็น 7,941 MB
ถ้าตัวใดตัวหนึ่งรั่ว มันกิน RAM ที่ SigNoz ต้องใช้ได้หมดโดยไม่มีอะไรกั้น

---

## Published ports ของ SigNoz

| container | binding |
|---|---|
| `signoz-ingester` | **`0.0.0.0:40317->4317`** · **`0.0.0.0:40318->4318`** |
| `signoz-signoz-0` | **`0.0.0.0:48080->8080`** |
| `signoz-telemetrystore-clickhouse-0-0` | ไม่ publish ✅ |
| `signoz-telemetrykeeper-clickhousekeeper-0` | ไม่ publish ✅ |

ClickHouse กับ Keeper ไม่ publish ออกมาเลย ถูกต้องตามที่ออกแบบไว้

---

## ของอื่นบน host เดียวกัน

| stack | container | published |
|---|---|---|
| keycloak | `keycloak_dev` · `keycloak-postgres-1` | `0.0.0.0:8080` · **`0.0.0.0:5432`** |
| minio | `minio` | `0.0.0.0:3990->9000` · `0.0.0.0:3989->9001` |
| portainer | `portainer` | `0.0.0.0:9000` · `0.0.0.0:9443` · `0.0.0.0:8000` |
| wikijs ×4 | wiki + db อย่างละคู่ | `3985` · `3987` · `3991` · `3993` |

**ไม่มี Carmen service และไม่มี Loki container รันบนเครื่องนี้** — อยู่คนละ VM ตามที่คาดไว้

---

## Loki — เหลือแต่ซาก

ไม่มี container รันอยู่ แต่ volume ยังค้าง:

- `grafana-loki-portainer-stack_loki-data` — 0.31 GB
- `grafana-loki-portainer-stack_grafana-data` — 0.05 GB

แปลว่าเคยมี stack `grafana-loki-portainer-stack` (Loki + Grafana) บนเครื่องนี้แล้วถูกลบ/หยุดไป
เหลือ volume กำพร้า 0.36 GB **การ "ปิด Loki server" บนเครื่องนี้จึงไม่มีอะไรให้ปิด** เหลือแค่
ลบ volume ทิ้งถ้าแน่ใจว่าไม่ต้องการข้อมูลเก่า

ส่วน `:3998` ที่เคยตอบ 404 เมื่อ ~09:47 กลับไม่ตอบเลยตอน ~10:45 — **ยังไม่ยืนยันว่าอะไรฟังอยู่
ตรงนั้นและอยู่เครื่องไหน** อย่าเขียนลงเอกสารว่า "Loki อยู่ VM Carmen" จนกว่าจะเห็นจริง

---

## Retention — ตั้งแล้ว 2026-08-23

| signal | ก่อน | หลัง | เก็บที่ |
|---|---|---|---|
| Traces | 15 Days | **3 Days** (`traces_ttl_duration_hrs: 72`) | v1 (legacy) |
| Logs | 15 Days | **7 Days** (`default_ttl_days: 7`) | **v2 custom retention** |
| Metrics | 1 Months | 1 Months (`metrics_ttl_duration_hrs: 720`) — ไม่แตะ | v1 (legacy) |

ตัดสินจาก disk ว่าง 60 GB (ชั้น `> 50 GB` ของตารางในแผนเฟส 0)

### กับดักสามชั้นของ retention บน v0.137.1

**1. `README.md` ชี้เมนูผิด** — ไม่มี "Settings → Retention" แล้ว ของจริงอยู่ที่
**Settings → Workspace → RETENTION CONTROLS** และหน่วยของ Metrics เป็น **Months** ไม่ใช่ Days

**2. TTL แยกเป็นสองระบบ ไม่มีที่ไหนบอกไว้**

- traces + metrics → API **v1** (`GET /api/v1/settings/ttl?type=…` เป็นตัวจริง)
- logs → **v2 custom retention** (`POST /api/v2/settings/ttl` body `{type, defaultTTLDays}`)
- `POST /api/v1/settings/ttl` ตายแล้ว ตอบ 500 `"SetTTLV2 only supported"`
- `POST /api/v2/settings/ttl` กับ `type: "traces"` ตอบ 400
  `"custom retention TTL only supported for logs"`

**3. `GET /api/v1/settings/ttl?type=logs` คืน `-1` ทั้งที่ตั้งค่าไว้แล้ว** — เพราะ v1 ไม่รู้จัก
logs อีกต่อไป **อย่าอ่าน `-1` ว่า "ไม่มี TTL"** ต้องถาม v2 สำหรับ logs เท่านั้น
(`GET /api/v2/settings/ttl` ไม่สนใจ `?type=` — ตอบ record ของ logs ให้ทุก type)

**4. UI ไม่ยิงขอค่า logs ตอนโหลดหน้า** — `performance.getEntriesByType('resource')` เห็นแค่
`type=metrics` กับ `type=traces` ตัวเลข logs บนจอจึงไม่ใช่ค่าที่ยืนยันจาก server
**ห้ามใช้หน้าจอเป็นหลักฐาน ให้ถาม API**

## Service Accounts

มี 1 รายการ: `carmen@signozserviceaccount.com` สถานะ **DELETED** (เคยมีคนสร้างแล้วลบ)

Service account ของ SigNoz เป็น token สำหรับ **API ของ SigNoz** ไม่ใช่ ingestion key ของ OTLP —
receiver ใน compose ไม่มี auth extension ใด ๆ ข้อสรุปเดิมของ spec ที่ว่า "OTLP ไม่มี auth"
**ยังคงถูกต้อง**

---

## สถานะการเปิดสู่อินเทอร์เน็ต (curl จากนอก LAN, 2026-08-23 ~10:45)

| port | ผล | คือ |
|---|---|---|
| **9000** | **200** | **Portainer — เปิดสู่อินเทอร์เน็ตผ่าน HTTP ล้วน** |
| 48080 | 200 | SigNoz UI (HTTP ล้วน) |
| 40318 | 404 | SigNoz OTLP/HTTP — receiver ฟังอยู่ ไม่มี auth |
| 8080 | 302 | Keycloak |
| 3993 | 302 | wiki.js |
| 5432 | — | ตรวจไม่ได้ (Postgres ไม่ใช่ HTTP และ sandbox บล็อก raw TCP) **ต้องตรวจซ้ำด้วย `nc`** |
| 3998 | ไม่ตอบ | เคยตอบ 404 เมื่อ ~09:47 — ไม่ยืนยัน |

`40318` ตอบ 404 (ไม่ใช่ connection reset) แปลว่า **มี organization ในระบบแล้ว** — pipeline
ไม่ได้ถูก rewrite เป็น `nop` ขั้นตอน "สร้าง admin account" ทำไปแล้ว
