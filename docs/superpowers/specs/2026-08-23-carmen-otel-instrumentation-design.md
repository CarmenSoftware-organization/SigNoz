# Design: ต่อ Carmen ทุก service เข้า SigNoz ด้วย OpenTelemetry

**วันที่:** 2026-08-23
**สถานะ:** design ผ่านการเคาะทีละส่วนในบทสนทนาแล้ว — รอ review ตัวเอกสารก่อนทำ implementation plan
**spec ก่อนหน้า:** `2026-08-18-signoz-portainer-design.md` (วาง stack — งานนี้คือ "รอบถัดไป" ที่ spec นั้นระบุว่าอยู่นอกสโคป)

---

## 1. ปัญหาและบริบท

SigNoz ขึ้นแล้วบน `dev.blueledgers.com` (UI `:48080` ตอบ 200, OTLP `:40318` มี receiver ฟังอยู่)
แต่ยังไม่มี service ไหนของ Carmen ส่งอะไรเข้าไปเลย stack จึงว่างเปล่า

เป้าหมายของ spec นี้: ทำให้ **12 app ใน 5 repo** ส่ง log + trace + metric เข้า SigNoz บน
environment `dev` โดยไม่เปิดช่องโหว่ใหม่ และไม่ทิ้งระบบ logging เดิมไว้ให้เป็นซาก

### 1.1 สิ่งที่ค้นพบระหว่างสำรวจ (เปลี่ยนรูปงานจากที่ตั้งต้นคิด)

**ค้นพบที่ 1 — log ของแอปฝั่ง NestJS ไม่เคยออกจาก process**

ทุก app มีเส้นทาง log สองเส้นที่แยกขาดจากกัน:

| เส้น | ใคร | ปลายทางจริงวันนี้ |
|---|---|---|
| `winstonLogger` (`backend.logger.ts:~429`) → Console + `LokiTransport` | ถูกตั้งเป็น Nest app logger ใน `main.ts` (`WinstonModule.createLogger`) | ถึง Loki — แต่ได้เฉพาะ log ระดับ framework |
| `class BackendLogger extends ConsoleLogger` | โค้ดแอปเรียกเอง **701 จุด** | **stdout เท่านั้น** |

ยืนยันด้วยการไล่ `super.*` ทุกบรรทัดในคลาส (`backend.logger.ts` บรรทัด 76, 108, 143, 178, 213,
226, 258, 300, 340, 382, 422) — ทุกเมธอดจบที่ `ConsoleLogger` ไม่มีบรรทัดไหนแตะ `winstonLogger`
รวมถึง `logPerformance()` และ `logBusinessEvent()` ที่ตั้งใจสร้างมาเพื่อส่งขึ้นระบบกลาง

การกระจายของ 701 จุด: gateway 377 · business 282 · cluster 30 · keycloak 6 · file 5 · notification 1

**ผลต่อ design:** งานนี้ไม่ใช่การย้ายปลายทางจาก Loki ไป SigNoz แต่คือ **การต่อท่อที่ขาดอยู่เป็น
ครั้งแรก** ดังนั้น volume ที่ SigNoz จะได้รับ **มากกว่าที่ Loki เคยรับหลายเท่า** ไม่ใช่เท่าเดิม
ซึ่งกระทบการตั้ง retention โดยตรง

**ค้นพบที่ 2 — distributed trace ได้ฟรี**

`@repo/nest-http-transport` ใช้ `node:http createServer` (`http-transport.server.ts:1,66`) ฝั่ง
server และ `axios` (`http-client.proxy.ts:42`) ฝั่ง client — เป็น HTTP จริงทั้งคู่ ไม่ใช่ Nest TCP
transport ดังนั้น `@opentelemetry/instrumentation-http` จะ inject/extract `traceparent` ให้เอง
**trace วิ่งข้าม gateway → business → cluster ได้โดยไม่ต้องเขียนโค้ด propagation** (ถ้าเป็น TCP
transport เรื่องนี้จะกลายเป็นงานใหญ่ที่สุดของทั้ง spec)

**ค้นพบที่ 3 — dev ไม่ได้รันบน Bun**

`scripts/start-dev.sh:51-55` รัน service ทั้งหมดด้วย `node dist/main` — ความเสี่ยง
"Bun monkey-patch `require` ไม่ครบ" ที่ spec รอบก่อนเตือนไว้ **ไม่มีผลกับ dev** สำหรับ 6 app นี้
Bun ใช้เฉพาะตอน build และ healthcheck ของ Docker (ซึ่งเป็นเส้นทาง deploy คนละเส้น)

