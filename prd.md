# PRD: Flux

**Status:** Draft v2 (all-in scope)
**Tipe:** Personal project, single-user
**Developer:** Rahmat

---

## 1. Latar Belakang & Masalah

Saat ini pencatatan keuangan pribadi dan pengelolaan jadwal (Google Calendar) dilakukan terpisah-pisah dan manual — tidak ada satu tempat yang menghubungkan "kapan saya ada acara" dengan "berapa yang saya keluarkan di acara itu", tidak ada kontrol proaktif terhadap batas pengeluaran per kategori, dan tidak ada cara cepat untuk melihat kondisi keuangan + jadwal hari ini dalam satu pandangan.

Flux dibangun untuk menjawab ini secara personal dan menyeluruh: mencatat transaksi keuangan dengan cepat, menyinkronkannya otomatis ke Google Sheets, mengelola jadwal lewat Google Calendar (dan menghubungkannya dengan transaksi), mendisiplinkan pengeluaran lewat budget per kategori yang fleksibel (mingguan/bulanan), mendorong kebiasaan menabung lewat goal, serta menyediakan gambaran analitik yang jelas lewat web dashboard.

## 2. Target Pengguna

Satu pengguna: developer sendiri (mahasiswa). Bukan produk komersial, tidak direncanakan untuk multi-user atau publish ke App Store.

**Konteks penggunaan:**
- Device utama: iPhone (testing via Expo Go, tanpa Mac, tanpa Apple Developer Program)
- Development: Windows + VS Code + Claude Code
- Kebutuhan: input transaksi cepat saat mobile, kontrol & analisis mendalam lewat web dashboard

## 3. Tujuan Produk

1. Mempercepat pencatatan transaksi keuangan harian tanpa friction, dengan arsip otomatis ke Google Sheets.
2. Menyatukan jadwal (Calendar) dan pengeluaran terkait jadwal tersebut.
3. Membantu disiplin menabung lewat goal yang jelas dan terpisah per tujuan.
4. Mengontrol pengeluaran secara proaktif lewat budget per kategori (fleksibel mingguan/bulanan) dengan notifikasi bertingkat.
5. Memberi gambaran analitik keuangan yang jelas dan actionable lewat web dashboard.

## 4. Fitur Inti (MVP — All-in)

### 4.1 Transaksi Keuangan
- Field: tanggal, nominal, tipe (Pemasukan / Pengeluaran / Transfer), kategori, sumber dana, catatan (opsional), tag event Calendar (opsional — pilih event hari itu atau "Lain-lain").
- Kategori: CRUD dari **app maupun web dashboard** (data sinkron).
- Sumber dana (fisik — tunai, bank, dst): CRUD dari **app**. Kantong (sub-kantong) & aturan alokasi otomatis punya aturan CRUD sendiri — lihat Section 4.9.
- Edit & hapus transaksi.
- Sinkronisasi ke Google Sheets **real-time** setiap transaksi baru.
- **Offline-first**: transaksi disimpan lokal (antrian) saat offline, auto-push saat online kembali. UUID dibuat client-side untuk mencegah duplikasi saat retry.

### 4.2 Goal Nabung
- Tiap goal otomatis menjadi entri sumber dana (`funds`) tersendiri, terpisah dari saldo kantong (lihat Section 4.9).
- Bisa multi-goal aktif paralel.
- Field: nama, target nominal, deadline, progress (dihitung dari total transfer masuk ke sumber dana goal tsb).
- CRUD dari app.
- Notifikasi lokal saat goal tercapai (100%).

### 4.3 Budget per Kategori (Lanjutan)
- Tiap kategori dapat memiliki konfigurasi budget: `limit_nominal` + `periode` (**Mingguan** atau **Bulanan**, dipilih bebas per kategori).
  - **Bulanan**: dihitung berdasarkan kalender bulan berjalan.
  - **Mingguan**: dihitung sebagai siklus rolling 7 hari, dimulai dari tanggal budget kategori tersebut dibuat/diset, dan berulang otomatis setiap 7 hari (bukan kalender Senin–Minggu tetap).
- Alert bertingkat, dihitung real-time setiap ada transaksi baru, sesuai periode masing-masing kategori:
  - **Warning** di 80% dari limit.
  - **Alert final** di 100% dari limit.
