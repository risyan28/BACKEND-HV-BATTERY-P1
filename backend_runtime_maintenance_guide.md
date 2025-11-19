# 📘 Backend Runtime Maintenance & Troubleshooting Guide

Dokumentasi ini dibuat untuk membantu teknisi atau user melakukan **maintenance**, **troubleshooting**, dan **operasional** pada sistem **Backend Runtime (Node.js + Express + Prisma + Socket.IO)** yang sudah dibundle dan berjalan tanpa internet.

---

# 📦 1. Struktur Folder Runtime

Setelah proses bundling dan extract ZIP, struktur folder akan seperti berikut:

```
backend-runtime/
├── dist/               # Hasil build TypeScript (index.js dan module lain)
├── node_modules/       # Dependency runtime (termasuk prisma, cors, express, socket.io, dll.)
├── prisma/             # Schema & migration files (jika ada)
├── package.json        # Configuration & script
├── package-lock.json
└── .env                # Environment variable (opsional)
```

Semua file ini **wajib ada** agar backend berjalan normal.

ZIP bundle yang dihasilkan:

```
backend-runtime.zip
```

Bisa di-copy ke server offline dan diextract.

---

# ▶️ 2. Menjalankan Backend

Backend dijalankan menggunakan **PM2** agar stabil dan auto-restart jika ada error.

### ✔ Menjalankan BE:

```
pm2 start dist/index.js --name backend
```

### ✔ Mengecek apakah BE berjalan:

```
pm2 status
```

### ✔ Melihat log realtime:

```
pm2 logs backend
```

### ✔ Restart BE:

```
pm2 restart backend
```

### ✔ Stop BE:

```
pm2 stop backend
```

### ✔ Biar auto-start saat server reboot

```
pm2 save
pm2 startup
```

---

# ⚙️ 3. Konfigurasi Environment (.env)

File `.env` harus ada di folder runtime jika backend membutuhkan environment variable.

Contoh `.env`:

```
DB_URL=sqlserver://username:password@host:port/database
NODE_ENV=production
```

Setelah mengubah `.env`, lakukan restart BE:

```
pm2 restart backend
```

---

# 🔄 4. Update / Deploy Versi Baru

Ketika ada update Backend baru:

1. Jalankan script bundler di development PC:

   ```
   npm run bundle:be
   ```

2. Akan menghasilkan file:

   ```
   backend-runtime.zip
   ```

3. Copy ZIP ke server lokal (flashdisk / LAN transfer)

4. Extract ZIP:

   ```
   unzip backend-runtime.zip
   ```

5. Stop versi lama:

   ```
   pm2 stop backend
   ```

6. Replace folder lama dengan yang baru

7. Jalankan versi baru:

   ```
   pm2 start dist/index.js --name backend
   ```

---

# 🛠 5. Troubleshooting

## ❌ 1. **Server tidak mau start / crash**

**Kemungkinan:**

- Node\_modules belum di-install atau corrupt
- .env missing
- Port bentrok

**Solusi:**

```
pm install --omit=dev
pm2 start dist/index.js --name backend
pm2 logs backend
```

---

## ❌ 2. **Prisma migration error / DB connection error**

**Solusi:**

1. Pastikan `.env` berisi DB\_URL yang benar
2. Jalankan migration jika perlu:

```
pm run migrate:deploy
```

3. Generate Prisma Client:

```
pm run generate
```

4. Restart backend

```
pm2 restart backend
```

---

## ❌ 3. **Port sudah digunakan (EADDRINUSE)**

**Solusi:**

```
pm2 list
pm2 stop <app-name>   # aplikasi yang bentrok
pm2 start dist/index.js --name backend
```

---

## ❌ 4. **Socket.IO tidak connect**

**Penyebab:**

- Port WebSocket blocked
- Firewall / network issue

**Solusi:**

- Pastikan backend port terbuka
- Cek log `pm2 logs backend` untuk error Socket.IO

---

# 🧹 6. Maintenance Rutin

- Bersihkan log PM2:

```
pm2 flush
```

- Restart server setiap minggu:

```
pm2 restart backend
```

- Backup folder runtime & prisma:

```
cp -r backend-runtime /backup/location
```

---

# 📞 7. Kontak Support

```
Divisi Pengembang Sistem
Email: risyan@adaptive.co.id
WA/Telp: 0899-1908-349
```

---

# ✅ Penutup

Dokumen ini dibuat agar teknisi atau user dapat dengan mudah melakukan:

- Menjalankan backend
- Monitoring
- Update / deploy offline
- Troubleshooting
- Maintenance rutin