ข้อยกเว้นเดียวคือ `carmen-inventory-god-mode` ที่รันด้วย `bun next dev` จริง — ดูข้อ 8

**ค้นพบที่ 4 — logger มี 6 สำเนาที่เริ่มแยกทางกันแล้ว**

`backend.logger.ts` ถูกก๊อปไว้ใน 6 app ขนาด 111–503 บรรทัด และเริ่มไม่เหมือนกัน:
`micro-notification` ไม่มี `LokiTransport` เลย · `micro-business` มี jest guard ที่อีก 5 ตัวไม่มี
(`isJest` — กัน LokiTransport ค้าง keep-alive timer จน jest ไม่ยอมจบ) · `config.loki.ts` ก็ถูก
ก๊อปตามไปด้วยทุก app

**ค้นพบที่ 5 — topology**

`dev.blueledgers.com` = `49.228.26.151` เป็น public IP เดียวที่ NAT forward ไปหลาย VM
(`:443` ตอบ `Microsoft-IIS/10.0` ขณะที่ deploy workflow ใช้ `rc-service` = OpenRC/Alpine
สองอย่างนี้อยู่เครื่องเดียวกันไม่ได้)

Service ของ Carmen ทั้ง 9 ตัวอยู่ VM เดียวกัน — ยืนยันจาก
`apps/backend-gateway/.env.example:33-41` ที่ชี้ `REPORT_SERVICE_HOST=localhost`,
`DATASET_SERVICE_HOST=localhost`, `CRONJOB_SERVICE_URL=http://localhost:6016`

**ค้นพบที่ 6 — OTLP เปิดสู่อินเทอร์เน็ตโดยไม่มี auth**

`curl` จากเครื่องนอก LAN ถึง `:40318` ได้ (ตอบ 404 ที่ `/` = receiver ฟังอยู่) SigNoz OSS ไม่มี
ingestion key ใครก็ตามที่ยิงถึงยัด telemetry เข้ามาได้ไม่จำกัดจนดิสก์เต็ม README ของ stack
เตือนเรื่องนี้ไว้เองแล้ว แต่ default `SIGNOZ_BIND_ADDR=0.0.0.0` ยังคาอยู่

---

## 2. การตัดสินใจ

| # | ประเด็น | ตัดสิน | เหตุผล |
|---|---|---|---|
| 1 | วิธีเก็บ | แก้โค้ดให้แต่ละ app ยิง OTLP เอง | ได้ log ที่มี structure + ผูกกับ trace ได้ ต่างจากการกวาดไฟล์ที่ต้อง parse กลับและไม่มี trace correlation |
| 2 | Loki | **ลบทิ้งทั้งหมด ไม่ต้องมีประตูกั้น** | 701 จุดไม่เคยถึง Loki อยู่แล้ว และไม่มีใครเปิดดู การลบจึงไม่มีอะไรให้เสีย — เป็น cleanup ไม่ใช่ migration |
| 3 | ขอบเขต | NestJS 6 + Go 3 + browser 2 + god-mode = 12 app / 5 repo | ไม่รวม `carmen-wiki`, `carmen-inventory-mobile` |
| 4 | signal | log + trace + metric ครบสาม | |
| 5 | environment | `dev` เท่านั้น | UAT/prod เปิดทีหลังด้วยการเติม env var ไม่ต้องแก้โค้ด |
| 6 | ทางเข้าของ browser | ผ่าน gateway ที่มี auth เดิม | ไม่ต้องเปิด port ใหม่สู่อินเทอร์เน็ต |
| 7 | pre-login telemetry | เก็บ ผ่านช่อง anonymous ที่จำกัดหนัก | บั๊กหน้า login คือกลุ่มที่กระทบหนักที่สุด (เข้าระบบไม่ได้เลย) |
| 8 | logger 6 สำเนา | ยุบเป็น `@repo/observability` ลบทิ้งทั้ง 6 | แก้ที่เดียวครอบ 701 จุด และหยุดความเพี้ยนที่กำลังโต |

---

## 3. สถาปัตยกรรม

### 3.1 สามโซน

```
โซน A — LAN (หลัง NAT)                        โซน B — อินเทอร์เน็ต
┌───────────────────────┐  ┌──────────────┐   ┌─────────────────┐
│ VM: Carmen            │  │ VM: SigNoz   │   │ เบราว์เซอร์ผู้ใช้ │
│  NestJS x6 (node)     │──┼─► :4317 gRPC │   │  carmen-spa     │
│  Go x3 (OpenRC)       │  │  :4318 HTTP  │   │  carmen-platform│
│  god-mode (bun/next)  │  │  :8080 UI    │   └────────┬────────┘
└──────────┬────────────┘  └──────────────┘            │ HTTPS
           │                                            │
           └── gateway :4000 ◄──────────────────────────┘
               forward เข้า LAN
```

