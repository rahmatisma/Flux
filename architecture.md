# Architecture: Flux

**Status:** Draft v1
**Referensi:** `prd.md`

---

## 1. Tech Stack

| Layer | Teknologi | Catatan |
|---|---|---|
| Mobile App | Expo (React Native + TypeScript) | Testing via Expo Go, tanpa dev build/App Store |
| Web Dashboard | React + Vite (atau Next.js) + TypeScript | Hosting: Vercel (free tier) |
| Backend Logic | Supabase Edge Functions (TypeScript/Deno) | Gak perlu server terpisah |
| Database | Supabase Postgres | Termasuk Auth & Storage bawaan |
| Auth | Supabase Auth — Google OAuth provider | 1 login, sekaligus request scope Calendar |
| Kalender | Google Calendar API | Diakses lewat Edge Function (server-side, pakai token dari Supabase Auth) |
| Spreadsheet | Google Sheets API | Auth: Service Account terpisah (bukan OAuth user) |
| Notifikasi | `expo-notifications` (local notification) | Semua notifikasi dijadwalkan/dipicu di device, tanpa push server |
| Offline Storage | `expo-sqlite` | Antrian transaksi lokal saat offline |
| Charting (web) | Recharts atau Chart.js | Untuk 4 grafik dashboard |
| PDF Export | Edge Function + library PDF (mis. `pdf-lib` atau render HTML→PDF via service ringan) | Untuk export laporan |

**Kenapa gak pakai Laravel:** biar seluruh stack konsisten TypeScript (mobile, web, backend logic), gak perlu hosting server PHP terpisah, dan Supabase Edge Functions sudah cukup untuk semua kebutuhan server-side (OAuth proxy, Sheets sync, PDF generation, kalkulasi budget).

---

## 2. Alur Arsitektur (High-Level)

```
[Expo App] ──┐
             ├──> [Supabase Auth (Google OAuth)] ──> [Supabase Postgres]
[Web React] ─┘                                              │
                                                              ├──> [Edge Function: sheets-sync] ──> Google Sheets API
                                                              ├──> [Edge Function: calendar-proxy] ──> Google Calendar API
                                                              └──> [Edge Function: report-generate] ──> PDF/Sheets export
```

- Mobile & web **tidak pernah** memanggil Google API langsung — semua lewat Edge Function, supaya token (OAuth & Service Account) tidak pernah ada di client.
- Mobile & web sama-sama pakai Supabase client (`@supabase/supabase-js`) untuk baca/tulis data transaksi, kategori, sumber dana, goal secara langsung (dilindungi Row Level Security/RLS agar cuma 1 user yang bisa akses).

---

## 3. Data Model (Supabase Postgres)

### `categories`
| Kolom | Tipe | Catatan |
|---|---|---|
| id | uuid (PK) | |
| nama | text | |
| limit_nominal | numeric, nullable | Budget, opsional |
| periode | enum('mingguan','bulanan'), nullable | Wajib diisi kalau `limit_nominal` diisi |
| periode_start_date | date, nullable | Untuk periode mingguan — tanggal dibuat, jadi acuan siklus rolling 7 hari |
| created_at | timestamptz | |

### `funds` (sumber dana fisik + kantong + goal nabung)
| Kolom | Tipe | Catatan |
|---|---|---|
| id | uuid (PK) | |
| nama | text | |
| tipe | enum('sumber_dana','kantong','goal') | `sumber_dana` = tunai/bank fisik, `kantong` = sub-kantong budget (lihat Section 4.5), `goal` = goal nabung |
| termasuk_kantong_utama | boolean, default true | Dipakai hitung "Kantong Utama" (Section 4.5) — default `true` untuk tipe `sumber_dana`, default `false` untuk tipe `kantong`/`goal` (mencegah hitung dobel saat uang sudah dipindah ke kantong/goal), bisa diubah manual |
| goal_target_nominal | numeric, nullable | Hanya kalau `tipe = 'goal'` |
| goal_deadline | date, nullable | Hanya kalau `tipe = 'goal'` |
| created_at | timestamptz | |

