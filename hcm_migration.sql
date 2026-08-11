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
-- Per-cage genotypes are by PHYSICAL cam (= this app's Cam01-04). Verified against
-- EVENTS.md + CAMERA_SWAP.md (disk cam IDs differ from physical: Cam2=cam_03, Cam3=cam_04, Cam4=cam_02).
-- "cages" = structured per-PHYSICAL-cam genotype (drives the swimlane timeline). Cam1-4 = physical positions.
insert into hcm_cohorts (id, meta, updated_by) values
 ('coh_app',     '{"lab":"AD","batch":"APP-study","start":"2024-09-24","end":"~2026-03-01","genotypes":"Cam1 WT | Cam2 APP | Cam3 APP | Cam4 WT  (WT={1,4}, APP={2,3})","cages":{"1":"WT","2":"APP","3":"APP","4":"WT"},"mice_per_cage":"3","in_manifest":"64,269 chunks","note":"Born ~Apr 2024. Each cage later dropped 3->2: Cam1 ~2025-10-18, Cam2 ~2025-12-27, Cam3 ~2025-10-18, Cam4 ~2024-10-15. Manifest (home_cage_manifest.csv) genotype for cam_02/cam_04 is INVERTED - do not trust it. APP sexes: dashboard vs EVENTS.md disagree."}', 'Leo'),
 ('coh_gap',     '{"lab":"AD","batch":"(empty gap)","start":"~2026-03-01","end":"2026-05-06","genotypes":"none (empty)","cages":{},"mice_per_cage":"0","in_manifest":"7,056 chunks (skip)","note":"Recording continued but no mice present."}', 'Leo'),
 ('coh_pd',      '{"lab":"AD","batch":"PD-arrive","start":"2026-05-07","end":"2026-05-13","genotypes":"Cam3 PD | Cam4 WT-sentinel  (Cam1,2 empty)","cages":{"3":"PD","4":"WT-s"},"mice_per_cage":"2 cages (Cam3,4)","in_manifest":"608 chunks","note":"1 wk settling. PD placed in Cam3,4 on 05-07; Cam1,2 still empty. Cam4 later confirmed WT sentinel."}', 'Leo'),
 ('coh_tauwtpd', '{"lab":"AD","batch":"Tau/WT/PD full-cohort","start":"2026-05-14","end":"2026-07-30","genotypes":"Cam1 Tau | Cam2 WT | Cam3 PD | Cam4 WT-sentinel","cages":{"1":"Tau","2":"WT","3":"PD","4":"WT-s"},"mice_per_cage":"2","in_manifest":"12,499 chunks (snapshot ends 07-21)","note":"~2 mo. Cam3,4 carried over from PD-arrive; Cam1,2 (Tau,WT) added 05-14 16:00. Cam1 Tau fatality 07-02 13:00 (->N=1); water flood Cam1 07-02->07-05 (exclude). Cam4 relabeled WT sentinel 06-22. Transfer OUT 07-30 15:00 to CRAF 2909 r5 (cages K-N): 1 Tau, 2 WT, 6 PD."}', 'Leo'),
 ('coh_wt',      '{"lab":"AD","batch":"WT-cohort","start":"2026-07-30","end":"present","genotypes":"all WT - Cam1,2 female | Cam3,4 male","cages":{"1":"WT","2":"WT","3":"WT","4":"WT"},"mice_per_cage":"F x3 (Cam1,2) / M x2 (Cam3,4)","in_manifest":"not in manifest snapshot (ends 07-21)","note":"Current. All WT, DOB ~2026-03-30. Transfer IN 2026-07-30 15:00 PT (3PM): 4mo-WT, 6 female (3+3, Cam1&2) + 4 male (2+2, Cam3&4)."}', 'Leo')
on conflict (id) do update set meta = excluded.meta, updated_by = excluded.updated_by;
