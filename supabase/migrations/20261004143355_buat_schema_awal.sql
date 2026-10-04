-- =====================================================================
-- Migration: Buat schema awal Flux
-- Referensi: architecture.md Section 3 & 4.1, doc/database-schema.md
-- =====================================================================


-- ---------------------------------------------------------------------
-- ENUM TYPES
-- ---------------------------------------------------------------------

create type kategori_tipe as enum ('pemasukan', 'pengeluaran');
create type periode_tipe as enum ('mingguan', 'bulanan');
create type fund_tipe as enum ('sumber_dana', 'kantong', 'goal');
create type transaksi_tipe as enum ('pemasukan', 'pengeluaran', 'transfer');
create type sync_status_tipe as enum ('pending', 'synced', 'failed');


-- ---------------------------------------------------------------------
-- TABEL
-- ---------------------------------------------------------------------
-- Semua tabel dibuat dulu sebelum fungsi/trigger/RLS di bawah, karena
-- fungsi is_owner() (lihat bagian Fungsi Bantu) baca langsung dari
-- app_settings -- kalau fungsi dibuat duluan sebelum tabelnya ada,
-- migration ini bakal gagal ("relation does not exist").

create table app_settings (
  id uuid primary key default gen_random_uuid(),
  owner_email text not null,
  updated_at timestamptz not null default now()
);

create table categories (
  id uuid primary key default gen_random_uuid(),
  nama text not null,
  tipe kategori_tipe not null,
  limit_nominal numeric(14, 2),
  periode periode_tipe,
  periode_start_date date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- Budget cuma valid buat kategori pengeluaran, dan periode_start_date
  -- cuma relevan buat periode mingguan (jadi acuan siklus rolling 7 hari).
  constraint categories_budget_consistency check (
    (limit_nominal is null and periode is null and periode_start_date is null)
    or (limit_nominal is not null and tipe = 'pengeluaran' and periode = 'bulanan' and periode_start_date is null)
    or (limit_nominal is not null and tipe = 'pengeluaran' and periode = 'mingguan' and periode_start_date is not null)
  )
);

create table funds (
  id uuid primary key default gen_random_uuid(),
  nama text not null,
  tipe fund_tipe not null,
  -- Sengaja NOT NULL tanpa DEFAULT di kolom ini -- nilainya diisi lewat
  -- trigger funds_set_default_termasuk_kantong_utama kalau tidak
  -- ditentukan eksplisit saat insert, supaya defaultnya bisa beda
  -- tergantung tipe (lihat trigger di bawah).
  termasuk_kantong_utama boolean not null,
  goal_target_nominal numeric(14, 2),
  goal_deadline date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- Field goal wajib ada kalau tipe = goal, dan dilarang ada kalau bukan.
  constraint funds_goal_consistency check (
    (tipe = 'goal' and goal_target_nominal is not null and goal_deadline is not null)
    or (tipe <> 'goal' and goal_target_nominal is null and goal_deadline is null)
  )
);

create table transactions (
  -- Sengaja tanpa DEFAULT -- id WAJIB dibuat & dikirim dari client (app),
  -- bukan server, supaya transaksi offline punya ID sebelum sempat online
  -- (dasar dari mekanisme anti-duplikat saat retry sync).
  id uuid primary key,
  tipe transaksi_tipe not null,
  nominal numeric(14, 2) not null,
  tanggal date not null,
  category_id uuid references categories (id) on delete restrict,
  fund_id uuid not null references funds (id) on delete restrict,
  fund_tujuan_id uuid references funds (id) on delete restrict,
  catatan text,
  calendar_event_id text,
  sync_status sync_status_tipe not null default 'pending',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint transactions_nominal_positive check (nominal > 0),
  -- category_id wajib ada kecuali transfer (transfer gak punya kategori).
  constraint transactions_category_consistency check (
    (tipe = 'transfer' and category_id is null)
    or (tipe <> 'transfer' and category_id is not null)
  ),
  -- fund_tujuan_id cuma valid buat transfer, dan gak boleh sama dengan
  -- fund_id (gak masuk akal transfer ke wadah yang sama).
  constraint transactions_transfer_consistency check (
    (tipe = 'transfer' and fund_tujuan_id is not null and fund_tujuan_id <> fund_id)
    or (tipe <> 'transfer' and fund_tujuan_id is null)
  )
);