**กฎเดียวที่คุมทั้งระบบ:** telemetry ไม่ออกอินเทอร์เน็ต ยกเว้นขาที่มาจากเบราว์เซอร์
ซึ่งต้องผ่าน gateway ที่มี auth

### 3.2 เส้นทางต่อ app

| ต้นทาง | ปลายทาง | protocol |
|---|---|---|
| NestJS x6, Go x3, god-mode | `<signoz-lan-ip>:4317` | OTLP/gRPC |
| carmen-spa, carmen-platform | `{BACKEND_URL}/telemetry/v1/*` → gateway → LAN | OTLP/HTTP |

### 3.3 สวิตช์เปิด-ปิด

ทุก app อ่าน `OTEL_EXPORTER_OTLP_ENDPOINT` (ฝั่ง browser อ่าน `OTEL_ENDPOINT` จาก
`public/config.json`) — **ไม่ตั้ง = SDK ไม่ start เลย ไม่ใช่ start แล้วยิงไม่ถึง**

เหตุผลที่ต้องเป็น "ไม่ start" ไม่ใช่ "start แล้ว fail เงียบ": exporter ที่ยิงไม่ถึงจะ retry และ
บวม memory ไปเรื่อย ๆ โดยไม่มีอะไรฟ้อง — บนเครื่อง dev ที่ RAM ตึงอยู่แล้วนี่คือการทำให้ระบบ
ล่มด้วยเครื่องมือที่ติดตั้งมาเพื่อดูว่าระบบล่มเพราะอะไร

นี่คือกลไกที่ทำให้ "dev อย่างเดียว" เป็นจริงโดยไม่ต้อง branch โค้ด และทำให้ขยายไป UAT/prod
ได้ด้วยการเติม env var อย่างเดียว

### 3.4 สิ่งที่จงใจไม่ทำ (YAGNI)

**OTel Collector เป็น relay บน VM Carmen** — จะให้ retry-on-disk (SigNoz ล่มแล้ว log ไม่หาย),
จุด redact PII จุดเดียว, และแยก app config ออกจากที่อยู่ SigNoz ทั้งหมดนี้มีค่าจริง แต่บน dev
ไม่คุ้มกับการเพิ่ม process ที่ต้องดูแล — และแทรกทีหลังได้โดยแก้แค่ env var ตัวเดียวต่อ app
เพราะ endpoint ถูก config ไว้อยู่แล้ว

---

## 4. Convention (เคาะในเฟส 0 — ทุกเฟสหลังจากนี้อ้างจากตรงนี้)

### 4.1 `service.name`

ใช้ชื่อที่มีอยู่แล้วในระบบ ไม่ประดิษฐ์ใหม่ เพราะมันตรงกับชื่อใน `start-dev.sh`, `rc-service`
และชื่อไฟล์ log ที่คนดูอยู่ทุกวัน:

```
backend-gateway · micro-business · micro-cluster · micro-file · micro-keycloak
micro-notification · micro-report · micro-cronjobs · micro-data
carmen-spa · carmen-platform · god-mode
```

### 4.2 Resource attributes

| attribute | ค่า | หมายเหตุ |
|---|---|---|
| `service.namespace` | `carmen` | แยกไว้เผื่อ SigNoz ตัวนี้รับของระบบอื่นในอนาคต |
| `deployment.environment` | `dev` | ตัวเดียวที่เปลี่ยนตอนขยาย env |
| `service.version` | git short sha ตอน build | ตอบ "บั๊กนี้เกิดหลัง deploy ไหน" ได้ตรง ๆ |

### 4.3 Log attributes

| attribute | มาจาก |
|---|---|
| `carmen.tenant_id` | `IAMInfo.tenant_id` ที่ทุกเมธอดของ `BackendLogger` รับอยู่แล้ว (`backend.logger.ts:5-8`) |
| `carmen.user_id` | `IAMInfo.user_id` |
| `carmen.auth` | `anonymous` เฉพาะ record ที่มาทางช่อง pre-login (ข้อ 8.3) |

prefix `carmen.` ทั้งหมดเพื่อกันชนกับ OTel semantic conventions ที่อาจนิยามคีย์ชื่อเดียวกัน
ในอนาคต

**701 จุดที่ส่ง `iam` มาอยู่แล้วจะกลายเป็น attribute ที่ filter ได้ใน SigNoz ทันที
โดยไม่ต้องแก้ call site สักจุด** — นี่คือเหตุผลหลักที่เลือกยุบเป็น package แทนที่จะเปลี่ยน API

