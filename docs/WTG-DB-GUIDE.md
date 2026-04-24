# DB_TMMIN1_KRW_WTG_HV_BATTERY — Dokumentasi

**Server:** `192.168.250.2:1433`  
**Database:** `DB_TMMIN1_KRW_WTG_HV_BATTERY`  
**Install script:** [`sql/wtg-db-install.sql`](../sql/wtg-db-install.sql)  
**Dibuat:** 2026-04-15

---

## Arsitektur

```
TB_SHIFT_DEFINITION  ──┐
                        ├── V_LINE_WT_A  ──→  V_LINE_WT_B  ──→  V_WORK_STATUS
TB_BREAK_SLOT        ──┘                           │
                                                   │ (LEFT JOIN)
TB_OVERTIME_SESSION  ──────────────────────────────┘

TB_WT_STATUS         ←── SP_WTG_DB (dipanggil setiap detik via SQL Agent job)
```

---

## Install / Reinstall

### Fresh DB (belum ada database-nya)

```bash
# 1. Buat database dulu
sqlcmd -S 192.168.250.2,1433 -U sa -P aas -No -Q "
IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name='DB_TMMIN1_KRW_WTG_HV_BATTERY')
    CREATE DATABASE [DB_TMMIN1_KRW_WTG_HV_BATTERY];"

# 2. Jalankan install script
sqlcmd -S 192.168.250.2,1433 -U sa -P aas -d DB_TMMIN1_KRW_WTG_HV_BATTERY -No -i "sql/wtg-db-install.sql"
```

### Reinstall (sudah ada, update objects saja)

```bash
# Script idempotent — aman dijalankan ulang
sqlcmd -S 192.168.250.2,1433 -U sa -P aas -d DB_TMMIN1_KRW_WTG_HV_BATTERY -No -i "sql/wtg-db-install.sql"
```

---

## Tabel

### `TB_SHIFT_DEFINITION` — Master jadwal shift

| Kolom             | Tipe         | Keterangan                   |
| ----------------- | ------------ | ---------------------------- |
| `SHIFT_ID`        | INT IDENTITY | PK                           |
| `LINENAME`        | VARCHAR(30)  | Nama line produksi           |
| `SHIFT_NO`        | TINYINT      | Nomor shift (1, 2, 3…)       |
| `SHIFT_LABEL`     | VARCHAR(20)  | Label shift ('Day', 'Night') |
| `WT_START`        | TIME(0)      | Jam mulai kerja              |
| `WT_END`          | TIME(0)      | Jam selesai kerja            |
| `IS_FRIDAY_SCHED` | BIT          | 1 = pakai jadwal Jumat       |
| `FWT_START`       | TIME(0)      | Jam mulai kerja hari Jumat   |
| `FWT_END`         | TIME(0)      | Jam selesai kerja hari Jumat |
| `IS_ACTIVE`       | BIT          | 1 = aktif                    |

### `TB_BREAK_SLOT` — Jam break per shift (fleksibel)

| Kolom             | Tipe         | Keterangan                   |
| ----------------- | ------------ | ---------------------------- |
| `BREAK_ID`        | INT IDENTITY | PK                           |
| `SHIFT_ID`        | INT          | FK → TB_SHIFT_DEFINITION     |
| `BREAK_SEQ`       | TINYINT      | Urutan break (1, 2, 3…)      |
| `BREAK_LABEL`     | VARCHAR(30)  | 'Lunch', 'Rest 1', …         |
| `BREAK_START`     | TIME(0)      | Jam mulai break              |
| `BREAK_END`       | TIME(0)      | Jam selesai break            |
| `IS_FRIDAY_BREAK` | BIT          | 1 = hanya berlaku hari Jumat |
| `IS_ACTIVE`       | BIT          | 1 = aktif                    |

### `TB_OVERTIME_SESSION` — Sesi overtime

| Kolom        | Tipe         | Keterangan                           |
| ------------ | ------------ | ------------------------------------ |
| `OT_ID`      | INT IDENTITY | PK                                   |
| `LINENAME`   | VARCHAR(30)  | Nama line                            |
| `SHIFT_ID`   | INT          | FK → TB_SHIFT_DEFINITION             |
| `OT_DATE`    | DATE         | Tanggal shift                        |
| `OT_START`   | DATETIME     | Waktu OT dimulai                     |
| `OT_END`     | DATETIME     | Waktu OT selesai (NULL = masih open) |
| `OT_SECONDS` | INT          | Akumulasi detik OT                   |
| `OT_REASON`  | VARCHAR(100) | Alasan overtime                      |

### `TB_WT_STATUS` — Counter status real-time