create table aturan_kantong (
  id uuid primary key default gen_random_uuid(),
  kantong_tujuan_id uuid not null references funds (id) on delete restrict,
  category_id uuid not null references categories (id) on delete restrict,
  persentase numeric(5, 2) not null,
  aktif boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint aturan_kantong_persentase_range check (persentase > 0 and persentase <= 100)
);

create table budget_period_state (
  id uuid primary key default gen_random_uuid(),
  category_id uuid not null references categories (id) on delete restrict,
  period_start date not null,
  period_end date not null,
  notified_80 boolean not null default false,
  notified_100 boolean not null default false,
  recap_notified boolean not null default false,
  -- 1 kategori cuma boleh punya 1 baris status per periode yang sama.
  constraint budget_period_state_unique unique (category_id, period_start),
  constraint budget_period_state_period_valid check (period_end >= period_start)
);

create table google_tokens (
  id uuid primary key default gen_random_uuid(),
  refresh_token text not null,
  updated_at timestamptz not null default now()
);

create table calendar_events_cache (
  google_event_id text primary key,
  judul text not null,
  tanggal date not null,
  synced_at timestamptz not null default now()
);


-- ---------------------------------------------------------------------
-- INDEX
-- ---------------------------------------------------------------------
-- Dipasang di kolom yang dipakai buat hitung saldo/budget (fund_id,
-- category_id, tanggal) biar tetap cepat walau riwayat transaksi sudah
-- banyak.

create index idx_transactions_fund_id on transactions (fund_id);
create index idx_transactions_fund_tujuan_id on transactions (fund_tujuan_id) where fund_tujuan_id is not null;
create index idx_transactions_category_id on transactions (category_id) where category_id is not null;
create index idx_transactions_tanggal on transactions (tanggal);
create index idx_aturan_kantong_category_id on aturan_kantong (category_id) where aktif;
create index idx_budget_period_state_category_id on budget_period_state (category_id);


-- ---------------------------------------------------------------------
-- FUNGSI BANTU (dipakai trigger & RLS)
-- ---------------------------------------------------------------------

-- Selalu isi updated_at tiap baris berubah, supaya kode aplikasi tidak
-- perlu (dan tidak bisa lupa) mengisi ini manual.
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- Dipakai semua RLS policy di bawah. SECURITY DEFINER supaya function ini
-- tetap bisa baca app_settings walau tabel app_settings sendiri terkunci
-- total dari role client (lihat kebijakan RLS-nya) -- jadi email pemilik
-- gak pernah ke-expose langsung lewat query client mana pun, cuma lewat
-- hasil true/false function ini.
create or replace function public.is_owner()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.app_settings
    where lower(owner_email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;

-- Default termasuk_kantong_utama sesuai tipe funds. Cuma jalan pas INSERT,
-- dan cuma kalau app gak nentuin nilainya secara eksplisit (NULL) --
-- supaya tetap bisa diubah manual kapan aja setelahnya tanpa ketimpa lagi
-- oleh trigger ini.
create or replace function public.funds_set_default_termasuk_kantong_utama()
returns trigger
language plpgsql
as $$
begin
  if new.termasuk_kantong_utama is null then
    new.termasuk_kantong_utama := (new.tipe = 'sumber_dana');
  end if;
  return new;
end;
$$;

-- Validasi aturan_kantong, 3 penjagaan sekaligus, dicek ulang tiap
-- insert/update:
-- 1) kantong_tujuan_id harus funds bertipe kantong
-- 2) category_id harus categories bertipe pemasukan
-- 3) total persentase semua aturan aktif di kategori yang sama gak lewat 100%
--
-- Catatan: karena single-user app tanpa akses bersamaan dari banyak
-- perangkat sekaligus, validasi total persentase ini gak dibuatin
-- penguncian transaksi tambahan (row lock) -- cukup untuk kebutuhan app ini.
create or replace function public.aturan_kantong_validate()
returns trigger
language plpgsql
as $$
declare
  v_fund_tipe fund_tipe;
  v_category_tipe kategori_tipe;
  v_total_persentase numeric;