---

## 5. งาน infra (เฟส 0)

| # | ทำอะไร | ทำไม |
|---|---|---|
| 1 | ยกเลิก NAT forward ของ `40317`/`40318` | วันนี้ใครก็ได้บนเน็ตยัด telemetry จนดิสก์เต็มได้ (ค้นพบที่ 6) |
| 2 | ตั้ง `SIGNOZ_BIND_ADDR` เป็น private IP ของ VM SigNoz | กันไม่ให้ผูก `0.0.0.0` ซ้ำรอย |
| 3 | UI `:48080` — **ปิด NAT forward เข้าผ่าน SSH tunnel** | วันนี้รหัสผ่าน admin วิ่งเป็น HTTP อ่านได้ เลือก tunnel เพราะไม่ต้องออก cert และคนที่ต้องเข้ามีไม่กี่คน ถ้าวันหนึ่งคนดูเยอะขึ้นค่อยเปลี่ยนเป็น reverse proxy ที่ terminate TLS |
| 4 | ตั้ง retention ตามข้อ 9 | trace+metric ของ 12 app กินดิสก์เร็วกว่า log อย่างเดียวมาก |
| 5 | ตัดสินใจว่าจะปิด Loki server (`:3998`) ด้วยไหม | คืน RAM ให้ VM กลุ่มเดียวกับที่ SigNoz กำลังขาด — **ลบ transport ในโค้ด ≠ ปิด server** เป็นคนละงาน ตัดสินพร้อมตัวเลข RAM จริง |
| 6 | เก็บตัวเลขจริง: RAM ว่าง, disk ว่าง, private IP ของ VM SigNoz, VM Carmen ยิงถึงไหม | spec รอบก่อนตั้งงบ 2.6 GB บนสมมติฐานว่าเป็นเครื่องแยก ซึ่งผิด |

---

## 6. ฝั่ง NestJS — `packages/observability`

repo `carmen-turborepo-backend-v2` มี `packages/*` workspace + convention `@repo/*` อยู่แล้ว
(14 package, `@repo/log-events-library` มี 4 app ใช้) ของใหม่อยู่ในรูปเดียวกัน

```
packages/observability/src/
  bootstrap.ts   startTelemetry() — NodeSDK: trace + metric + log
                 endpoint ไม่ตั้ง = return ทันที ไม่ start อะไรเลย
  winston.ts     OTLP transport เสียบเข้า winstonLogger
  logger.ts      BackendLogger ที่ delegate ลง winston (API เดิมครบทุกเมธอด)
  redact.ts      กัน password/token/secret หลุด (ลอกแนวจาก log-events-library/src/utils/redact.ts)
```

### 6.1 ลำดับ boot — จุดที่พังเงียบที่สุด

`startTelemetry()` ต้องรัน **ก่อน** `import` อะไรก็ตามที่ต้องถูก patch (`http`, `pg`,
`@prisma/client`) การวางเป็นบรรทัดแรกใน `main.ts` **ไม่พอ** เพราะ ES module hoist `import`
ขึ้นไปก่อน statement เสมอ

ต้องใช้ทางใดทางหนึ่ง:
- `node --require ./otel.js dist/main` (แก้ `start-dev.sh` ที่บรรทัด `SERVICE_*`)
- แยกเป็นไฟล์ที่มี side effect แล้วให้ `main.ts` `import './otel'` เป็นบรรทัดแรกสุด

**อาการเมื่อทำผิด: SDK start สำเร็จ ไม่มี error แต่ได้ span เปล่า** ไม่มีอะไรฟ้องเลย
นี่คือ task แรกของเฟส 2 และต้องพิสูจน์ด้วยการเห็น span จริงก่อนทำอย่างอื่นต่อ

### 6.2 การยุบ 6 สำเนา

`BackendLogger` เก็บ API เดิมทุกเมธอด (`log`, `error`, `warn`, `debug`, `verbose`,
`logPerformance`, `logBusinessEvent`) — 701 call site ไม่ต้องแก้สักจุด สิ่งที่เปลี่ยนคือข้างใน:
จาก `super.*` (ConsoleLogger) เป็น delegate ลง winston ซึ่งมีทั้ง Console transport (คนยังเห็น
log ในเทอร์มินัลเหมือนเดิม) และ OTLP transport

**ต้องรักษาไว้:** jest guard ของ `micro-business` (`isJest`) — เหตุผลเดิมยังใช้ได้กับ OTLP
exporter ที่มี keep-alive timer เหมือนกัน ถ้าไม่ยกมาด้วย test suite จะค้างไม่ยอมจบ