### `transactions`
| Kolom | Tipe | Catatan |
|---|---|---|
| id | uuid (PK) | **Dibuat di client (mobile)**, bukan auto-generate server, untuk dukung offline-first |
| tipe | enum('pemasukan','pengeluaran','transfer') | |
| nominal | numeric | |
| tanggal | date | |
| category_id | uuid, nullable, FK → categories | Null untuk tipe `transfer` |
| fund_id | uuid, FK → funds | Sumber dana asal (atau sumber dana yang kena efek untuk pemasukan) |
| fund_tujuan_id | uuid, nullable, FK → funds | Hanya untuk tipe `transfer` |
| catatan | text, nullable | |
| calendar_event_id | text, nullable | ID event Google Calendar, null = "Lain-lain" |
| sync_status | enum('pending','synced','failed') | Untuk tracking sync ke Sheets |
| created_at | timestamptz | |

### `aturan_kantong`
Aturan alokasi otomatis dari pemasukan ke kantong (lihat Section 4.5 & `prd.md` Section 4.9).
| Kolom | Tipe | Catatan |
|---|---|---|
| id | uuid (PK) | |
| kantong_tujuan_id | uuid, FK → funds | Harus fund dengan `tipe = 'kantong'` |
| category_id | uuid, FK → categories | Kategori pemasukan yang jadi pemicu |
| persentase | numeric | 0–100 |
| aktif | boolean, default true | |
| created_at | timestamptz | |

Validasi aplikasi (bukan constraint database): total `persentase` dari semua baris `aktif = true` dengan `category_id` yang sama tidak boleh melebihi 100.

### `budget_period_state`
Tabel bantu untuk mencegah notifikasi budget terkirim berkali-kali dalam 1 periode yang sama.
| Kolom | Tipe | Catatan |
|---|---|---|
| id | uuid (PK) | |
| category_id | uuid, FK → categories | |
| period_start | date | |
| period_end | date | |
| notified_80 | boolean, default false | |
| notified_100 | boolean, default false | |
| recap_notified | boolean, default false | |

### `google_tokens`
Disimpan terenkripsi, dipakai Edge Function untuk akses Calendar API. Hanya 1 baris (single user).
| Kolom | Tipe | Catatan |
|---|---|---|
| id | uuid (PK) | |
| refresh_token | text (encrypted) | |
| updated_at | timestamptz | |

### `calendar_events_cache`
Cache ringan supaya app gak perlu selalu hit Google API buat nampilin daftar event.
| Kolom | Tipe | Catatan |
|---|---|---|
| google_event_id | text (PK) | |
| judul | text | |
| tanggal | date | |
| synced_at | timestamptz | |

---

## 4. Desain Kunci

### 4.1 Autentikasi & Akses Tunggal
- Login via Supabase Auth, provider Google, dengan scope tambahan `https://www.googleapis.com/auth/calendar`.
- Setelah login berhasil, cek email user terhadap 1 email yang di-hardcode di environment variable (`OWNER_EMAIL`). Kalau tidak cocok → langsung sign-out & tolak akses.
- Refresh token Google disimpan di tabel `google_tokens` (bukan di client) — dipakai Edge Function `calendar-proxy` untuk semua request ke Calendar API.

### 4.2 Offline-First Transaksi
- Transaksi dibuat dengan UUID di client (pakai `expo-crypto` atau lib UUID), disimpan dulu ke SQLite lokal dengan status `pending`.
- Saat online, background sync mencoba push ke Supabase (`transactions` table) — karena ID sudah dibuat di client, retry yang gagal setengah jalan tidak akan bikin duplikat (upsert by ID).
- Setelah tersimpan di Supabase, trigger database (Postgres trigger/webhook) memanggil Edge Function `sheets-sync` untuk push baris itu ke Google Sheets secara real-time.

### 4.3 Notifikasi Lokal
Semua dijadwalkan/dipicu dari **mobile app**, bukan dari server (karena Expo Go tidak mendukung push notification):
- **Reminder event Calendar**: dijadwalkan saat event dibuat/diedit, pakai waktu yang dipilih user.
- **Goal tercapai & Budget warning/alert**: dicek langsung di app setiap kali transaksi baru berhasil disimpan (bandingkan progress/pengeluaran terhadap target/limit).
- **Rekap sisa budget**: app menghitung `period_end` tiap kategori berbudget setiap kali dibuka, lalu menjadwalkan local notification untuk tanggal tersebut (malam hari). Status `notified_*` di `budget_period_state` mencegah notifikasi dobel.