- **Rekap sisa budget** di akhir tiap periode (akhir bulan untuk kategori bulanan; akhir siklus 7 hari untuk kategori mingguan): notifikasi gabungan (1 notifikasi mencakup semua kategori yang periodenya berakhir di hari itu dan masih bersisa), berisi info "kategori X sisa Rp Y — mau dipindah ke tabungan?". **Bersifat pengingat saja**, bukan transfer otomatis — user tetap harus melakukan aksi transfer manual dari app kalau mau.

### 4.4 Google Calendar
- Lihat & tambah event, 1 calendar (default/primary akun Google).
- Auth: OAuth.
- Reminder: local notification, **waktu dapat diatur per event** (mis. 10 menit / 1 jam / 1 hari sebelum) saat event dibuat.
- **Detail transaksi per event**: pada tampilan detail tanggal, tiap event dapat di-expand untuk melihat transaksi (nominal + kategori) yang ditag ke event tersebut, termasuk transaksi "Lain-lain" (non-event) di tanggal itu.

### 4.5 Sinkronisasi Google Sheets
- Auth: **Service Account** (1 spreadsheet tetap, di-share ke email service account).
- Sync real-time tiap transaksi baru.

### 4.6 Web Dashboard
- **Read-only** laporan & grafik detail:
  - Trend pemasukan/pengeluaran bulan ke bulan (line chart).
  - Breakdown pengeluaran per kategori (pie/bar chart).
  - Progress semua goal nabung dalam satu tampilan.
  - Perbandingan realisasi vs limit budget per kategori.
- **Generate & export** laporan periodik (ke Sheets/PDF).
- **Settings**: CRUD kategori transaksi (sinkron dengan app).

### 4.7 Home (Mobile — Ringkasan Harian)
- Satu tampilan gabungan: total pemasukan/pengeluaran hari ini, saldo Kantong Utama (lihat Section 4.9) saat ini, daftar event Calendar hari ini.

### 4.8 Sistem Notifikasi (konsolidasi)

| # | Notifikasi | Trigger | Sifat |
|---|---|---|---|
| 1 | Reminder event Calendar | Sebelum event mulai, waktu diatur per event | Dijadwalkan di muka |
| 2 | Goal nabung tercapai | Progress goal 100% | Real-time |
| 3 | Budget warning | Pengeluaran kategori capai 80% limit (sesuai periode kategori) | Real-time |
| 4 | Budget alert final | Pengeluaran kategori lewat 100% limit | Real-time |
| 5 | Rekap sisa budget | Akhir periode tiap kategori (bulanan/mingguan sesuai settingnya) | Dijadwalkan di muka, digabung per hari |

Semua notifikasi memakai **local notification** (dijadwalkan/dipicu langsung di perangkat) — kompatibel dengan Expo Go, tidak memerlukan push notification server.

### 4.9 Kantong & Alokasi Otomatis (Rules)
- **Kantong Utama**: bukan sumber dana tersendiri — murni angka hasil hitung real-time dari total saldo semua `funds` (sumber dana fisik, kantong, maupun goal) yang ditandai "termasuk kantong utama". Angka ini **menggantikan** "saldo/total keseluruhan" yang ditampilkan di Home (Section 4.7) — jadi cuma satu angka, bukan dua angka terpisah.
- Tiap `funds` (sumber dana fisik, kantong, goal) punya toggle **"termasuk kantong utama"** (nyala/mati), diatur manual per item:
  - Default sumber dana fisik (tunai, bank, dst): **nyala**.
  - Default kantong & goal: **mati** — supaya uang yang sudah dipindah dari sumber dana fisik ke kantong/goal tidak terhitung dobel (sekali di sumber asal, sekali lagi di kantong/goal tujuan).
  - Bisa diubah bebas kapan saja, dari app maupun web (misal mau mengecualikan 1 rekening bank tertentu dari Kantong Utama).
- **Sub-Kantong** (misal: kantong makan, kantong main, kantong kebutuhan harian): kantong buatan user untuk breakdown alokasi uang yang sudah ada — terpisah dari Budget per Kategori (Section 4.3) yang cuma menghitung limit pengeluaran, bukan benar-benar menyisihkan uang.
  - Diisi lewat transaksi transfer nyata dari sumber dana fisik mana pun yang dipilih user (saldo sumber dana berkurang, saldo kantong bertambah).
  - Bisa langsung dipilih sebagai sumber dana saat input transaksi pengeluaran.
  - CRUD dari **app maupun web dashboard** (data sinkron).
  - Hanya 1 level (tidak bisa dipecah lagi jadi sub-kantong yang lebih detail).