### 6.3 ที่ต้องยืนยันตอน implement

- **Prisma 7.9.1 + `@prisma/instrumentation`** — เช็คว่ายังต้องเปิด preview feature `tracing`
  ไหม (Prisma เปลี่ยนเรื่องนี้หลายรอบ) ถ้าเปิดไม่ได้ = ไม่เห็น query span แต่ log และ trace
  ระดับ HTTP ยังได้ครบ ไม่ถือว่าเฟสล้ม
- **`micro-notification`** เป็นตัวที่เพี้ยนจากพวก (ไม่มี Loki, `BackendLogger` แค่ 1 จุด)
  ใช้เป็นตัวแรกที่เสียบ package ได้ — ผลกระทบต่ำสุดถ้าออกแบบ interface ผิด

---

## 7. ฝั่ง Go (3 service)

### 7.1 จุดที่ต้องแตะ — เล็กมาก

ตัวอย่างจาก `micro-report` (ตัวที่สะอาดที่สุด จึงเป็น pilot):

| ไฟล์ | ของเดิม | เพิ่ม |
|---|---|---|
| `cmd/server/main.go:32` | `logger, _ := zap.NewProduction()` | ห่อ core ด้วย `otelzap` — log ทุกบรรทัดที่มีอยู่แล้วไหลเข้า OTLP โดยไม่แก้ call site |
| `cmd/server/main.go` (ต้นฟังก์ชัน) | — | `shutdown := otel.Init(cfg)` + `defer shutdown(ctx)` |
| `routes/routes.go:31-32` | `r := gin.New()` / `r.Use(GinRecovery, GinLogging)` | แทรก `otelgin.Middleware("micro-report")` หน้าสุดของ chain |

`applyLogLevel` (`main.go:133`) ห่อ zap อยู่แล้ว โครงสร้างจึงรองรับการห่อ core เพิ่มโดยธรรมชาติ
และไม่มีปัญหา "ต้อง patch ก่อน import" เพราะ Go ต่อ middleware ตรง ๆ ไม่ได้ patch อะไร

### 7.2 ความต่างของแต่ละตัว

- **`micro-cronjobs` ไม่มี HTTP request** — งานเป็น scheduled job ไม่มี `otelgin` ให้เกาะ
  ต้องสร้าง root span เองต่อรอบงาน (`tracer.Start(ctx, "job:"+name)`) ไม่งั้นได้แต่ log ลอย ๆ
  ที่ไม่มี trace ผูก **นี่เป็นงานเขียนโค้ดจริง ไม่ใช่เสียบ middleware**
- **`micro-data` ไม่มี CI ไป dev** — deploy ด้วยมือผ่าน `deploy/deploy.sh` (ซึ่งใช้ `rc-service`
  จริง) ต้องเขียนขั้นตอนนี้ไว้ใน plan ไม่งั้นแก้โค้ดเสร็จแล้วของไม่ขึ้นโดยไม่มีใครรู้
- **shutdown flush** — ทั้งสามตัวต้อง `defer shutdown(ctx)` ที่รอ exporter ส่งของค้างให้หมด
  ไม่งั้น log/span ช่วงก่อนปิดหายทุกครั้งที่ `rc-service restart` ซึ่งคือ**ช่วงที่คนอยากดูมากที่สุด**

---

## 8. ฝั่ง browser + god-mode

### 8.1 gateway เป็น proxy โง่ ๆ ไม่ใช่ตัวแปลง

```
SPA → POST {BACKEND_URL}/telemetry/v1/{traces,logs}
      Authorization: Bearer <access token เดิม>
      Content-Type: application/x-protobuf   (OTLP มาตรฐาน)
    → gateway :4000  (guard เดิม + rate limit + cap body)
    → stream body ต่อแบบไม่แกะ → SigNoz LAN :4318
```

SPA ใช้ `OTLPTraceExporter` มาตรฐานแล้วชี้ `url` มาที่ gateway เท่านั้น gateway ไม่ต้องรู้จัก
OTLP schema ไม่ต้อง parse ไม่ต้อง maintain contract — ถ้าออกแบบ JSON format ของตัวเอง จะต้อง
เขียนทั้งฝั่งส่ง ฝั่งแปลง และดูแลมันตลอดไป โดยได้ผลลัพธ์เท่ากันเป๊ะ

### 8.2 สิ่งที่ต้องเพิ่มที่ gateway (ไม่มีวันนี้)

`main.ts` มีแค่ `cors: true` (สะท้อน origin ที่ขอมา) และ **ไม่มี `@nestjs/throttler` ใน
dependency เลย** — endpoint นี้จึงเป็น endpoint แรกของระบบที่จำเป็นต้องมี rate limit จริง

