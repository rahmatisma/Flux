# TODO: Flux

**Legenda status:** 🔴 Belum Mulai · 🟡 Sedang Dikerjakan · 🟢 Selesai · ⚠️ Terhambat

Referensi kriteria selesai tiap task ada di `architecture.md` Section 5. File ini cuma nyatet status + catatan singkat kalau ada blocker.

---

## Milestone 0 — Fondasi

| # | Task | Status | Catatan |
|---|---|---|---|
| 0.1 | Setup project Supabase | 🟢 | |
| 0.2 | Setup Google Cloud project (OAuth + Calendar API + Sheets API + Service Account) | 🟢 | |
| 0.3 | Buat schema database (semua tabel + RLS) | 🔴 | |
| 0.4 | Setup Expo project (jalan di Expo Go) | 🟢 | |
| 0.5 | Setup web project (deploy kosong ke Vercel) | 🟡 | Project React+Vite sudah jalan lokal, belum di-deploy ke Vercel |

## Milestone 1 — Auth

| # | Task | Status | Catatan |
|---|---|---|---|
| 1.1 | Login Google di web dashboard (+ scope Calendar) | 🔴 | |
| 1.2 | Login Google di mobile app | 🔴 | |
| 1.3 | Proteksi akses single-user (`OWNER_EMAIL`) | 🔴 | |

## Milestone 2 — Transaksi Keuangan (App)

| # | Task | Status | Catatan |
|---|---|---|---|
| 2.1 | CRUD kategori (app) | 🔴 | |
| 2.2 | CRUD sumber dana (app) | 🔴 | |
| 2.3 | Form input transaksi (semua field) | 🔴 | |
| 2.4 | Edit & hapus transaksi | 🔴 | |
| 2.5 | Offline queue (SQLite + retry tanpa duplikat) | 🔴 | |
| 2.6 | Edge Function `sheets-sync` (real-time push ke Sheets) | 🔴 | |

## Milestone 3 — Goal Nabung

| # | Task | Status | Catatan |
|---|---|---|---|
| 3.1 | CRUD goal (app) | 🔴 | |
| 3.2 | Transfer ke goal (nambah progress) | 🔴 | |
| 3.3 | Progress bar goal (UI) | 🔴 | |
| 3.4 | Notifikasi goal tercapai (100%) | 🔴 | |

## Milestone 4 — Budget per Kategori

| # | Task | Status | Catatan |
|---|---|---|---|
| 4.1 | Setting limit & periode kategori (mingguan/bulanan) | 🔴 | |
| 4.2 | Kalkulasi realisasi vs limit sesuai periode | 🔴 | |
| 4.3 | Notifikasi warning 80% & alert 100% | 🔴 | |
| 4.4 | Notifikasi rekap akhir periode (gabungan) | 🔴 | |

## Milestone 5 — Google Calendar

| # | Task | Status | Catatan |
|---|---|---|---|
| 5.1 | Edge Function `calendar-proxy` (list & create event) | 🔴 | |
| 5.2 | Lihat event di app | 🔴 | |
| 5.3 | Tambah event dari app (+ pilihan waktu reminder) | 🔴 | |
| 5.4 | Reminder lokal per event | 🔴 | |
| 5.5 | Tag transaksi ke event ("Lain-lain" kalau tidak ada) | 🔴 | |

## Milestone 6 — Home (Mobile)

| # | Task | Status | Catatan |
|---|---|---|---|
| 6.1 | Ringkasan harian (pemasukan/pengeluaran + saldo + event hari ini) | 🔴 | |

## Milestone 7 — Web Dashboard

| # | Task | Status | Catatan |
|---|---|---|---|
| 7.1 | Grafik trend bulanan (line chart) | 🔴 | |
| 7.2 | Grafik breakdown kategori (pie/bar chart) | 🔴 | |
| 7.3 | Grafik progress semua goal | 🔴 | |
| 7.4 | Grafik realisasi vs limit budget per kategori | 🔴 | |
| 7.5 | Generate & export laporan (PDF/Sheets) | 🔴 | |
| 7.6 | Settings kategori dari dashboard (sinkron dengan app) | 🔴 | |

## Milestone 8 — Kantong & Alokasi Otomatis (Rules)

| # | Task | Status | Catatan |
|---|---|---|---|
| 8.1 | Migrasi skema `funds` (kolom `tipe` + `termasuk_kantong_utama`) | 🔴 | |
| 8.2 | CRUD sub-kantong (app & web) | 🔴 | |
| 8.3 | Toggle "termasuk kantong utama" per fund (app & web) | 🔴 | |
| 8.4 | Kalkulasi Kantong Utama (real-time) | 🔴 | |
| 8.5 | Alokasi manual ke sub-kantong | 🔴 | |
| 8.6 | Tabel `aturan_kantong` + CRUD (app & web) | 🔴 | |
| 8.7 | Eksekusi otomatis aturan | 🔴 | |

---

## Log Perubahan Scope

*(Catatan singkat kalau ada keputusan yang mengubah scope setelah `prd.md`/`architecture.md` fix — biar gak hilang jejak kenapa sesuatu berubah.)*

- **2026-10-04**: Tambah fitur Kantong (Kantong Utama sebagai angka hasil hitung dari toggle "termasuk kantong utama" di tiap `funds`, sub-kantong untuk breakdown alokasi uang, dan aturan alokasi otomatis dari pemasukan ke sub-kantong) — `prd.md` Section 4.9, `architecture.md` Section 3/4.5/5 (Milestone 8). Kolom `is_goal` di tabel `funds` diganti jadi `tipe` enum (`sumber_dana`/`kantong`/`goal`) supaya bisa nampung 3 jenis fund. Goal nabung & budget per kategori tetap berjalan seperti semula, tidak berubah perilakunya.