| `FREG_NAME`  | Isi `FREG_VALUE`  | Keterangan                                            |
| ------------ | ----------------- | ----------------------------------------------------- |
| `WT`         | integer (detik)   | Total detik kerja berjalan                            |
| `SHIFT`      | 1 / 2             | Shift aktif saat ini                                  |
| `LAST SHIFT` | 1 / 2             | Shift terakhir yang berjalan                          |
| `INFO`       | integer (bitmask) | bit0-1=shift, bit2=working, bit3=break, bit4=overtime |
| `DATE SHIFT` | YYYY-MM-DD        | Tanggal logis shift                                   |
| `DATE`       | YYYY-MM-DD        | Tanggal kalender                                      |
| `DATE NOW`   | YYYY-MM-DD        | Tanggal saat ini (update tiap 2 detik)                |

### `TB_WT_LOG` — Audit log (opsional)

Isi dari aplikasi sesuai kebutuhan. Struktur: `LINENAME`, `LOG_TS`, `SHIFT_NO`, `IS_WORKING`, `IS_BREAK`, `IS_OVERTIME`, `WT_SECONDS_SNAP`.

---

## Views

### `V_WORK_STATUS` — Dashboard utama ⭐

Query ini yang dibaca frontend / SCADA:

```sql
SELECT * FROM V_WORK_STATUS
```

| Kolom         | Keterangan                            |
| ------------- | ------------------------------------- |
| `LINENAME`    | Nama line                             |
| `SHIFT_LABEL` | 'Day' / 'Night'                       |
| `FNOW`        | Waktu server saat ini                 |
| `WORK_MODE`   | **WORKING / BREAK / OVERTIME / IDLE** |
| `WT_SECONDS`  | Total detik kerja berjalan            |
| `IS_BREAK`    | 1 = sedang break                      |
| `IS_OVERTIME` | 1 = sedang overtime                   |
| `OT_SECONDS`  | Detik overtime berjalan               |
| `SHIFT_DATE`  | Tanggal logis shift                   |
| `WT_START_DT` | DATETIME mulai shift                  |
| `WT_END_DT`   | DATETIME selesai shift                |

> Hanya menampilkan row yang `WORKING`, `BREAK`, atau `OVERTIME`. Saat `IDLE` (di luar jam kerja) tidak ada row.

### `V_LINE_WT_B` — Detail per shift

```sql
SELECT * FROM V_LINE_WT_B WHERE LINENAME = 'ADAPTIVE'
```

Menampilkan semua shift (termasuk yang tidak aktif), dengan flag `WT_TIME`, `IS_BREAK`, `FWT_TIME`, `FBREAK`, `IS_OVERTIME`.

### `V_LINE_WT_A` — Resolved datetime windows

View internal — menghitung `WT_START_DT` / `WT_END_DT` dengan date arithmetic yang benar untuk night shift midnight-crossing.

---

## Stored Procedures

### `SP_WTG_DB` — 1-second ticker

Dipanggil otomatis oleh SQL Agent job setiap detik. Bisa juga dipanggil manual untuk test:

```sql
EXEC SP_WTG_DB @VLINE = 'ADAPTIVE'
```

**Logic:**

- Cek apakah saat ini dalam jam kerja → increment `WT` counter
- Saat break → pause counting (counter tidak naik)
- Saat OT session open → increment `OT_SECONDS` juga
- Reset counter otomatis tiap pergantian shift (07:05 & 19:55)

### `SP_WTG_OVERTIME_OPEN` — Buka sesi overtime

```sql
EXEC SP_WTG_OVERTIME_OPEN
    @VLINE  = 'ADAPTIVE',          -- nama line
    @REASON = 'Target belum capai' -- alasan (opsional)
```

- Hanya bisa buka 1 sesi OT per line per hari
- Otomatis ambil shift terakhir dari `TB_WT_STATUS.LAST SHIFT`

### `SP_WTG_OVERTIME_CLOSE` — Tutup sesi overtime

```sql
EXEC SP_WTG_OVERTIME_CLOSE @VLINE = 'ADAPTIVE'
```

Output langsung:

```
OT_ID  LINENAME  OT_START              OT_END                OT_SECONDS  OT_DURATION_HMS
1      ADAPTIVE  2026-04-15 20:00:05   2026-04-15 21:23:45   5020        01:23:40
```

---

## SQL Agent Job

**Nama job:** `WTG_DB_BATTERY_TICKER`  
**Schedule:** setiap 1 menit (loop 60x `WAITFOR DELAY '00:00:01'` di dalam step)

Cek status job:

```sql
SELECT j.name, j.enabled,
       h.run_status,  -- 1=Success, 0=Failed
       LEFT(h.message, 200) AS last_message
FROM msdb.dbo.sysjobs j
JOIN msdb.dbo.sysjobhistory h ON h.job_id = j.job_id
WHERE j.name = 'WTG_DB_BATTERY_TICKER'
ORDER BY h.instance_id DESC
```

