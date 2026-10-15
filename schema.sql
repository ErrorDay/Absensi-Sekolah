-- Schema awal SI-PRESENSI untuk project Supabase kosong.
-- Jalankan sekali melalui Supabase SQL Editor.
-- Face embeddings memakai face_recognition/dlib 128D dan tidak dibuka ke browser.

create schema if not exists extensions;
create extension if not exists vector with schema extensions;

create table if not exists public.kelas (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  grade smallint not null check (grade between 10 and 12),
  visible boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.siswa (
  id uuid primary key default gen_random_uuid(),
  nisn text not null unique,
  name text not null,
  gender text not null check (gender in ('L', 'P')),
  class_id uuid references public.kelas(id) on delete set null,
  status text not null default 'Aktif' check (status in ('Aktif', 'Nonaktif')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.users (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null unique,
  nama text not null,
  role text not null default 'operator' check (role in ('admin', 'operator', 'walas')),
  created_at timestamptz not null default now()
);

create table if not exists public.absensi (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.siswa(id) on delete cascade,
  attendance_date date not null default current_date,
  checked_at timestamptz not null default now(),
  status text not null check (status in ('Tidak Terlambat', 'Terlambat', 'Izin', 'Alpa')),
  source text not null default 'face' check (source in ('face', 'manual', 'import')),
  notes text,
  created_by uuid references public.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (student_id, attendance_date)
);

create table if not exists public.face_embeddings (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.siswa(id) on delete cascade,
  embedding extensions.vector(128) not null,
  model text not null default 'dlib-face-recognition-128d',
  created_at timestamptz not null default now()
);

create table if not exists public.kunjungan_perpustakaan (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.siswa(id) on delete cascade,
  visited_at timestamptz not null default now(),
  source text not null default 'face' check (source in ('face', 'manual')),
  created_by uuid references public.users(id) on delete set null,
  notes text
);

create table if not exists public.hari_libur (
  id uuid primary key default gen_random_uuid(),
  tanggal date not null unique,
  keterangan text,
  created_at timestamptz not null default now()
);

create table if not exists public.settings (
  id smallint primary key default 1 check (id = 1),
  jam_masuk time not null default '07:00',
  batas_terlambat_menit integer not null default 0 check (batas_terlambat_menit >= 0),
  hari_sekolah smallint[] not null default array[0, 1, 2, 3, 4]::smallint[],
  fr_mode text not null default 'disabled' check (fr_mode in ('endpoint', 'local', 'disabled')),
  fr_endpoint_url text,
  updated_at timestamptz not null default now(),
  check (hari_sekolah <@ array[0, 1, 2, 3, 4, 5, 6]::smallint[])
);

insert into public.settings (id)
values (1)
on conflict (id) do nothing;

create index if not exists siswa_class_id_idx on public.siswa(class_id);
create index if not exists absensi_date_idx on public.absensi(attendance_date desc);
create index if not exists absensi_student_date_idx on public.absensi(student_id, attendance_date desc);
create index if not exists kunjungan_perpustakaan_visited_at_idx on public.kunjungan_perpustakaan(visited_at desc);
create index if not exists kunjungan_perpustakaan_student_idx on public.kunjungan_perpustakaan(student_id, visited_at desc);
create index if not exists face_embeddings_embedding_idx
  on public.face_embeddings using hnsw (embedding extensions.vector_cosine_ops);

comment on table public.face_embeddings is
  'Data biometrik wajah. Jangan beri akses langsung kepada role anon/authenticated; gunakan backend tepercaya.';

create or replace function public.current_user_role()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select u.role
  from public.users as u
  where u.id = (select auth.uid())
$$;

revoke all on function public.current_user_role() from public;
grant execute on function public.current_user_role() to authenticated;

grant usage on schema public to authenticated;
grant select, insert, update, delete on
  public.kelas,
  public.siswa,
  public.users,
  public.absensi,
  public.face_embeddings,
  public.kunjungan_perpustakaan,
  public.hari_libur,
  public.settings
  to authenticated;

grant usage, select on all sequences in schema public to authenticated;

alter table public.users enable row level security;
alter table public.kelas enable row level security;
alter table public.siswa enable row level security;
alter table public.absensi enable row level security;
alter table public.face_embeddings enable row level security;
alter table public.kunjungan_perpustakaan enable row level security;
alter table public.hari_libur enable row level security;
alter table public.settings enable row level security;

-- Profil hanya terlihat oleh pemiliknya dan admin. Pembuatan profil/role dilakukan
-- dari dashboard atau backend tepercaya, bukan dari form signup publik.
drop policy if exists users_read_self_or_admin on public.users;
create policy users_read_self_or_admin on public.users
  for select to authenticated
  using (id = (select auth.uid()) or (select public.current_user_role()) = 'admin');

drop policy if exists users_admin_manage on public.users;
create policy users_admin_manage on public.users
  for all to authenticated
  using ((select public.current_user_role()) = 'admin')
  with check ((select public.current_user_role()) = 'admin');

drop policy if exists kelas_read_authenticated on public.kelas;
create policy kelas_read_authenticated on public.kelas
  for select to authenticated using (true);
drop policy if exists kelas_manage_admin_walas on public.kelas;
create policy kelas_manage_admin_walas on public.kelas
  for all to authenticated
  using ((select public.current_user_role()) in ('admin', 'walas'))
  with check ((select public.current_user_role()) in ('admin', 'walas'));

drop policy if exists siswa_read_authenticated on public.siswa;
create policy siswa_read_authenticated on public.siswa
  for select to authenticated using (true);
drop policy if exists siswa_manage_admin_walas on public.siswa;
create policy siswa_manage_admin_walas on public.siswa
  for all to authenticated
  using ((select public.current_user_role()) in ('admin', 'walas'))
  with check ((select public.current_user_role()) in ('admin', 'walas'));

drop policy if exists absensi_read_authenticated on public.absensi;
create policy absensi_read_authenticated on public.absensi
  for select to authenticated using (true);
drop policy if exists absensi_insert_staff on public.absensi;
create policy absensi_insert_staff on public.absensi
  for insert to authenticated
  with check ((select public.current_user_role()) in ('admin', 'operator', 'walas'));
drop policy if exists absensi_update_admin_operator on public.absensi;
create policy absensi_update_admin_operator on public.absensi
  for update to authenticated
  using ((select public.current_user_role()) in ('admin', 'operator'))
  with check ((select public.current_user_role()) in ('admin', 'operator'));
drop policy if exists absensi_delete_admin on public.absensi;
create policy absensi_delete_admin on public.absensi
  for delete to authenticated
  using ((select public.current_user_role()) = 'admin');

drop policy if exists kunjungan_read_authenticated on public.kunjungan_perpustakaan;
create policy kunjungan_read_authenticated on public.kunjungan_perpustakaan
  for select to authenticated using (true);
drop policy if exists kunjungan_insert_staff on public.kunjungan_perpustakaan;
create policy kunjungan_insert_staff on public.kunjungan_perpustakaan
  for insert to authenticated
  with check ((select public.current_user_role()) in ('admin', 'operator', 'walas'));
drop policy if exists kunjungan_admin_manage on public.kunjungan_perpustakaan;
create policy kunjungan_admin_manage on public.kunjungan_perpustakaan
  for all to authenticated
  using ((select public.current_user_role()) = 'admin')
  with check ((select public.current_user_role()) = 'admin');

-- Sengaja tidak ada policy untuk face_embeddings. RLS memblokir akses client;
-- proses pencocokan wajah harus berjalan melalui server/service role.

drop policy if exists hari_libur_read_authenticated on public.hari_libur;
create policy hari_libur_read_authenticated on public.hari_libur
  for select to authenticated using (true);
drop policy if exists hari_libur_admin_manage on public.hari_libur;
create policy hari_libur_admin_manage on public.hari_libur
  for all to authenticated
  using ((select public.current_user_role()) = 'admin')
  with check ((select public.current_user_role()) = 'admin');

drop policy if exists settings_read_authenticated on public.settings;
create policy settings_read_authenticated on public.settings
  for select to authenticated using (true);
drop policy if exists settings_admin_update on public.settings;
create policy settings_admin_update on public.settings
  for update to authenticated
  using ((select public.current_user_role()) = 'admin')
  with check ((select public.current_user_role()) = 'admin');