### 4.4 Kalkulasi Periode Budget
- **Bulanan**: `period_start` = tanggal 1 bulan berjalan, `period_end` = akhir bulan.
- **Mingguan**: `period_start` = `periode_start_date` + (n × 7 hari), berulang otomatis; `period_end` = `period_start + 6 hari`.

### 4.5 Kantong Utama & Alokasi Otomatis (Rules)
- **Kantong Utama tidak disimpan sebagai baris data** — dihitung on-the-fly: `SUM(saldo)` dari semua `funds` yang `termasuk_kantong_utama = true`. Saldo tiap fund dihitung dari net transaksi (`pemasukan` + `transfer masuk` − `pengeluaran` − `transfer keluar`) yang `fund_id`/`fund_tujuan_id`-nya merujuk fund tersebut.
- Karena bukan fund sungguhan, Kantong Utama **tidak bisa** dipilih sebagai `fund_id`/`fund_tujuan_id` di transaksi apa pun — transfer ke kantong selalu menyebut sumber dana fisik spesifik, bukan "Kantong Utama" sebagai perantara.
- Nilai ini menggantikan "saldo/total keseluruhan" di Home (`prd.md` Section 4.7) — satu angka, bukan dua.
- **Eksekusi rule**: setiap transaksi `pemasukan` baru berhasil disimpan, app mengecek tabel `aturan_kantong` yang `aktif = true` dan `category_id`-nya cocok dengan kategori transaksi tersebut. Untuk tiap aturan yang cocok, app otomatis membuat 1 transaksi baru tipe `transfer`: `fund_id` = fund asal transaksi pemasukan, `fund_tujuan_id` = `kantong_tujuan_id` aturan, `nominal` = `persentase` × nominal transaksi pemasukan.
- Pengecekan ini berjalan di **app** (sama seperti pengecekan goal/budget di Section 4.3), karena transaksi hanya dibuat dari mobile app — web dashboard read-only untuk transaksi (`prd.md` Section 4.6).

---

## 5. Task Breakdown

Setiap task berikut punya kriteria selesai (Definition of Done) sendiri, sesuai urutan yang disarankan dikerjakan.

### Milestone 0 — Fondasi
| Task | Definition of Done |
|---|---|
| Setup project Supabase | Project dibuat, koneksi Postgres bisa diakses, `.env` tersimpan aman |
| Setup Google Cloud project | OAuth client ID dibuat, Calendar API & Sheets API di-enable, Service Account dibuat & di-share ke 1 spreadsheet tujuan |
| Buat schema database | Semua tabel di Section 3 dibuat via migration, RLS aktif dan hanya izinkan `OWNER_EMAIL` |
| Setup Expo project | App kosong bisa jalan di Expo Go di iPhone, hot reload berfungsi |
| Setup web project | App React kosong bisa di-deploy ke Vercel dan diakses via URL |

### Milestone 1 — Auth
| Task | Definition of Done |
|---|---|
| Login Google di web dashboard | User bisa login via Google, scope Calendar ter-request, refresh token tersimpan di `google_tokens` |
| Login Google di mobile app | User bisa login via Google dari Expo app, session tersimpan |
| Proteksi akses single-user | Login dengan email selain `OWNER_EMAIL` otomatis ditolak & sign-out |

### Milestone 2 — Transaksi Keuangan (App)
| Task | Definition of Done |
|---|---|
| CRUD kategori (app) | Bisa tambah/edit/hapus kategori dari app, tersimpan & sinkron ke Supabase |
| CRUD sumber dana (app) | Bisa tambah/edit/hapus sumber dana dari app |
| Form input transaksi | Semua field (tanggal, nominal, tipe, kategori, sumber dana, catatan, tag event) bisa diisi dan tersimpan |
| Edit & hapus transaksi | Transaksi lama bisa diubah/dihapus, perubahan tersinkron |
| Offline queue | Transaksi yang dibuat saat offline tersimpan di SQLite lokal, otomatis ter-push saat online, tidak ada duplikat setelah retry |
| Edge Function `sheets-sync` | Transaksi baru di Supabase otomatis muncul sebagai baris baru di Google Sheets dalam hitungan detik |

### Milestone 3 — Goal Nabung
| Task | Definition of Done |
|---|---|
| CRUD goal (app) | Bikin goal otomatis membuat entri `funds` dengan `tipe = 'goal'` |
| Transfer ke goal | Transaksi tipe `transfer` ke goal menambah progress goal tersebut |
| Progress bar goal | UI menampilkan persentase progress tiap goal secara akurat |
| Notifikasi goal tercapai | Local notification muncul tepat saat progress goal menyentuh 100% |

