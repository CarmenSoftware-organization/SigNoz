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
   (`limit_mib: 300`) และ**หั่นขนาด batch ของ collector ลง 10 เท่า**:
   `batch.send_batch_size` 50000 → 5000, `batch.send_batch_max_size` 55000 → 5500,
   `batch/meter.send_batch_size` 20000 → 2000, `batch/meter.send_batch_max_size` 25000 → 2500
   (คอนเทนเนอร์ `ingester` ถูกจำกัดไว้ที่ `mem_limit: 400m` — เอาค่า 50000 ของ upstream
   กลับมาเมื่อไหร่ ก็ OOM เมื่อนั้น)
6. pin image tag ทุกตัว (upstream ใช้ `latest` แม้ในไฟล์ที่ชื่อ `.lock`)
7. ทำ port และ bind address เป็นตัวแปรสำหรับช่อง env ของ Portainer
8. `signozspanmetrics/delta.dimensions_cache_size` 100000 → 10000
   cache นี้เก็บ latency histogram 17 bucket + counter ต่อชุด dimension ที่ไม่ซ้ำกัน
   มันโตตาม cardinality ของ span ไม่ใช่ตาม rate และ `memory_limiter` เอาคืนไม่ได้
   (memory_limiter แค่ปฏิเสธข้อมูลใหม่ ไม่ได้ปล่อยของที่ processor ถือไว้แล้ว)
   ค่า 100000 ของ upstream เป็นค่าสำหรับ production เต็มขนาด ไม่ใช่สำหรับคอนเทนเนอร์ 400m
9. ลดของที่เก็บซ้ำโดยไม่จำเป็นบน single node: keeper `snapshots_to_keep` 3 → 2,
   ClickHouse `logger.count` 10 → 3 และ `logger.size` 1000M → 100M

## วิธีอัปเดตตอนอัปเกรด SigNoz

```bash
# ดึงชุดใหม่ทับ แล้วดูว่า upstream เปลี่ยนอะไร
git diff reference/upstream/
```

ถ้า `config-0-0.yaml` หรือ `ingester.yaml` เปลี่ยน ต้องเอาความเปลี่ยนแปลงนั้น
มาใส่ใน `configs.content` ของ compose เราด้วยมือ พร้อมคงการดัดแปลงทั้ง 9 ข้อข้างบนไว้

ตัวเลขทุกตัวในข้อ 5, 8, 9 เป็นค่าที่ตั้งใจตั้ง ไม่ใช่ค่าที่หลงเหลือมา — เวลาอัปเกรดให้ไล่ทีละข้อ
อย่าก๊อป config ของ upstream ทับทั้งก้อน ไม่งั้นค่าพวกนี้จะกลับไปเป็นค่า production ของ upstream
เงียบๆ โดยไม่มีอะไรฟ้อง แล้วไปโผล่เป็น OOM ตอนมี traffic จริงแทน