| ต้องมี | ทำไม |
|---|---|
| rate limit ต่อ user/IP | ไม่มี = ย้ายรูที่เพิ่งปิดจาก `:40318` มาไว้ที่ `:4000` แทน |
| cap ขนาด body แยกจาก `BODY_LIMIT` ปัจจุบัน (`main.ts:74` = `'2mb'`) | 2 MB ต่อ request คูณ N tab = ดิสก์หายเร็วมาก |
| ตรวจ content-type ปฏิเสธที่ไม่ใช่ OTLP | กันใช้เป็น open relay ยิงอะไรก็ได้เข้า LAN |

### 8.3 ช่อง anonymous (pre-login) — ต้องนิยามให้แคบมาก

เปิดช่องนี้ = ยอมรับความเสี่ยงที่เพิ่งปิดไปบางส่วนกลับมา เพดานจึงต้องแคบจนใช้ก่อกวนไม่คุ้ม:

| ข้อจำกัด | ค่า |
|---|---|
| path | `/telemetry/v1/logs` เท่านั้น — **ไม่รับ trace** |
| severity | `ERROR` ขึ้นไปเท่านั้น |
| body | <= 16 KB |
| จำนวน record | <= 5 ต่อ request |
| rate ต่อ IP | เข้มกว่าช่องที่ login แล้วอย่างน้อย 10 เท่า |
| attribute | allowlist เท่านั้น ไม่รับ attribute อิสระ |
| ติดธง | `carmen.auth=anonymous` ทุก record |
| ปิดฉุกเฉิน | ต้องปิดได้ด้วย env var ตัวเดียวโดยไม่ต้อง deploy โค้ดใหม่ |

### 8.4 รายละเอียดที่พลาดง่าย

**`propagateTraceHeaderCorsUrls`** — OTel web SDK ไม่ใส่ `traceparent` ให้ request ข้าม origin
โดย default ต้องตั้ง option นี้ให้ตรงกับ `BACKEND_URL` **ถ้าลืม จะได้ trace ฝั่งเบราว์เซอร์กับ
ฝั่ง backend เป็นคนละเส้นแยกกัน ซึ่งทำลายเหตุผลหลักที่เลือก SigNoz ตั้งแต่แรก**

**คีย์ใน `public/config.json` เป็น gitignore** — เพิ่ม `OTEL_ENDPOINT?: string` ลง
`RuntimeConfig` (`lib/runtime-config.ts:5`) ตามแบบเดิมของ repo ที่ห้าม hardcode backend URL
ลง bundle แต่ `public/config*.json` ถูก gitignore ทุกไฟล์ยกเว้น sample — **กับดักเดียวกับ
`LICENSE_ENFORCEMENT`** ต้องเติมคีย์ด้วยมือในทุก environment ไม่งั้น deploy แล้วเงียบสนิท
โดยไม่มี error (ไม่ตั้งคีย์ = telemetry ปิด ซึ่งเป็น default ที่ถูกต้อง แต่ต้องเขียนไว้ให้ชัด)

**`carmen-platform` เป็นคนละ repo** — แชร์ npm package ข้าม repo ไม่ได้ (ไม่มี private registry)
ต้องก๊อปโมดูลไป จึงต้องเขียนให้เล็กพอที่การก๊อปไม่เจ็บ (~1 ไฟล์) ไม่ใช่ตั้ง registry เพื่อ 2 repo

### 8.5 ขอบเขตของสิ่งที่ส่งจากเบราว์เซอร์

| ส่ง | ไม่ส่ง |
|---|---|
| `window.onerror`, `unhandledrejection` | `console.log` ทั้งหมด (volume ระเบิด + PII) |
| `RootErrorBoundary` ที่ catch ได้ | keystroke / form value |
| fetch span ที่ error หรือช้าเกิน threshold | fetch span ปกติทุกอัน (sample) |
| document-load 1 span ต่อ session | |

**`lib/analytics.ts` (click analytics ที่มีอยู่) ไม่ถูกแทนที่ด้วย OTel** — ตอบคำถามคนละแบบ
(พฤติกรรมผู้ใช้ vs สุขภาพระบบ) ปลายทางคนละที่ และมี rollup ของตัวเองอยู่แล้ว

### 8.6 god-mode — Bun กลับมามีผลที่นี่ที่เดียว

