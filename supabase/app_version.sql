-- Run once in the Supabase SQL editor.
-- Holds the newest APK details that the app checks on startup.
create table if not exists public.app_version (
  id int primary key default 1 check (id = 1), -- single row
  latest_build int not null,                   -- build number of the newest APK (the +N in pubspec.yaml)
  min_build int not null default 1,            -- builds below this are blocked until they update
  apk_url text not null,                       -- direct download link for the newest APK
  release_notes text,
  updated_at timestamptz not null default now()
);

alter table public.app_version enable row level security;

drop policy if exists "Anyone can read app version" on public.app_version;
create policy "Anyone can read app version"
  on public.app_version for select
  to anon, authenticated
  using (true);

insert into public.app_version (id, latest_build, min_build, apk_url, release_notes)
values (1, 1, 1, 'https://example.com/okebori_pos.apk', 'First release')
on conflict (id) do nothing;