### Milestone 4 — Budget per Kategori
| Task | Definition of Done |
|---|---|
| Setting limit & periode kategori | Kategori bisa diberi `limit_nominal` + pilih periode (mingguan/bulanan) |
| Kalkulasi realisasi vs limit | App bisa menghitung total pengeluaran kategori sesuai periode aktifnya dengan benar |
| Notifikasi warning 80% & alert 100% | Muncul tepat saat threshold terlewati, tidak berulang dalam periode yang sama |
| Notifikasi rekap akhir periode | Muncul di akhir periode (malam hari), menggabungkan semua kategori yang bersisa di hari itu |

### Milestone 5 — Google Calendar
| Task | Definition of Done |
|---|---|
| Edge Function `calendar-proxy` | Bisa list, create event dari server menggunakan token tersimpan |
| Lihat event di app | Daftar event dari Google Calendar tampil di tab Calendar |
| Tambah event dari app | Event baru berhasil masuk ke Google Calendar asli, dengan pilihan waktu reminder |
| Reminder lokal per event | Local notification muncul sesuai waktu yang dipilih sebelum event |
| Tag transaksi ke event | Transaksi bisa memilih event hari itu (atau "Lain-lain"), muncul di detail event |

### Milestone 6 — Home (Mobile)
| Task | Definition of Done |
|---|---|
| Ringkasan harian | Home menampilkan total pemasukan/pengeluaran hari ini, saldo Kantong Utama (hasil hitung dari fund yang `termasuk_kantong_utama = true`, lihat Section 4.5), dan event hari ini dalam satu tampilan, update real-time |

### Milestone 7 — Web Dashboard
| Task | Definition of Done |
|---|---|
| Grafik trend bulanan | Line chart pemasukan/pengeluaran per bulan tampil akurat |
| Grafik breakdown kategori | Pie/bar chart pengeluaran per kategori sesuai data aktual |
| Grafik progress goal | Semua goal aktif tampil dengan progress masing-masing |
| Grafik realisasi vs limit budget | Perbandingan per kategori tampil akurat sesuai periode masing-masing |
| Generate & export laporan | Bisa export laporan periode tertentu ke PDF dan/atau trigger update ke Sheets |
| Settings kategori (dashboard) | CRUD kategori dari dashboard tersinkron dengan app |

### Milestone 8 — Kantong & Alokasi Otomatis (Rules)
| Task | Definition of Done |
|---|---|
| Migrasi skema `funds` (kolom `tipe` + `termasuk_kantong_utama`) | Kolom `is_goal` diganti `tipe` enum, kolom `termasuk_kantong_utama` ditambahkan dengan default sesuai Section 3 |
| CRUD sub-kantong (app & web) | Bisa tambah/edit/hapus kantong dari app maupun web, tersimpan & sinkron |
| Toggle "termasuk kantong utama" per fund (app & web) | Tiap fund (sumber dana/kantong/goal) bisa diubah toggle-nya, berubah real-time di perhitungan Kantong Utama |
| Kalkulasi Kantong Utama (real-time) | Angka Kantong Utama di Home selalu akurat sesuai Section 4.5, update tiap ada transaksi baru |
| Alokasi manual ke sub-kantong | Transfer dari sumber dana fisik ke sub-kantong tercatat & saldo kedua fund berubah dengan benar |
| Tabel `aturan_kantong` + CRUD (app & web) | Aturan bisa dibuat/diedit/dihapus dari app maupun web, validasi total persentase per kategori pemicu ≤ 100% berjalan |
| Eksekusi otomatis aturan | Transaksi pemasukan baru yang kategorinya cocok otomatis memicu transfer sesuai persentase aturan aktif, tanpa notifikasi tambahan |

---

## 6. Hosting & Deployment

| Komponen | Platform | Biaya |
|---|---|---|
| Database + Auth + Edge Functions | Supabase | Free tier (cukup untuk 1 user) |
| Web Dashboard | Vercel | Free tier |
| Mobile App | Expo Go (development) | Gratis, tanpa build/publish |

Tidak ada komponen yang butuh biaya untuk skala 1 user.