`carmen-inventory-god-mode` เป็น Next.js 16.2.9 + React 19.2.4 รันด้วย `bun next dev`
(ยังไม่มี `instrumentation.ts`) Next.js มี hook `instrumentation.ts` ที่ทำมาเพื่อ OTel โดยเฉพาะ
แต่ auto-instrumentation ข้างใต้ยังพึ่ง `require-in-the-middle` เหมือนเดิม บน Bun อาจได้ SDK
ที่ start สำเร็จแต่ไม่มี span

**ตั้งเป้าต่ำโดยตั้งใจ:** เอาแค่ log + span ที่สร้างเองรอบ operation ที่มีความหมาย (delete,
raw SQL, migration — repo นี้มี audit table ของตัวเองอยู่แล้ว จุดเสียบจึงชัด) ถ้า
auto-instrumentation ทำงานด้วยถือเป็นกำไร **ไม่ใช่เงื่อนไขความสำเร็จของเฟส** การไล่ให้
Bun+Next+OTel ทำงานเต็มรูปแบบควรเป็น spike แยก ไม่ใช่ส่วนหนึ่งของงานนี้

---

## 9. การถอด Loki และ retention

### 9.1 ถอด Loki — เป็น cleanup ไม่ใช่ migration

เนื่องจาก 701 จุดไม่เคยถึง Loki และไม่มีใครเปิด Loki ดู การลบจึงไม่ต้องรอ SigNoz พร้อม
**ทำแยกได้เลยและทำก่อนก็ได้** สิ่งที่ต้องลบ:

- `winston-loki` ออกจาก `package.json` ทั้ง 6 app
- `src/libs/config.loki.ts` และ `src/common/libs/config.loki.ts` (micro-business มีสองที่)
- `LOKI_HOST` / `LOKI_PORT` / `LOKI_PROTOCOL` / `LOKI_USERNAME` / `LOKI_PASSWORD`
  ออกจาก `.env.example` ทุก app และจาก `.env` จริงบน dev
- บรรทัดที่อ้าง `LOKI_*` ใน `carmen-turborepo-backend-v2/CLAUDE.md:76`

**การปิด Loki server (`:3998`) เป็นคนละงาน** อยู่ในเฟส 0 ข้อ 5 ตัดสินพร้อมตัวเลข RAM

### 9.2 Retention ตั้งต้น

volume จะมากกว่าที่ Loki เคยรับหลายเท่า (701 จุดเพิ่งได้ต่อท่อครั้งแรก) บวก trace + metric
ของ 12 app

| signal | เสนอ | เหตุผล |
|---|---|---|
| logs | 7 วัน | ครอบ sprint ปัจจุบัน บน dev ไม่มีใครย้อนดูเกินนี้ |
| traces | 3 วัน | กินที่มากที่สุดต่อ byte มีค่าเฉพาะตอนไล่บั๊กสด ๆ |
| metrics | 30 วัน | เล็กที่สุด และเป็นตัวเดียวที่มีประโยชน์แบบดูย้อนหลัง |

ต้องยืนยันกับ disk จริงในเฟส 0 — **ถ้า disk ว่างน้อยกว่า 20 GB ต้องหั่นลงทั้งแถวตั้งแต่แรก**
ไม่ใช่รอไปแก้ตอนดิสก์เต็ม (ClickHouse กลายเป็น read-only แล้วกู้ยากกว่ามาก)

---

## 10. แผนเฟสและแผนตรวจสอบ

design เดียว แต่ implementation plan แยก 5 ใบ ทำทีละใบ

| เฟส | เนื้อหา | ผ่านเมื่อ |
|---|---|---|
| **0. ฐานราก** | งาน infra ข้อ 5 ทั้งหมด + เคาะ convention ข้อ 4 | รู้ RAM/disk/LAN IP จริง · ยิง `:40317/:40318` จากนอก LAN **ไม่ถึง** แล้ว · `smoke-test/send-trace.sh` ยิงจาก VM Carmen เข้า LAN แล้วเห็น span ใน UI |
| **1. Pilot — `micro-report`** | otelzap + otelgin + OTLP/gRPC ครบสาม signal | เรียก endpoint จริงแล้วเห็นครบสาม: span ของ request, log ที่มี `trace_id` เดียวกัน, metric ของ process |
| **2. NestJS 6 apps** | `@repo/observability` + ยุบ 6 สำเนา + ลบ Loki | เห็น trace เส้นเดียวไหลข้าม gateway → business → cluster · เห็น log จาก `BackendLogger` · `LOKI_*` หายจาก repo |
| **3. Go ที่เหลือ** | `micro-cronjobs` (root span ต่อ job) + `micro-data` | `micro-cronjobs` มี span ต่อรอบงานไม่ใช่ log ลอย · `micro-data` deploy ด้วยมือแล้วขึ้นจริง |
| **4. Browser + god-mode** | gateway telemetry proxy + web SDK 2 repo + `instrumentation.ts` | ทำให้ SPA พังจริง 1 ครั้งแล้วเห็น stack ใน SigNoz · ทำให้หน้า login พังแล้วเห็นผ่านช่อง anonymous · god-mode มี span ตอน delete |

