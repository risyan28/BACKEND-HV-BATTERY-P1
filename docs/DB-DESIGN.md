# Database Design — HEV Battery PIS (TMMIN 1 KRW)

> Last updated: 2026-03-12  
> DB: `DB_TMMIN1_KRW_PIS_HV_BATTERY` · SQL Server 2019 · port 1433

---

## Daftar Isi

1. [Overview Arsitektur](#1-overview-arsitektur)
2. [Master Tables](#2-master-tables)
3. [Runtime / Transaksional Tables](#3-runtime--transaksional-tables)
4. [History Tables](#4-history-tables)
5. [Data Flow per Order Type](#5-data-flow-per-order-type)
6. [Trigger Catalog](#6-trigger-catalog)
7. [Function & Stored Procedure](#7-function--stored-procedure)
8. [Cara Tambah Model / Type Baru](#8-cara-tambah-model--type-baru)
9. [Catatan Skema & Known Issues](#9-catatan-skema--known-issues)

---

## 1. Overview Arsitektur

```
┌──────────────────────────────────────────────────────────────────────────┐
│                         MASTER CONFIGURATION                             │
│                                                                          │
│  TB_M_PROD_MODEL          TB_M_PROD_ORDER_TYPE     TB_M_INIT_QRCODE      │
│  (FMODEL_BATTERY          (ORDER_TYPE              (QR config per        │
│   FTYPE_BATTERY)           IS_ACTIVE               ORDER_TYPE × MODEL)   │
│        │                       │                                         │
│        └───── trigger ─────────┘                                         │
│                    auto-insert/delete baris QRCODE                       │
│                                                                          │
│  TB_M_BATTERY_MAPPING                              TB_M_LABEL_CONSTANT   │
│  (FKATASHIKI × FTYPE × FMODEL × ORDER_TYPE)        (barcode constants)   │
└──────────────────────────────────────────────────────────────────────────┘
         │                                    │
         │ INSERT dari                         │ INSERT dari
         │ TB_R_RECEIVER_SUBSYSTEM             │ TB_H_PROD_PLAN_DETAIL
         ▼ (trigger Assy)                     ▼ (trigger CKD/Svc Part)
┌──────────────────────────────────────────────────────────────────────────┐
│                         RUNTIME / PLANNING                               │
│                                                                          │
│  TB_R_TARGET_PROD                                                        │
│  (FTYPE × FMODEL) — 1 baris per kombinasi                                │
│                                                                          │
│    FTYPE  FMODEL    ORDER_TYPE    FTARGET   Sumber terakhir              │
│    E      LI-688D   CKD           74        ← total akumulasi; ORDER_TYPE│
│                                           diset sesuai proses terakhir    │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
         │
         │ SP_REGENERATE_BATTERY_SEQUENCE
         ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                         SEQUENCE / BARCODE                               │
│                                                                          │
│  TB_R_SEQUENCE_BATTERY                                                   │
│  (1 row per unit fisik — FBARCODE adalah label yang diprint)             │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Master Tables

### `TB_M_PROD_MODEL`

Single source of truth untuk model battery yang diproduksi.

| Kolom          | Type         | Nullable | Keterangan                              |
| -------------- | ------------ | -------- | --------------------------------------- |
| FID            | int          | NOT NULL | PK, autoincrement                       |
| FMODEL_BATTERY | nvarchar(20) | YES      | Identifier model, ex: `LI-688D`         |
| FTYPE_BATTERY  | varchar(1)   | YES      | Type untuk barcode, ex: `E`             |
| IS_DEFAULT     | int          | NOT NULL | 1 = default model di UI                 |
| IS_ACTIVE      | int          | NOT NULL | 1 = aktif — trigger sync ke INIT_QRCODE |
| CREATED_AT     | datetime     | NOT NULL |                                         |
| UPDATED_AT     | datetime     | YES      |                                         |

**Data saat ini:**

```
FID  FMODEL_BATTERY  FTYPE_BATTERY  IS_DEFAULT  IS_ACTIVE
1    LI-688D         E              1           1
```

**Aturan penting:**

- `FMODEL_BATTERY` adalah key yang dipakai di semua tabel runtime (`TB_R_*`)
- `FTYPE_BATTERY` wajib diisi — dipakai oleh `SP_REGENERATE_BATTERY_SEQUENCE` untuk partisi barcode
- Set `IS_ACTIVE = 0` → trigger otomatis hapus baris di `TB_M_INIT_QRCODE`

---

### `TB_M_PROD_ORDER_TYPE`

Daftar order type produksi.

| Kolom      | Type         | Nullable | Keterangan                    |
| ---------- | ------------ | -------- | ----------------------------- |
| FID        | int          | NOT NULL | PK                            |
| ORDER_TYPE | nvarchar(50) | NOT NULL | `Assy`, `CKD`, `Service Part` |
| IS_ACTIVE  | int          | NOT NULL | 1 = aktif                     |
| SORT_ORDER | int          | NOT NULL | Urutan tampilan di UI         |
| CREATED_AT | datetime     | NOT NULL |                               |
| UPDATED_AT | datetime     | YES      |                               |

**Data saat ini:**

```
ORDER_TYPE    IS_ACTIVE  SORT_ORDER
Assy          0          1           ← nonaktif (tidak masuk plan web app)
CKD           1          2
Service Part  1          3
```

> `Assy` sengaja `IS_ACTIVE=0` → tidak masuk planning web app. Actuality Assy masuk dari `TB_R_RECEIVER_SUBSYSTEM`.

---

### `TB_M_INIT_QRCODE`

Konfigurasi QR code label per kombinasi `ORDER_TYPE × FMODEL_BATTERY`.

| Kolom                  | Type         | Nullable | Keterangan                     |
| ---------------------- | ------------ | -------- | ------------------------------ |
| FID                    | int          | NOT NULL | PK                             |
| ORDER_TYPE             | nvarchar(50) | YES      | Dari `TB_M_PROD_ORDER_TYPE`    |
| FMODEL_BATTERY         | varchar(20)  | YES      | Dari `TB_M_PROD_MODEL`         |
| NO_BATTERYPACK         | varchar(50)  | YES      | Part number, ex: `G9280-F7040` |
| BATTERY_PACK_NAME      | varchar(50)  | YES      | Nama battery pack              |
| BATTERY_IDENTIFICATION | varchar(10)  | YES      |                                |
| EMC_ID                 | varchar(50)  | YES      |                                |
| BATTERYPACK_ID         | varchar(50)  | YES      |                                |
| ENERGY_BATTERY         | varchar(10)  | YES      |                                |
| BATTERY_CATEGORY       | varchar(10)  | YES      |                                |
| NO_EPR                 | varchar(10)  | YES      |                                |
| URL                    | varchar(50)  | YES      | URL QR code                    |
| FTYPE_BATTERY          | varchar(10)  | YES      |                                |
| FMODEL_BATTERY         | varchar(20)  | YES      | ex: `LI-688D` (UPPER)          |

**Unique constraint:** `UQ_INIT_QRCODE_OT_FMODEL (ORDER_TYPE, FMODEL_BATTERY)`

**Data saat ini:**

```
FID  ORDER_TYPE    FMODEL_BATTERY  NO_BATTERYPACK  URL
1    CKD           LI-688D         G9280-F7040     https://bp.toyota/battery/
2    Service Part  LI-688D         NULL            NULL   ← perlu diisi manual
```

> Baris FID=2 (Service Part) auto-insert oleh trigger saat ORDER_TYPE aktif. Field selain FMODEL_BATTERY perlu diisi manual lewat UI/SQL karena bisa berbeda dari CKD.

---

### `TB_M_BATTERY_MAPPING`

Mapping katashiki (kode unit dari subsystem Assy) ke identitas battery.

| Kolom              | Type         | Nullable | Keterangan                           |
| ------------------ | ------------ | -------- | ------------------------------------ |
| FKATASHIKI         | varchar(15)  | NOT NULL | Kode unit dari ALC_DATA posisi 50–53 |
| FTYPE_BATTERY      | varchar(1)   | NOT NULL | ex: `E`                              |
| FMODEL_BATTERY     | varchar(20)  | NOT NULL | ex: `LI-688D`                        |
| FPACK_PART_BATTERY | varchar(5)   | computed | `GetPackPartByModel(FMODEL_BATTERY)` |
| ORDER_TYPE         | nvarchar(50) | YES      | Scope flow: saat ini selalu `'Assy'` |

**Data saat ini:**

```
FKATASHIKI  FTYPE  FMODEL   FPACK_PART  ORDER_TYPE
NYC2        E      LI-688D  F7040       Assy
```

> `FPACK_PART_BATTERY` adalah **computed column** — nilainya otomatis dari function `GetPackPartByModel`. Tidak perlu diisi manual.

---

### `TB_M_LABEL_CONSTANT`

Konstanta untuk pembentukan barcode.

| FKEY         | Contoh FVALUE | Dipakai di barcode posisi |
| ------------ | ------------- | ------------------------- |
| MANUFACTURER | `---`         | prefix                    |
| PROD_TYPE    | `PE`          | setelah manufacturer      |
| SPEC_NO      | `--`          | setelah type              |
| LINE_NO      | `0`           | setelah pack part         |
| ADDRESS      | `L`           | setelah line              |

---

### `TB_M_PROD_YEAR` & `TB_M_PROD_MONTH_DAY`

Encoding kode tahun/bulan/hari untuk barcode.

---

## 3. Runtime / Transaksional Tables

### `TB_R_TARGET_PROD`

Target dan actual produksi per kombinasi `FTYPE × FMODEL`. **Satu baris per kombinasi.**

| Kolom              | Type         | Nullable | Keterangan                                     |
| ------------------ | ------------ | -------- | ---------------------------------------------- |
| FID                | int          | NOT NULL | PK                                             |
| FTYPE_BATTERY      | varchar(20)  | YES      | ex: `E`                                        |
| FMODEL_BATTERY     | varchar(30)  | YES      | ex: `LI-688D`                                  |
| ORDER_TYPE         | nvarchar(50) | YES      | `Assy` / `CKD` / `Service Part`                |
| FPACK_PART_BATTERY | varchar(5)   | computed | `GetPackPartByModel(FMODEL_BATTERY)`           |
| FTARGET            | int          | YES      | Planning qty (CKD/SP) atau actual count (Assy) |
| FPROD_DATE         | date         | YES      | Tanggal produksi terakhir                      |
| FSEQ_K0            | varchar(3)   | YES      | Sequence K0 (Assy)                             |
| FBODY_NO_K0        | varchar(5)   | YES      | Body number K0 (Assy)                          |
| FID_RECEIVER       | varchar(50)  | YES      | ID unit terakhir dari subsystem (Assy)         |
| FALC_DATA          | varchar(200) | YES      | Raw ALC_DATA terakhir (Assy)                   |
| FDATETIME_MODIFIED | datetime     | YES      | Timestamp update terakhir                      |

**Unique key/index:** `UQ_TARGET_PROD_TYPE_MODEL (FTYPE_BATTERY, FMODEL_BATTERY)`

**Data saat ini:**

```
FTYPE  FMODEL    ORDER_TYPE    FPACK_PART  FTARGET  FPROD_DATE
E      LI-688D   CKD           F7040       74       2026-03-12  ← total akumulasi saat ini
```

**Cara data masuk:**

- `ORDER_TYPE = 'Assy'` → via trigger `TB_RECEIVER_SUBSYSTEM_AFTER_INSERT` (FTARGET++, ORDER_TYPE='Assy', field receiver diupdate)
- `ORDER_TYPE = 'CKD'` / `'Service Part'` → via trigger `TR_PLAN_DETAIL_SYNC_TARGET_PROD` saat `SEQ_GENERATED = 1` (FTARGET += DeltaGeneratedQty, ORDER_TYPE diset ke order type yang diproses)

---

### `TB_R_SEQUENCE_BATTERY`

Satu baris per **unit fisik battery** yang siap diproses/diprint.

| Kolom           | Type         | Nullable | Keterangan                                  |
| --------------- | ------------ | -------- | ------------------------------------------- |
| FID             | int          | NOT NULL | PK                                          |
| FID_ADJUST      | int          | YES      | Ref ke FID lain jika di-adjust              |
| FSEQ_NO         | int          | NOT NULL | Nomor urut dalam satu TYPE+MODEL+ORDER_TYPE |
| FTYPE_BATTERY   | varchar(1)   | NOT NULL |                                             |
| FMODEL_BATTERY  | varchar(20)  | NOT NULL |                                             |
| ORDER_TYPE      | nvarchar(50) | YES      | `Assy` / `CKD` / `Service Part`             |
| FSEQ_DATE       | date         | NOT NULL | Tanggal sequence                            |
| FSTATUS         | int          | YES      | `0`=pending, `2`=completed                  |
| FBARCODE        | varchar(100) | YES      | Barcode string lengkap                      |
| FSEQ_K0         | varchar(100) | YES      | Seq K0 dari subsystem                       |
| FBODY_NO_K0     | varchar(100) | YES      | Body No dari subsystem                      |
| FID_RECEIVER    | varchar(50)  | YES      | UUID dari subsystem                         |
| FALC_DATA       | varchar(200) | YES      | Raw data dari subsystem                     |
| FTIME_RECEIVED  | datetime     | YES      | Waktu diterima dari subsystem               |
| FTIME_PRINTED   | datetime     | YES      | Waktu label diprint                         |
| FTIME_COMPLETED | datetime     | YES      | Waktu selesai diproses                      |

**Barcode format** (diisi oleh `SP_REGENERATE_BATTERY_SEQUENCE`):

```
[MANUFACTURER][PROD_TYPE][FTYPE_BATTERY][SPEC_NO][FPACK_PART_BATTERY][LINE_NO][ADDRESS][YEAR_CODE][MONTH_CODE][DAY_CODE][0000001..N]
Contoh: ---PE--252R31DG1K0000001
```

---

### `TB_R_RECEIVER_SUBSYSTEM`

Data masuk dari subsystem eksternal (antara lain sistem Assy).

| Kolom                   | Type         | Keterangan                              |
| ----------------------- | ------------ | --------------------------------------- |
| ID_RECEIVER             | varchar(50)  | UUID unit                               |
| BC_STS / PR_STS         | char(2)      | Status barcode/print                    |
| SENT_TO / RECEIVED_FROM | varchar(50)  | Routing info                            |
| ALC_DATA                | varchar(255) | **Raw data unit** — parsed oleh trigger |
| READ_FLG                | varchar(1)   | Flag sudah dibaca                       |
| CREATED_DT              | datetime     | Timestamp insert                        |

**ALC_DATA anatomy (Assy):**

```
Posisi  Len  Field
1–3     3    FSEQ_K0      → masuk TB_R_TARGET_PROD.FSEQ_K0
4–6     3    (reserved)
7–11    5    FBODY_NO_K0  → masuk TB_R_TARGET_PROD.FBODY_NO_K0
...
50–53   4    FKATASHIKI   → join ke TB_M_BATTERY_MAPPING untuk identifikasi model
```

---

### `TB_R_RFID_COMMAND`

Command READ/WRITE ke RFID reader per station.

| Kolom        | Keterangan                     |
| ------------ | ------------------------------ |
| STATION_NAME | `UNLOADING`, `MAN_ASSY_1`, dll |
| COMMAND      | `READ` atau `WRITE`            |
| FVALUE       | Status command                 |

---

### `TB_R_PRINT_LABEL`

State label QR yang sedang/sudah diprint.

| Kolom              | Keterangan        |
| ------------------ | ----------------- |
| FPRINT_QRCODE      | QR content string |
| FMODEL_BATTERY     | Model terkait     |
| FDATETIME_MODIFIED | Timestamp         |

---

## 4. History Tables

### `TB_H_PROD_PLAN` & `TB_H_PROD_PLAN_DETAIL`

Planning produksi harian dari web app.

```
TB_H_PROD_PLAN
  FID, PLAN_DATE, SHIFT, IS_LOCKED
    └── TB_H_PROD_PLAN_DETAIL
          FID, FID_PLAN, MODEL_NAME, ORDER_TYPE, QTY_PLAN,
          SEQ_GENERATED, SEQ_GENERATED_AT
```

> `MODEL_NAME` di tabel ini menggunakan format mixed-case (`Li-688D`) — berbeda dari `FMODEL_BATTERY` uppercase (`LI-688D`). Join ke `TB_M_PROD_MODEL` menggunakan `UPPER()`.

**Trigger:** Saat baris `TB_H_PROD_PLAN_DETAIL` untuk `ORDER_TYPE ≠ 'Assy'` di-mark `SEQ_GENERATED = 1`, trigger `TR_PLAN_DETAIL_SYNC_TARGET_PROD` otomatis sync delta `QTY_PLAN` ke `TB_R_TARGET_PROD`.

---

### `TB_H_PRINT_LOG`

Log setiap print event.

### `TB_H_TRACEABILITY_INSPECTION_MACHINE`

Data inspeksi mesin per battery pack (cell voltages, relay, insulation, dll — 36+ kolom).

### `TB_H_TRACEABILITY_MODULE_INSPECTION`

Data inspeksi modul (Fr/Rr stack).

### `TB_H_POS_FINAL_JUDGEMENT`

Penilaian akhir POS per pack: `LIFETIME_MODULE1`, `LIFETIME_MODULE2`, `OVERALL_JUDGEMENT`.

### `TB_H_POS_UNLOADING`

Data unloading dari POS.

### `TB_H_ANDON_LOG` & `TB_H_ANDON_STATUS` & `TB_H_DOWNTIME_LOG`

History andon dan downtime per station per shift.

---

## 5. Data Flow per Order Type

### Assy (actual dari subsystem)

```
Subsystem Assy
   │
   │ INSERT ke TB_R_RECEIVER_SUBSYSTEM
   ▼
TB_RECEIVER_SUBSYSTEM_AFTER_INSERT (trigger)
   │
   ├─ ALC_DATA[50:53] → lookup FKATASHIKI di TB_M_BATTERY_MAPPING
   │                        (WHERE ORDER_TYPE = 'Assy')
   │
   ├─ Auto-INSERT baris baru di TB_R_TARGET_PROD
   │  jika (FTYPE, FMODEL) belum ada
   │
   └─ UPDATE TB_R_TARGET_PROD SET FTARGET = FTARGET + 1
      + FSEQ_K0, FBODY_NO_K0, FID_RECEIVER, FALC_DATA, FPROD_DATE
```

### CKD & Service Part (dari planning web app)

```
Web App — input QTY_PLAN
   │
   │ UPSERT ke TB_H_PROD_PLAN_DETAIL (default: SEQ_GENERATED=0)
   │ lalu klik generate => SEQ_GENERATED=1
   ▼
TR_PLAN_DETAIL_SYNC_TARGET_PROD (trigger)
   │
   ├─ Hanya proses row dengan SEQ_GENERATED=1
   │
   ├─ JOIN TB_M_PROD_MODEL ON UPPER(FMODEL_BATTERY) = UPPER(MODEL_NAME)
   │  → dapat FTYPE_BATTERY
   │
   ├─ Auto-INSERT baris baru di TB_R_TARGET_PROD
   │  jika (FTYPE, FMODEL) belum ada
   │
   └─ UPDATE TB_R_TARGET_PROD SET FTARGET = FTARGET + DeltaGeneratedQty
      + ORDER_TYPE = ORDER_TYPE dari plan yang sedang diproses
      ← DeltaGeneratedQty = QTY_PLAN_baru - QTY_PLAN_terakhir_yang_sudah_generated
      ← Contoh CKD: 0->1, QTY=100 => +100 (seq 1..100)
      ← Contoh Service Part: 0->1, QTY=60 => +60 (seq lanjut 101..160)
```

> **Multi-shift:** Tiap shift punya baris terpisah di `TB_H_PROD_PLAN_DETAIL` (via `FID_PLAN` yang beda shift). Trigger akumulasi ke `FTARGET` — sehingga sequence di `SEQUENCE_BATTERY` terus berlanjut antar shift.

### Sequence Generation — Global Continuous per FTYPE + FMODEL

Sequence dikelola oleh trigger `TB_R_TARGET_PROD_AFTER_UPDATE` (dipanggil otomatis tiap kali `TB_R_TARGET_PROD` diupdate):

```
TB_R_TARGET_PROD (FTARGET berubah)
   │
   │ AFTER UPDATE trigger
   ▼
TB_R_SEQUENCE_BATTERY (1 row per unit)
   - FSEQ_NO  : GLOBAL, tidak reset per hari / ORDER_TYPE
                 nerusin dari MAX(FSEQ_NO) per FTYPE+FMODEL
   - FBARCODE : MANUFACTURER + PROD_TYPE + FTYPE + SPEC_NO
                + FPACK_PART + LINE_NO + ADDRESS
                + YEAR_CODE + MONTH_CODE + DAY_CODE     ← tanggal saat plan di-set
                + 7-digit FSEQ_NO
   - ORDER_TYPE: 'CKD' | 'Service Part' | 'Assy'
```

**Aturan trigger:**

| Delta FTARGET | Aksi                                                             |
| ------------- | ---------------------------------------------------------------- |
| `new > old`   | INSERT sejumlah `Delta` baris baru, FSEQ_NO lanjut dari MAX+1    |
| `new < old`   | DELETE sejumlah `Delta` baris FSTATUS=0 tertinggi per ORDER_TYPE |
| `new = old`   | No-op                                                            |

**Skenario:**

- CKD plan set ke 100 → generate seq 1..100 (misal)
- Assy unit ke-1 masuk → generate seq 101
- CKD plan naik ke 150 → generate seq 102..151 (CKD lanjut, Assy sudah pakai 101)
- CKD plan turun ke 140 → delete 10 baris CKD FSTATUS=0 teratas

**Catatan:** `SP_REGENERATE_BATTERY_SEQUENCE` masih ada untuk koreksi barcode jika data master (label constant/tahun/bulan) berubah, bukan untuk generate sequence normal.

---

## 6. Trigger Catalog

| Trigger                              | On Table                  | Event                | Fungsi                                                                                           |
| ------------------------------------ | ------------------------- | -------------------- | ------------------------------------------------------------------------------------------------ |
| `TB_RECEIVER_SUBSYSTEM_AFTER_INSERT` | `TB_R_RECEIVER_SUBSYSTEM` | AFTER INSERT         | Parse ALC_DATA → update Assy actual di TARGET_PROD; update READ_FLG di SUBSYSTEM_HV_P1           |
| `TR_PLAN_DETAIL_SYNC_TARGET_PROD`    | `TB_H_PROD_PLAN_DETAIL`   | AFTER INSERT, UPDATE | Sync saat `SEQ_GENERATED=1`: FTARGET += DeltaGeneratedQty (berdasarkan QTY yang sudah generated) |
| `TB_R_TARGET_PROD_AFTER_UPDATE`      | `TB_R_TARGET_PROD`        | AFTER UPDATE         | Global continuous sequence: delta>0→INSERT baris ke SEQUENCE_BATTERY; delta<0→DELETE kelebihan   |
| `TR_ORDER_TYPE_SYNC_QRCODE`          | `TB_M_PROD_ORDER_TYPE`    | AFTER INSERT, UPDATE | IS_ACTIVE=1 → insert baris ke INIT_QRCODE (cross join model aktif); IS_ACTIVE=0 → delete         |
| `TR_PROD_MODEL_SYNC_QRCODE`          | `TB_M_PROD_MODEL`         | AFTER INSERT, UPDATE | IS_ACTIVE=1 → insert baris ke INIT_QRCODE (cross join order type aktif); IS_ACTIVE=0 → delete    |
| `TB_M_BATTERY_MAPPING_AFTER_INSERT`  | `TB_M_BATTERY_MAPPING`    | AFTER INSERT         | Auto-insert baris ke TARGET_PROD saat mapping baru ditambah                                      |
| `TB_H_ANDON_STATUS_AFTER_UPDATE`     | `TB_H_ANDON_STATUS`       | AFTER UPDATE         | Akumulasi downtime ke H_DOWNTIME_LOG + R_DOWNTIME_LOG                                            |
| `TB_R_ANDON_STATUS_AFTER_UPDATE`     | `TB_R_ANDON_STATUS`       | AFTER UPDATE         | FVALUE 0→1: start andon; 1→0: end andon ke H_ANDON_STATUS                                        |
| `TB_R_PRINT_LABEL_AFTER_DELETE`      | `TB_R_PRINT_LABEL`        | AFTER DELETE         | (cek definisi — belum terdokumentasi)                                                            |

---

## 7. Function & Stored Procedure

### `GetPackPartByModel(@Model VARCHAR(50)) → VARCHAR(5)`

Computed column helper — dipanggil otomatis oleh `FPACK_PART_BATTERY` di:

- `TB_M_BATTERY_MAPPING`
- `TB_R_TARGET_PROD`

```sql
SELECT TOP 1 RIGHT(NO_BATTERYPACK, 5)
FROM TB_M_INIT_QRCODE
WHERE FMODEL_BATTERY = @Model
  AND NO_BATTERYPACK IS NOT NULL
ORDER BY FID ASC
```

> `TOP 1 + NOT NULL filter` penting — INIT_QRCODE kini punya banyak baris per model (satu per ORDER_TYPE). Tanpa ini, hasil bisa NULL jika row kosong terbaca duluan.

---

### `SP_REGENERATE_BATTERY_SEQUENCE`

Generate ulang sequence barcode dari `TB_R_SEQUENCE_BATTERY`.

**Alur:**

1. Ambil semua row `FSTATUS=0` (pending)
2. Re-number `FSEQ_NO` mulai dari 1, partisi per `(FTYPE_BATTERY, FMODEL_BATTERY)`
3. Rebuild `FBARCODE` dari konstanta + kode tanggal + seq
4. Update `FTARGET` di `TB_R_TARGET_PROD` dengan `MAX(FSEQ_NO)` per TYPE+MODEL

---

### `sp_RefreshBatteryTraceabilityView`

Recreate view `VW_TRACEABILITY_PIS` secara dinamis — auto-detect kolom dari tabel inspeksi (karena kolom bisa berubah).

---

## 8. Cara Tambah Model / Type Baru

### Skenario A: Model baru, Type baru

Misal: model `LI-999D`, type `F`

```sql
-- 1. Daftarkan model
INSERT INTO TB_M_PROD_MODEL (FMODEL_BATTERY, FTYPE_BATTERY, IS_DEFAULT, IS_ACTIVE)
VALUES ('LI-999D', 'F', 0, 1);
-- ↑ trigger TR_PROD_MODEL_SYNC_QRCODE otomatis insert baris ke INIT_QRCODE
--   untuk setiap ORDER_TYPE yang IS_ACTIVE=1

-- 2. Daftarkan katashiki untuk Assy
INSERT INTO TB_M_BATTERY_MAPPING (FKATASHIKI, FTYPE_BATTERY, FMODEL_BATTERY, ORDER_TYPE)
VALUES ('XYZ9', 'F', 'LI-999D', 'Assy');
-- ↑ trigger TB_M_BATTERY_MAPPING_AFTER_INSERT otomatis insert baris ke TARGET_PROD

-- 3. Isi data INIT_QRCODE yang auto-insert (isi field yang kosong)
UPDATE TB_M_INIT_QRCODE
SET NO_BATTERYPACK = 'G9280-XXXXX', URL = 'https://bp.toyota/battery/', ...
WHERE FMODEL_BATTERY = 'LI-999D';
```

**Tidak perlu ubah trigger apapun.**

### Skenario B: FMODEL sama, FTYPE berbeda

Kedua kolom di `TB_M_BATTERY_MAPPING` dan `TB_R_TARGET_PROD` adalah composite key → otomatis terpisah. `SP_REGENERATE` juga partisi per `(FTYPE, FMODEL)` → sequence terpisah.

### Skenario C: Tambah ORDER_TYPE baru

```sql
-- 1. Daftarkan order type
INSERT INTO TB_M_PROD_ORDER_TYPE (ORDER_TYPE, IS_ACTIVE, SORT_ORDER)
VALUES ('Export', 1, 4);
-- ↑ trigger TR_ORDER_TYPE_SYNC_QRCODE otomatis insert baris ke INIT_QRCODE
--   untuk setiap MODEL yang IS_ACTIVE=1

-- 2. Tentukan apakah sumber datanya dari subsystem atau planning
--    Jika dari subsystem: tambah entry di TB_M_BATTERY_MAPPING dengan ORDER_TYPE='Export'
--    Jika dari planning: sudah otomatis via TR_PLAN_DETAIL_SYNC_TARGET_PROD
```

---

## 9. Catatan Skema & Known Issues

### ⚠️ Case Mismatch: MODEL_NAME vs FMODEL_BATTERY

`TB_H_PROD_PLAN_DETAIL.MODEL_NAME` menyimpan `Li-688D` (mixed case), sedangkan `TB_M_PROD_MODEL.FMODEL_BATTERY` = `LI-688D` (UPPER). Join di trigger menggunakan `UPPER()`.

**Rekomendasi:** Normalkan case saat input di web app (simpan sebagai UPPER ke plan detail) agar tidak perlu `UPPER()` di trigger.

---

### ⚠️ INIT_QRCODE: Field kosong pada auto-inserted rows

Saat ORDER_TYPE baru diaktifkan, trigger insert row kosong ke `TB_M_INIT_QRCODE`. Field seperti `NO_BATTERYPACK`, `URL`, `BATTERY_PACK_NAME` harus diisi manual.

**Rekomendasi:** Tambah alert/indicator di web app untuk row INIT_QRCODE yang masih kosong.

---

### ℹ️ FPACK_PART_BATTERY adalah computed column

Kolom ini **tidak bisa di-INSERT/UPDATE langsung** — nilainya otomatis dari `GetPackPartByModel()`. Untuk mengubah nilainya, ubah `NO_BATTERYPACK` di `TB_M_INIT_QRCODE`.

---

### ℹ️ Assy IS_ACTIVE = 0 di PROD_ORDER_TYPE

Ini disengaja. Assy tidak masuk UI planning web app karena actual-nya dari subsystem. Tetap masuk `TB_R_TARGET_PROD` via trigger receiver.

---

### ℹ️ SP_REGENERATE: partisi hanya per FTYPE + FMODEL

Saat ini `SP_REGENERATE_BATTERY_SEQUENCE` belum partisi per `ORDER_TYPE`. Jika ke depan CKD dan Service Part perlu barcode sequence terpisah, SP perlu diupdate dengan tambahan `ORDER_TYPE` di `PARTITION BY`.