- **Aturan Alokasi Otomatis (Rules)** — opsional, per sub-kantong (boleh gak dipakai sama sekali):
  - 1 aturan terdiri dari: kategori pemicu (kategori pemasukan, misal "Gaji"), persentase, dan kantong tujuan.
  - Trigger: setiap ada transaksi pemasukan baru dengan kategori yang cocok dengan kategori pemicu, sistem otomatis membuat transaksi transfer sebesar persentase × nominal transaksi tersebut, dari sumber dana fisik tempat pemasukan itu tercatat, ke kantong tujuan aturan. Dihitung per transaksi (bukan per total bulanan), jadi pendapatan tak terduga/tidak rutin tetap tertangani secara proporsional kalau kategorinya memang jadi pemicu.
  - Kalau ada lebih dari satu aturan aktif dengan kategori pemicu yang sama, **semua aturan yang cocok jalan bersamaan** pada transaksi pemasukan yang sama.
  - Total persentase gabungan semua aturan aktif untuk 1 kategori pemicu yang sama **tidak boleh lebih dari 100%** — divalidasi saat aturan dibuat/diaktifkan.
  - Sisa yang tidak kena aturan tetap ada di sumber dana fisik asalnya, dan otomatis ikut terhitung di Kantong Utama (karena Kantong Utama cuma angka hasil hitung, bukan hasil transfer manual) — tidak perlu aksi tambahan apa pun.
  - Pemasukan dengan kategori selain yang jadi pemicu aturan (misal pendapatan tak terduga/job dadakan) **tidak** terpengaruh aturan apa pun — tetap transaksi manual biasa, tetap muncul di laporan kategori seperti biasa.
  - Eksekusi aturan berjalan senyap (tidak memicu notifikasi baru).
  - CRUD aturan dari **app maupun web dashboard** (data sinkron).

## 5. Di Luar Scope (Out of Scope)

| Fitur | Alasan |
|---|---|
| Multi-user | Project personal, 1 pengguna |
| Publish ke App Store | Tidak ada Mac / Apple Developer Program; cukup testing via Expo Go |
| Integrasi bank (otomatis maupun semi-otomatis/import CSV) | Tidak ada open banking API publik gratis di Indonesia; pihak ketiga berbayar & butuh approval bisnis; pembacaan notifikasi bank tidak dimungkinkan di iOS |
| Rollover otomatis sisa budget ke periode berikutnya | Sisa budget hanya diinfokan lewat notifikasi rekap (4.3), tidak otomatis menambah limit periode berikutnya |

## 6. Dependensi Eksternal

- Google OAuth (Calendar) — setup Google Cloud project, consent screen mode testing.
- Google Service Account (Sheets) — setup Google Cloud project + share spreadsheet ke email service account.
- Expo Go — local notification (scheduled & real-time) didukung; push notification (server-triggered) tidak didukung tanpa development build (tidak dibutuhkan karena semua notifikasi Flux bersifat lokal).

## 7. Metrik Keberhasilan (Definition of Done — level produk)

MVP dianggap berhasil jika:
- Transaksi bisa dicatat dari HP dalam kondisi online maupun offline, dan selalu berakhir tersinkron ke Sheets tanpa duplikat.
- Goal nabung bisa dibuat, diisi progresnya, dan memicu notifikasi saat tercapai.
- Budget per kategori (mingguan/bulanan) menghasilkan alert 80%/100% yang akurat dan rekap akhir periode yang tepat waktu.
- Event Calendar bisa dilihat/ditambah dari app dengan reminder yang bisa diatur, dan transaksi bisa ditelusuri per event.
- Web dashboard menampilkan 4 jenis grafik (trend, breakdown kategori, progress goal, realisasi vs limit) secara akurat dan bisa generate laporan periodik.
- Kantong Utama menghitung saldo secara akurat sesuai toggle "termasuk kantong utama", sub-kantong bisa dibuat & diisi lewat transfer nyata, dan aturan alokasi otomatis memindahkan persentase yang tepat tanpa pernah melebihi total 100% per kategori pemicu.

---

*Dokumen ini adalah hasil diskusi scoping. Detail implementasi teknis (stack, hosting, pembagian task per bagian) akan dijabarkan di `architecture.md`.*
