# Flux

Aplikasi personal untuk mencatat transaksi keuangan (sync otomatis ke Google
Sheets) dan mengelola jadwal (Google Calendar) dalam satu tempat, lengkap
dengan budget per kategori, kantong alokasi dana, dan goal nabung.

Project personal, single-user — bukan produk komersial.

## Dokumentasi

- [`prd.md`](./prd.md) — latar belakang masalah & detail tiap fitur
- [`architecture.md`](./architecture.md) — tech stack, data model, task breakdown per milestone
- [`TODO.md`](./TODO.md) — status pengerjaan tiap task

## Tech Stack

- Mobile: Expo (React Native + TypeScript)
- Web dashboard: React + Vite + TypeScript
- Backend: Supabase (Postgres, Auth, Edge Functions)
- Kalender: Google Calendar API
- Spreadsheet: Google Sheets API