**เหตุผลที่ pilot เป็น Go ไม่ใช่ NestJS:** `micro-report` ไม่มี Loki ให้ถอด จึงแยก "เส้นทาง
เน็ตเวิร์กข้าม VM ใช้ได้ไหม" ออกจาก "การเปลี่ยน logger พังอะไรไหม" ได้สะอาด ถ้าเริ่มที่ NestJS
แล้ว log ไม่ขึ้น จะแยกไม่ออกว่าเพราะ NAT หรือเพราะ transport

ทุกเฟสต้องผ่าน `bunx tsc --noEmit` + `lint` ก่อน merge

---

## 11. Failure modes

| อาการ | สาเหตุที่น่าจะเป็น | จุดตรวจ |
|---|---|---|
| SDK start ผ่าน แต่ไม่มี span เลย | `startTelemetry()` รันหลัง `import` ที่ต้อง patch | ข้อ 6.1 — ต้องใช้ `--require` หรือไฟล์ side-effect |
| trace เบราว์เซอร์กับ backend แยกเส้นกัน | ลืม `propagateTraceHeaderCorsUrls` | ข้อ 8.4 |
| log ขึ้น แต่ไม่มี `trace_id` | winston transport ไม่ได้อ่าน active context | ต้องยิงระหว่าง request จริง ไม่ใช่ตอน bootstrap |
| test suite ค้างไม่ยอมจบ | OTLP exporter keep-alive timer (ปัญหาเดียวกับ LokiTransport เดิม) | ต้องยก jest guard ของ micro-business มาด้วย (ข้อ 6.2) |
| memory บวมช้า ๆ แล้ว service ตาย | exporter ยิงไม่ถึงแล้ว retry สะสม | ข้อ 3.3 — endpoint ไม่ตั้งต้องแปลว่าไม่ start ไม่ใช่ start แล้ว fail |
| ดิสก์เต็ม ClickHouse read-only | retention ไม่ได้ตั้ง หรือตั้งบนตัวเลข disk ที่เดาเอา | ข้อ 9.2 + เฟส 0 |
| log ช่วง restart หายทุกครั้ง | ไม่มี shutdown flush | ข้อ 7.2 |

---

## 12. นอกสโคป

- UAT / prod (เปิดทีหลังด้วยการเติม env var — ไม่ต้องแก้โค้ด)
- `carmen-wiki`, `carmen-inventory-mobile`
- OTel Collector relay (เหตุผลในข้อ 3.4)
- Alert / dashboard ใน SigNoz — spec นี้จบที่ "ข้อมูลเข้าไปครบและ query ได้"
- การไล่ให้ auto-instrumentation ทำงานเต็มรูปแบบบน Bun (ข้อ 8.6)
- Session replay หรือ RUM เต็มรูปแบบฝั่งเบราว์เซอร์
- แทนที่ `lib/analytics.ts` (คนละเรื่อง — ข้อ 8.5)

---

## 13. เรื่องที่ยังไม่รู้ ต้องยืนยันตอน implement

| เรื่อง | ทำไมสำคัญ | เช็คยังไง |
|---|---|---|
| private IP ของ VM SigNoz และ VM Carmen ยิงถึงไหม | ถ้าไม่ถึง ทั้ง design ต้องเปลี่ยนเส้นทาง | SSH เข้า VM Carmen แล้ว `curl` ไปที่ `:4318` |
| RAM ว่างจริงบน VM SigNoz | spec รอบก่อนตั้งงบ 2.6 GB บนสมมติฐานเครื่องแยก ซึ่งผิด | `free -m` |
| disk ว่างจริง | ตัวเลข retention ข้อ 9.2 ตั้งบนสมมติฐาน >= 20 GB | `df -h` |
| retention ถูกตั้งไปแล้วหรือยัง | README บอกว่า "ห้ามข้าม" แต่ยืนยันจากนอกไม่ได้ | ดูใน SigNoz UI |
| Prisma 7.9.1 ต้องเปิด preview `tracing` ไหม | กระทบว่าจะเห็น query span หรือไม่ | ลองเสียบใน `micro-notification` ก่อน |
| ใครควบคุม NAT / port forward | เฟส 0 ข้อ 1 ทำไม่ได้ถ้าเข้าไม่ถึง | ถามเจ้าของเครื่อง |
