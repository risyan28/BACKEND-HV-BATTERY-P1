# Traceability API - Setup Guide

## 📁 Files Created

### 1. Controller
`src/controllers/traceability.controller.ts`
- Handles HTTP requests untuk endpoint traceability
- Validasi parameter `from` dan `to` (YYYY-MM-DD format)
- Error handling yang consistent

### 2. Service  
`src/services/traceability.service.ts`
- Business logic untuk query `VW_TRACEABILITY_PIS`
- Filter berdasarkan `PROD_DATE_PrintLog` (from-to range)
- Format datetime/date output

### 3. Routes
`src/routes/traceability.routes.ts`
- Define endpoint `/api/traceability/search`
- Method: GET dengan query params

### 4. App Registration
`src/app.ts`
- Routes sudah di-register di Express app

---

## 🗄️ Prisma Schema untuk VIEW

### Cara Handle VIEW di Prisma:

Karena `VW_TRACEABILITY_PIS` adalah **VIEW** dengan struktur **dinamis** (kolom pivot tightening bisa berubah), ada 2 opsi:

#### **Opsi 1: Gunakan `@@ignore` (Sudah diterapkan)** ✅

```prisma
model VW_TRACEABILITY_PIS {
  PACK_ID   String @id @db.VarChar(50)
  // ... field definitions ...
  
  @@map("VW_TRACEABILITY_PIS")
  @@ignore  // Tidak generate Prisma Client, pakai raw query
}
```

**Keuntungan:**
- View tetap terdokumentasi di schema
- Tidak error saat `prisma generate` atau `prisma db pull`
- Pakai `$queryRawUnsafe` untuk query (sudah diimplementasi di service)

#### **Opsi 2: Tanpa model, pure raw query**

Hapus model `VW_TRACEABILITY_PIS` dari schema, langsung pakai raw query aja.

---

## 🚀 Usage

### 1. Generate Prisma Client (Opsional)
```bash
npx prisma generate
```

### 2. Jalankan Stored Procedure (sekali atau saat ada perubahan)
```sql
EXEC sp_RefreshBatteryTraceabilityView;
```

### 3. Test API Endpoint
```bash
GET /api/traceability/search?from=2024-01-01&to=2024-01-31
```

**Response:**
```json
[
  {
    "PACK_ID": "ABC123",
    "MODULE_1": "M001",
    "MODULE_2": "M002",
    "UNLOADING_TIME": "2024-01-15 10:30:00.000",
    "PROD_DATE_PrintLog": "2024-01-15",
    "MANUAL WORK 3_SEQ1_TorqueMeasured": 45.5,
    "MANUAL WORK 3_SEQ1_ResultEvaluation": "OK",
    // ... all dynamic columns ...
  }
]
```

---

## 📝 Notes

### Tentang Dynamic Columns (Tightening Pivot)

View ini punya kolom dinamis yang di-generate oleh stored procedure:
- Format: `{StationName}_SEQ{N}_{Field}`
- Contoh: `MANUAL WORK 3_SEQ6_TorqueMeasured`

Karena struktur dinamis, **tidak bisa full type-safe** di TypeScript. Solusinya:

1. **Define interface manual** di service/controller (jika struktur stabil)
2. **Gunakan `any[]` atau `Record<string, any>`** (lebih fleksibel)
3. **Frontend parse column names** untuk extract station/sequence info

### Refresh View

Kalau ada perubahan di tightening structure (station baru, sequence baru):
```sql
EXEC sp_RefreshBatteryTraceabilityView;
```

View akan auto-rebuild dengan kolom terbaru.

---

## 🔧 Customization

### Ubah Filter Column
Kalau mau filter pakai kolom lain (bukan `PROD_DATE_PrintLog`), edit di service:

```typescript
// src/services/traceability.service.ts
const result = await prisma.$queryRawUnsafe<any[]>(`
  SELECT *
  FROM VW_TRACEABILITY_PIS
  WHERE CAST(UNLOADING_TIME AS DATE) BETWEEN @p1 AND @p2  -- Ganti kolom
  ORDER BY UNLOADING_TIME DESC
`, from, to)
```

### Additional Filters
Tambah query params (misal: `PACK_ID`, `JUDGEMENT_VALUE`):

```typescript
// controller
const { from, to, packId, judgement } = req.query

// service
WHERE CAST(PROD_DATE_PrintLog AS DATE) BETWEEN @p1 AND @p2
  AND (@p3 IS NULL OR PACK_ID LIKE '%' + @p3 + '%')
  AND (@p4 IS NULL OR JUDGEMENT_VALUE = @p4)
`, from, to, packId || null, judgement || null)
```

---

## ✅ Checklist

- [x] Controller created
- [x] Service created  
- [x] Routes created
- [x] Routes registered in app.ts
- [x] Prisma schema updated (with @@ignore)
- [ ] Run stored procedure to create view
- [ ] Test endpoint

**Endpoint Ready:** `GET /api/traceability/search?from=YYYY-MM-DD&to=YYYY-MM-DD`
