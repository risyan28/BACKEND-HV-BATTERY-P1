# Change Tracking & WebSocket Setup

Dokumen ini menjelaskan cara mengaktifkan **SQL Server Change Tracking (CT)** di database, dan bagaimana fitur **WebSocket real-time** di backend ini menggunakannya.

---

## Daftar Isi

1. [Arsitektur](#arsitektur)
2. [Aktifkan Change Tracking di Database](#aktifkan-change-tracking-di-database)
3. [Buat Tabel CDC_CURSOR](#buat-tabel-cdc_cursor)
4. [Tabel yang Menggunakan Change Tracking](#tabel-yang-menggunakan-change-tracking)
5. [Cara Kerja WebSocket + CT di Backend](#cara-kerja-websocket--ct-di-backend)
6. [WebSocket Topics & Events](#websocket-topics--events)
7. [Alur Subscribe Client](#alur-subscribe-client)
8. [Troubleshooting](#troubleshooting)

---

## Arsitektur

```
SQL Server DB
  └── Change Tracking aktif per tabel
        └── CHANGETABLE(CHANGES ...) → deteksi ada perubahan
              ↓
Backend (Node.js)
  └── poller.ws.ts → cek CT setiap 2 detik
        └── Jika ada perubahan → ambil snapshot → emit ke Socket.IO room
              ↓
Frontend (Browser)
  └── Socket.IO client → subscribe topic → terima data real-time
```

---

## Aktifkan Change Tracking di Database

Jalankan script SQL berikut di SSMS pada database `DB_TMMIN1_KRW_PIS_HV_BATTERY`:

### Step 1 — Enable CT di level Database

```sql
ALTER DATABASE DB_TMMIN1_KRW_PIS_HV_BATTERY
SET CHANGE_TRACKING = ON
(CHANGE_RETENTION = 2 DAYS, AUTO_CLEANUP = ON);
```

> `CHANGE_RETENTION = 2 DAYS` → SQL Server menyimpan history CT selama 2 hari.  
> `AUTO_CLEANUP = ON` → SQL Server otomatis hapus CT lama.

### Step 2 — Enable CT per Tabel

```sql
-- Sequence Battery
ALTER TABLE dbo.TB_R_SEQUENCE_BATTERY
ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF);

-- Andon Global (summary)
ALTER TABLE dbo.TB_R_ANDON_GLOBAL
ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF);

-- Andon Status (andon calls)
ALTER TABLE dbo.TB_R_ANDON_STATUS
ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF);

-- POS Status
ALTER TABLE dbo.TB_R_POS_STATUS
ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF);

-- Downtime Log
ALTER TABLE dbo.TB_R_DOWNTIME_LOG
ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF);
```

> `TRACK_COLUMNS_UPDATED = OFF` → lebih ringan, cukup untuk deteksi "ada perubahan atau tidak".

### Step 3 — Verifikasi CT sudah aktif

```sql
-- Cek CT di level database
SELECT name, is_change_tracking_on = CASE WHEN db_id() IN (
    SELECT database_id FROM sys.change_tracking_databases
) THEN 1 ELSE 0 END
FROM sys.databases WHERE name = 'DB_TMMIN1_KRW_PIS_HV_BATTERY';

-- Cek CT per tabel
SELECT 
    OBJECT_NAME(object_id) AS TableName,
    is_track_columns_updated_on,
    min_valid_version,
    begin_version,
    cleanup_version
FROM sys.change_tracking_tables
ORDER BY TableName;
```

---

## Buat Tabel CDC_CURSOR

Backend menyimpan posisi CT terakhir di tabel `CDC_CURSOR` agar polling tidak memproses ulang perubahan yang sama setelah restart.

```sql
CREATE TABLE dbo.CDC_CURSOR (
    table_name  NVARCHAR(255) NOT NULL PRIMARY KEY,
    last_lsn    BIGINT        NOT NULL DEFAULT 0,
    updated_at  DATETIME      NOT NULL DEFAULT GETDATE()
);
```

Setelah tabel dibuat, backend akan otomatis mengisi baris untuk setiap tabel saat pertama kali ada subscriber.

---

## Tabel yang Menggunakan Change Tracking

| Tabel | WebSocket Topic | Event dikirim ke FE |
|-------|-----------------|---------------------|
| `TB_R_SEQUENCE_BATTERY` | `sequences` | `sequences:update` |
| `TB_R_ANDON_GLOBAL` | `summary` | `summary:update` |
| `TB_R_ANDON_STATUS` | `calls` | `calls:update` |
| `TB_R_POS_STATUS` | `processes` | `processes:update` |
| `TB_R_DOWNTIME_LOG` | `downtime` | `downtime:update` |

---

## Cara Kerja WebSocket + CT di Backend

### File utama: `src/ws/poller.ws.ts`

Flow per polling interval (default **2 detik**):

```
1. Baca last_lsn dari CDC_CURSOR untuk table ini
2. Jalankan: CHANGETABLE(CHANGES dbo.[TABLE_NAME], @lastVersion)
3. Jika ada rows → ada perubahan
   a. Ambil max SYS_CHANGE_VERSION → simpan ke CDC_CURSOR
   b. Panggil onChangeDetected() → invalidasi cache Redis/memory
   c. Jalankan pollingLogic() → ambil snapshot data terbaru
   d. io.to(room).emit(eventName, snapshot) → broadcast ke semua subscriber
4. Jika tidak ada rows → skip (tidak emit)
```

### Cache invalidation

Saat CT mendeteksi perubahan pada `TB_R_SEQUENCE_BATTERY`, cache di-invalidate sebelum broadcast:

```typescript
onChangeDetected: async () => {
  await cache.del('sequences:all')
}
```

Ini memastikan request HTTP `/api/sequences` setelah ada perubahan selalu dapat data terbaru.

---

## WebSocket Topics & Events

### `sequences` → `sequences:update`

Data sequence battery saat ini, antrian, selesai, dan parkir.

```json
{
  "current": { "FID": 1, "FSEQ_DATE": "2026-03-07", ... },
  "queue": [...],
  "completed": [...],
  "parked": [...]
}
```

### `summary` → `summary:update`

Summary produksi harian dari `TB_R_ANDON_GLOBAL`.

```json
{
  "Target": 100,
  "Plan": 95,
  "ActCkd": 87,
  "ActAssy": 85,
  "Eff": 87.0,
  "TaktTime": 180,
  "UpdatedAt": "2026-03-07T10:00:00"
}
```

### `calls` → `calls:update`

Andon calls yang sedang aktif.

```json
[
  { "station": "ST-01", "call_type": "QUALITY" },
  { "station": "ST-03", "call_type": "MATERIAL" }
]
```

### `processes` → `processes:update`

Status per proses/stasiun.

```json
[
  { "station": "ST-01", "status": "RUNNING", "source": "PLC" }
]
```

### `downtime` → `downtime:update`

Akumulasi downtime per stasiun.

```json
[
  { "station": "ST-01", "times": 3, "minutes": 15 }
]
```

---

## Alur Subscribe Client (Frontend)

```javascript
const socket = io('ws://localhost:4001', { transports: ['websocket'] })

// Subscribe ke topic
socket.emit('subscribe', 'sequences')

// Terima data real-time
socket.on('sequences:update', (data) => {
  console.log(data)
})

// Error handler
socket.on('sequences:update:error', (err) => {
  if (err.fatal) {
    // Polling berhenti, perlu refresh halaman
  }
})

// Manual force-refresh (tanpa tunggu polling interval)
socket.emit('sync', 'sequences')
```

---

## Troubleshooting

### Polling tidak jalan / tidak ada data masuk

1. Cek CT sudah aktif:
   ```sql
   SELECT * FROM sys.change_tracking_tables;
   ```
2. Cek `CDC_CURSOR` punya row untuk tabel yang bersangkutan:
   ```sql
   SELECT * FROM CDC_CURSOR;
   ```
3. Pastikan `CDC_CURSOR` table sudah dibuat (lihat bagian [Buat Tabel CDC_CURSOR](#buat-tabel-cdc_cursor)).

### Error: "Invalid object name 'CDC_CURSOR'"

Tabel `CDC_CURSOR` belum dibuat. Jalankan script di bagian [Buat Tabel CDC_CURSOR](#buat-tabel-cdc_cursor).

### Error: "Invalid object name 'CHANGETABLE'"

Change Tracking belum aktif di database atau tabel. Jalankan script di Step 1 dan Step 2.

### CT version terlalu lama / data tidak keluar

CT version di `CDC_CURSOR` mungkin sudah expired (lebih lama dari `CHANGE_RETENTION`). Reset cursor:

```sql
-- Reset semua cursor (backend akan polling dari versi current)
UPDATE CDC_CURSOR SET last_lsn = CHANGE_TRACKING_CURRENT_VERSION();
-- atau hapus semua dan biarkan backend isi ulang
DELETE FROM CDC_CURSOR;
```

### Polling berhenti sendiri

Backend berhenti polling jika gagal 3x berturut-turut (`MAX_RETRIES = 3`). FE akan menerima event `{fatal: true}`. Client perlu re-subscribe atau refresh halaman.

### Cek versi CT saat ini di database

```sql
SELECT CHANGE_TRACKING_CURRENT_VERSION() AS CurrentVersion;
SELECT CHANGE_TRACKING_MIN_VALID_VERSION(OBJECT_ID('TB_R_SEQUENCE_BATTERY')) AS MinValidVersion;
```

Jika `last_lsn` di `CDC_CURSOR` lebih kecil dari `MinValidVersion`, CT sudah expired → perlu reset cursor seperti di atas.
