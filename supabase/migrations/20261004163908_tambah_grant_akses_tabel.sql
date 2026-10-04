-- =====================================================================
-- Migration: Tambah GRANT akses tabel (anon, authenticated, service_role)
-- =====================================================================
-- Migration sebelumnya (buat_schema_awal) sudah benar soal RLS, tapi ada
-- lapis izin yang lebih dasar sebelum RLS dicek sama sekali: GRANT.
-- Tanpa GRANT ini, role manapun (termasuk service_role) ditolak total
-- dengan error "permission denied for table ..." sebelum RLS sempat
-- dievaluasi -- jadi RLS yang sudah bagus pun gak kepake kalau GRANT
-- dasarnya belum ada.
--
-- Biasanya Supabase otomatis ngasih GRANT ini ke tabel baru di schema
-- public, tapi ternyata gak otomatis kejadian di project ini -- jadi
-- ditambahkan eksplisit di sini.

grant usage on schema public to anon, authenticated, service_role;

-- anon & authenticated: cuma tabel yang memang dijaga RLS owner-access
-- (kalau bukan owner yang login, RLS tetap nolak walau GRANT ini ada).
grant select, insert, update, delete on public.categories to anon, authenticated;
grant select, insert, update, delete on public.funds to anon, authenticated;
grant select, insert, update, delete on public.transactions to anon, authenticated;
grant select, insert, update, delete on public.aturan_kantong to anon, authenticated;
grant select, insert, update, delete on public.budget_period_state to anon, authenticated;
grant select, insert, update, delete on public.calendar_events_cache to anon, authenticated;

-- app_settings & google_tokens SENGAJA tidak di-grant ke anon/authenticated
-- -- tetap tertutup total dari client, sesuai desain awal.

-- service_role: akses penuh ke semua tabel (dipakai Edge Function, bypass RLS).
grant select, insert, update, delete on public.app_settings to service_role;
grant select, insert, update, delete on public.categories to service_role;
grant select, insert, update, delete on public.funds to service_role;
grant select, insert, update, delete on public.transactions to service_role;
grant select, insert, update, delete on public.aturan_kantong to service_role;
grant select, insert, update, delete on public.budget_period_state to service_role;
grant select, insert, update, delete on public.google_tokens to service_role;
grant select, insert, update, delete on public.calendar_events_cache to service_role;
