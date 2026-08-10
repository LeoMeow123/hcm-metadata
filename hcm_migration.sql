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

-- ---------------------------------------------------------------------
-- Cohort / batch history (room-level timeline). Powers the "Cohort
-- history" section. The app works without this table (it's fetched
-- defensively), so running this block is optional but recommended.
-- ---------------------------------------------------------------------
create table if not exists hcm_cohorts (
  id          text primary key,
  meta        jsonb not null default '{}'::jsonb,  -- { batch, start, end, genotypes, mice_per_cage, in_manifest, note }
  updated_at  timestamptz,
  updated_by  text
);
alter table hcm_cohorts enable row level security;
drop policy if exists hcm_coh_all on hcm_cohorts;
create policy hcm_coh_all on hcm_cohorts for all using (true) with check (true);

-- Seed the known batch history (idempotent — re-running updates in place).
insert into hcm_cohorts (id, meta, updated_by) values
 ('coh_app',     '{"batch":"APP-study","start":"2024-09-24","end":"2026-02-28","genotypes":"WT, APP","mice_per_cage":"3","in_manifest":"64,269 chunks","note":"~17 mo. Each cage later lost a mouse 3->2 at various dates (see EVENTS.md). Manifest genotype for cam_02/cam_04 is inverted: truth WT={cam01,cam02}, APP={cam03,cam04}."}', 'Leo'),
 ('coh_gap',     '{"batch":"(empty gap)","start":"2026-03-01","end":"2026-05-06","genotypes":"none","mice_per_cage":"0","in_manifest":"7,056 chunks (skip)","note":"Recording continued but no mice present."}', 'Leo'),
 ('coh_pd',      '{"batch":"PD-arrive","start":"2026-05-07","end":"2026-05-13","genotypes":"PD, WT-PD","mice_per_cage":"1 (settling)","in_manifest":"608 chunks","note":"1 wk settling-in period."}', 'Leo'),
 ('coh_tauwtpd', '{"batch":"Tau/WT/PD full-cohort","start":"2026-05-14","end":"2026-07-21","genotypes":"Tau, WT, PD, WT-PD","mice_per_cage":"2","in_manifest":"12,499 chunks","note":"~2 mo. Phys1 Tau fatality 2026-07-02 13:00 (->N=1); water flood Phys1 2026-07-02->07-05 (exclude). Phys4 relabeled WT sentinel 06-22."}', 'Leo'),
 ('coh_wt',      '{"batch":"WT-cohort","start":"2026-07-30","end":"present","genotypes":"WT (4 mo)","mice_per_cage":"F x3 / M x2","in_manifest":"not in this manifest snapshot (ends 07-21)","note":"Current cohort. DOB ~ 2026-03-30. Placed 2026-07-30 15:00 PT."}', 'Leo')
on conflict (id) do update set meta = excluded.meta, updated_by = excluded.updated_by;