begin
  select tipe into v_fund_tipe from funds where id = new.kantong_tujuan_id;
  if v_fund_tipe is distinct from 'kantong' then
    raise exception 'kantong_tujuan_id harus menunjuk ke funds dengan tipe = kantong';
  end if;

  select tipe into v_category_tipe from categories where id = new.category_id;
  if v_category_tipe is distinct from 'pemasukan' then
    raise exception 'category_id harus menunjuk ke categories dengan tipe = pemasukan';
  end if;

  if new.aktif then
    select coalesce(sum(persentase), 0) into v_total_persentase
    from aturan_kantong
    where category_id = new.category_id
      and aktif = true
      and id <> new.id;

    if v_total_persentase + new.persentase > 100 then
      raise exception 'total persentase aturan aktif untuk kategori ini akan melebihi 100%% (sudah %, ditambah %)', v_total_persentase, new.persentase;
    end if;
  end if;

  return new;
end;
$$;


-- ---------------------------------------------------------------------
-- TRIGGER
-- ---------------------------------------------------------------------

-- updated_at otomatis
create trigger trg_app_settings_updated_at before update on app_settings for each row execute function public.set_updated_at();
create trigger trg_categories_updated_at before update on categories for each row execute function public.set_updated_at();
create trigger trg_funds_updated_at before update on funds for each row execute function public.set_updated_at();
create trigger trg_transactions_updated_at before update on transactions for each row execute function public.set_updated_at();
create trigger trg_aturan_kantong_updated_at before update on aturan_kantong for each row execute function public.set_updated_at();
create trigger trg_google_tokens_updated_at before update on google_tokens for each row execute function public.set_updated_at();

-- default termasuk_kantong_utama
create trigger trg_funds_default_termasuk_kantong_utama
before insert on funds
for each row execute function public.funds_set_default_termasuk_kantong_utama();

-- validasi aturan_kantong
create trigger trg_aturan_kantong_validate
before insert or update on aturan_kantong
for each row execute function public.aturan_kantong_validate();


-- ---------------------------------------------------------------------
-- ROW LEVEL SECURITY
-- ---------------------------------------------------------------------

alter table app_settings enable row level security;
alter table categories enable row level security;
alter table funds enable row level security;
alter table transactions enable row level security;
alter table aturan_kantong enable row level security;
alter table budget_period_state enable row level security;
alter table google_tokens enable row level security;
alter table calendar_events_cache enable row level security;

-- app_settings & google_tokens SENGAJA tidak dikasih policy sama sekali --
-- artinya tertutup total dari role client (anon/authenticated), cuma bisa
-- diakses lewat service_role (dipakai Edge Function) atau langsung oleh
-- developer lewat SQL editor/CLI. Sesuai architecture.md Section 3.

create policy "categories_owner_access" on categories
for all using (is_owner()) with check (is_owner());

create policy "funds_owner_access" on funds
for all using (is_owner()) with check (is_owner());

create policy "transactions_owner_access" on transactions
for all using (is_owner()) with check (is_owner());

create policy "aturan_kantong_owner_access" on aturan_kantong
for all using (is_owner()) with check (is_owner());

create policy "budget_period_state_owner_access" on budget_period_state
for all using (is_owner()) with check (is_owner());

create policy "calendar_events_cache_owner_access" on calendar_events_cache
for all using (is_owner()) with check (is_owner());


-- ---------------------------------------------------------------------
-- SEED DATA
-- ---------------------------------------------------------------------
-- Baris pertama & satu-satunya di app_settings. Idempotent (aman dijalankan
-- ulang) -- gak bikin baris baru kalau sudah ada isinya. Tetap gampang
-- diubah kapan aja lewat Supabase Studio tanpa migration baru.

insert into app_settings (owner_email)
select 'rahmatismahidayat@gmail.com'
where not exists (select 1 from app_settings);
