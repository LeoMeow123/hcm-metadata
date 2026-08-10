-- HCM Metadata — Supabase schema
-- Run once in the Lee Lab colony Supabase project (SQL Editor → New query → paste → Run).
-- Shares the existing project; the publishable key can't run DDL, so this is manual.
--
-- Two flat tables, each row a JSONB blob keyed by a generated id, so the app can do
-- diff-based per-row upserts (two people editing different cages never clobber each other),
-- and any field added later round-trips without a migration.

create table if not exists hcm_occupants (
  id          text primary key,          -- app-generated stay id
  cage        int  not null,             -- 1..8  (top row 1-4 = Lee AD, bottom 5-8 = ALS)
  mouse_id    text,                       -- ear-tag / label (may repeat across stays)
  meta        jsonb not null default '{}'::jsonb,  -- { lab, genotype, sex, dob, entered_at, exited_at, note }
  updated_at  timestamptz,
  updated_by  text
);

create table if not exists hcm_events (
  id          text primary key,          -- app-generated event id
  cage        int  not null default 0,   -- 0 = whole room, else 1..8
  meta        jsonb not null default '{}'::jsonb,  -- { type, at, exclude_min, note }
  updated_at  timestamptz,
  updated_by  text
);

-- Permissive RLS — same "soft" model as the colony app (open read/write, guarded by
-- the app + audited by updated_by). Tighten later with Supabase Auth if needed.
alter table hcm_occupants enable row level security;
alter table hcm_events    enable row level security;

drop policy if exists hcm_occ_all on hcm_occupants;
drop policy if exists hcm_evt_all on hcm_events;
create policy hcm_occ_all on hcm_occupants for all using (true) with check (true);
create policy hcm_evt_all on hcm_events    for all using (true) with check (true);