Restart job manual:

```sql
EXEC msdb.dbo.sp_start_job @job_name = 'WTG_DB_BATTERY_TICKER'
```

---

## Penggunaan Umum

### Baca status dari backend

```sql
-- Status semua line (polling tiap 1-2 detik)
SELECT LINENAME, WORK_MODE, WT_SECONDS, IS_BREAK, IS_OVERTIME, OT_SECONDS
FROM V_WORK_STATUS

-- Konversi detik ke HH:MM:SS
SELECT LINENAME, WORK_MODE,
       CONVERT(VARCHAR(8), DATEADD(SECOND, WT_SECONDS, 0), 108) AS WT_HH_MM_SS
FROM V_WORK_STATUS
```

### Tambah / ubah break

```sql
DECLARE @SID INT = (
    SELECT SHIFT_ID FROM TB_SHIFT_DEFINITION
    WHERE LINENAME='ADAPTIVE' AND SHIFT_NO=1
)

-- Tambah break baru
INSERT INTO TB_BREAK_SLOT (SHIFT_ID, BREAK_SEQ, BREAK_LABEL, BREAK_START, BREAK_END, IS_FRIDAY_BREAK)
VALUES (@SID, 5, 'Sholat Ashar', '15:30', '15:45', 0)

-- Nonaktifkan break tanpa hapus
UPDATE TB_BREAK_SLOT SET IS_ACTIVE = 0
WHERE SHIFT_ID = @SID AND BREAK_LABEL = 'Sholat Ashar'

-- Ubah jam break
UPDATE TB_BREAK_SLOT SET BREAK_START = '12:00', BREAK_END = '13:00'
WHERE SHIFT_ID = @SID AND BREAK_LABEL = 'Lunch'
```

### Tambah shift atau line baru

```sql
-- Tambah line / shift baru
INSERT INTO TB_SHIFT_DEFINITION (LINENAME, SHIFT_NO, SHIFT_LABEL, WT_START, WT_END, IS_ACTIVE)
VALUES ('LINE_B', 1, 'Day', '07:20', '20:00', 1)

-- Wajib: insert initial status rows
INSERT INTO TB_WT_STATUS (FDEV_NAME, FLINE, FREG_NAME, FREG_VALUE, FTR_TIME) VALUES
('WTG','LINE_B','SHIFT',     '0', GETDATE()),
('WTG','LINE_B','LAST SHIFT','0', GETDATE()),
('WTG','LINE_B','INFO',      '0', GETDATE()),
('WTG','LINE_B','WT',        '0', GETDATE()),
('WTG','LINE_B','DATE SHIFT',CONVERT(VARCHAR(10),GETDATE(),126), GETDATE()),
('WTG','LINE_B','DATE',      CONVERT(VARCHAR(10),GETDATE(),126), GETDATE()),
('WTG','LINE_B','DATE NOW',  CONVERT(VARCHAR(10),GETDATE(),126), GETDATE())

-- Update job step untuk memanggil LINE_B juga (tambahkan baris di command job)
-- EXEC dbo.SP_WTG_DB @VLINE = 'LINE_B';
```

### History overtime

```sql
-- Semua sesi OT line ADAPTIVE
SELECT OT_ID, OT_DATE, OT_START, OT_END, OT_SECONDS,
       CONVERT(VARCHAR(8), DATEADD(SECOND, OT_SECONDS, 0), 108) AS DURASI,
       OT_REASON
FROM TB_OVERTIME_SESSION
WHERE LINENAME = 'ADAPTIVE'
ORDER BY OT_DATE DESC

-- OT yang masih open
SELECT * FROM TB_OVERTIME_SESSION WHERE OT_END IS NULL
```

---

## VINFO Bitmask (untuk integrasi PLC/SCADA)

Nilai kolom `INFO` di `TB_WT_STATUS` adalah bitmask:

| Bit     | Nilai | Arti                   |
| ------- | ----- | ---------------------- |
| bit 0-1 | 1 / 2 | Nomor shift aktif      |
| bit 2   | +4    | Sedang dalam jam kerja |
| bit 3   | +8    | Sedang dalam jam break |
| bit 4   | +16   | Sedang overtime        |

Contoh: `INFO = 5` → `4 + 1` = working, shift 1

---

## Koneksi `.env`

```dotenv
WTG_SERVER=192.168.250.2
WTG_PORT=1433
WTG_DATABASE=DB_TMMIN1_KRW_WTG_HV_BATTERY
WTG_USER=sa
WTG_PASSWORD=aas
```
