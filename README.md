# HCM Metadata — EBS Room 58

**Live:** https://leomeow123.github.io/hcm-metadata/

A small shared web app for logging **home-cage-monitoring metadata**: which mice are in
which camera cage, and disturbances (food change, noise, light, handling…) that mark
windows of recording to **exclude from analysis**.

It is deliberately *not* the full colony DB — it's one focused page for the Talmo-lab /
Lee-lab HCM room. (For recording-pipeline *health* — crash days, inference progress — see
the separate `hcm-monitor` dashboard.)

## The room

A **2×4** grid of camera home cages in EBS 58:

- **Top row (Cam01–Cam04)** — Kuo-Fen Lee Lab · **AD**
- **Bottom row (Cam05–Cam08)** — **ALS**

Each cage shows its current occupants (mouse icons + `id · sex · genotype · age`). Labels and
the cage→lab mapping live in the `CAGES` / `ROWS` constants at the top of the `<script>` — edit
there to relabel or re-map.

## What it does

- **Occupancy** — record a mouse entering a cage (id, sex, genotype, DOB, entry time), and mark
  it out when it leaves. "Inside" = currently recording.
- **Disturbance events** — log food change, water change, cage change, handling, noise, light,
  person-entered-room, or other. Each type has a default exclusion window (e.g. 60 min; cage
  change 120), editable per event. Noise/light default to **whole-room** (all 8 cages); the rest
  default to one cage.
- **Exclusion windows** — the scientific point. Every event = an interval `[event, event + N min]`
  to drop from analysis. **Export → Exclusion windows (CSV)** gives your pipeline one row per
  (event × affected cage): `cage, lab, exclude_start, exclude_end, event, minutes, note`.
- **Cohort history** — a room-level timeline of which batch/cohort occupied the cages over each
  date range (batch, dates, genotypes, mice/cage, manifest status, note) — essential for
  segmenting analysis by cohort. Seeded with the known APP-study → WT-cohort history.
- **Exports** — exclusion windows, occupancy log, disturbance events, cohort history (all CSV), or everything (JSON).

All timestamps are **San Diego (PT) wall-clock**, so they line up with the recording clock.

## Data / sync

Live-synced through **Supabase** (shares the Lee Lab colony project; publishable key is public,
guarded by permissive RLS). Stored granularly — one row per occupancy record and per event — with
**diff-based per-row upserts**, so two people editing different cages never overwrite each other.
Edits save to `localStorage` instantly, sync ~1.2 s after the last change (debounced), flush on
tab-hide, and **reconcile** local-only edits against the server on load.

Three tables: `hcm_occupants`, `hcm_events`, and `hcm_cohorts` (each a JSONB blob keyed by a
generated id). `hcm_cohorts` is fetched defensively — if its migration hasn't been run, the app
still works and just hides the cohort-history section.

## Setup

1. **One-time:** run `hcm_migration.sql` in the Supabase SQL editor (the publishable key can't run
   DDL, so this is manual). It creates the two tables + permissive RLS.
2. Open `index.html` (or the hosted GitHub Pages URL). Click ⚙ to set **your name** (saved with each
   edit).
3. Click a cage to add a mouse; click **＋ Log disturbance** whenever something happens that should
   be excluded from analysis.

No build step, no dependencies — single-file vanilla JS.
