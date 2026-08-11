# HCM Metadata

Web app for logging **home-cage-monitoring (HCM) metadata** for the **EBS Room 58** recording rig —
which mice are in each camera cage, disturbance/exclusion events, and per-lab cohort history — so
downstream SLEAP / behavior analysis knows which time windows and which cohorts to trust.

Single-file vanilla-JS front end (`index.html`) backed by Supabase. **No build step, no dependencies.**

> **Live:** https://talmolab.github.io/hcm-metadata/ — GitHub Pages, auto-deploys on merge to `main`.

---

## What it tracks

- **Per-lab rooms** — the 2×4 camera rig split by owner, as tabs:
  - **🧠 AD · Kuo-Fen Lee lab** — physical **Cam 1–4**
  - **🧬 ALS · Eiman lab** — physical **Cam 5–8**
  - **Tye lab** is a selectable *event* target (no cages of its own yet).
- **Occupancy** — which mouse (id, sex, genotype, DOB) is in each cage, with entry/exit times. "Inside" = currently recording.
- **Events** — food / water / cage change, handling, noise, light, person-entered-room, add/remove cohort, **mouse death**, other. Each disturbance marks an **exclusion window** (editable, default 60 min) to drop from analysis.
- **Cohort history** (per lab, AD / ALS sub-tabs) — a per-cage **swimlane timeline** of which genotype occupied each cage over time, with **† death markers**, a live **"recording now"** indicator, the batch table, and a **past-cohort events** section.
- **Exports** — per-lab CSV (exclusion windows / events / occupancy, each gated by a confirm) + a full JSON dump.

## Camera numbering

Cages are labeled by **physical camera position** (Cam 1–8), **not** the Bonsai disk-folder IDs
(`cam_01`…), which are wired differently on the Lee rig (see the lab's CAMERA_SWAP notes). The stored
data is mapped to physical positions.

## Current vs past events

- The **lab event log** (on each lab tab) shows only **current-cohort** events.
- **Past-cohort** events (old deaths, disturbances, transfer-outs) live under **Cohort history → Past-cohort events**.
- Routing: an event on/after the current cohort's start = current; a *remove cohort* is always filed with the past.
- The cage **⚠ badge** counts current-cohort events only.

---

## Architecture

- **Front end:** one `index.html` — vanilla JS, no framework/build. All UI + logic inline in a single `<script>`.
- **Backend:** Supabase (hosted Postgres + auto-generated REST API + Row-Level Security). It **shares the Lee Lab colony Supabase project**; the key embedded in the page is the **publishable** (public-safe) key, guarded by permissive RLS.
- **Tables** — each row stores a JSONB `meta` blob keyed by a generated id, so new fields round-trip without a migration:

  | Table | One row per | `meta` fields |
  |---|---|---|
  | `hcm_occupants` | mouse-stay in a cage | `genotype, sex, dob, entered_at, exited_at, note` |
  | `hcm_events` | event | `type, at, exclude_min, lab, by, note` |
  | `hcm_cohorts` | cohort period | `lab, batch, start, end, genotypes, cages{cam:geno}, mice_per_cage, in_manifest, note` |

  `hcm_events.cage`: **0** = whole room, **1–8** = physical cams, **99** = Tye lab cages.
  `hcm_cohorts.meta.cages` (e.g. `{"1":"Tau","2":"WT",…}`) drives the swimlane timeline.

- **Sync — diff-based per-row upserts.** Every edit writes to `localStorage` instantly, then a debounced (~1.2 s) sync **upserts only the rows that changed**, so two people editing different cages/cohorts never clobber each other. On load it **reconciles** any unsynced local rows against the server (a fast refresh after an edit never loses it); a tab-hide flush covers the rest.

---

## Setup

1. **One-time:** run `hcm_migration.sql` in the Supabase SQL editor (the publishable key can't run DDL). It creates the 3 tables + permissive RLS and seeds the known AD cohort history. It's **idempotent** — safe to re-run (`create table if not exists` + `insert … on conflict do update`).
2. Open `index.html`. Click ⚙ to set **your name** (pre-fills the event form / edit history).

## Running & hosting

- **Local:** open `index.html` directly, or `python3 -m http.server` and visit it. It talks to Supabase over the network — no server of your own.
- **Hosting:** published via **GitHub Pages** at https://talmolab.github.io/hcm-metadata/. The repo is private but talmolab's GitHub **Team** plan allows Pages from a private repo — the repo stays private while the built site is public. **Merges to `main` auto-deploy**, so open a PR, get it reviewed, merge, and it's live.

## Developing

Everything is in **`index.html`**. Config lives at the top of the `<script>` and is the main thing you'll edit for setup changes:

| Constant | What |
|---|---|
| `LABS` | labs, their cages, and colors |
| `CAGES` | physical cam labels + lab ownership |
| `EVENT_LABS` | the **Lab** dropdown in the event form |
| `ACTION_TYPES` / `ACT_COLOR` | event types + default exclusion minutes |
| `GENO_COLOR` | genotype colors for the swimlane |
| `SUPA_URL` / `SUPA_KEY` | Supabase project (publishable key) |

- **Data layer** (rarely needs touching for UI work): `sb()`, `collectRows()`, `syncToSupabase()`, `loadFromSupabase()`, `reconcile()`, `saveLocal()`, `runSync()`, `init()`.
- **Render layer:** `renderAll()` → `renderLab()`, `eventTableHtml()` / `renderEventTable()`, `renderOccTable()`, `renderCohortTimeline()`, `renderCohorts()`, `renderCohortEvents()`.
- **Modals:** `openEvent()` / `saveEvent()`, `openCage()` / `addOcc()`, `openCohort()` / `saveCohort()`.

Quick JS syntax check without a browser (extract the script and run `node --check`):

```bash
node -e "const fs=require('fs');const h=fs.readFileSync('index.html','utf8');const m=h.match(/<script>\s*\(function\(\)\{([\s\S]*?)\}\)\(\);\s*<\/script>/);fs.writeFileSync('/tmp/hcm.js','(function(){'+m[1]+'})();')" && node --check /tmp/hcm.js
```

(or just open the file — the browser console shows runtime errors.)

## Data notes

- Timestamps are **San Diego (PT) wall-clock** (`YYYY-MM-DDTHH:MM`), to line up with the recording clock.
- The AD cohort history is **seeded** (APP-study → empty gap → PD-arrive → Tau/WT/PD → current WT), cross-checked against the lab's `EVENTS.md` + the `hcm-monitor` dashboard/CAMERA_SWAP docs. Per-cage genotypes account for the camera-wiring mismatch. **ALS is empty** until Eiman's cohorts are added.
- The current WT cohort (placed 2026-07-30 15:00, 4 mo, 6♀ 3+3 / 4♂ 2+2) is live in `hcm_occupants`; its recording-start is an `add_cohort` event.

## Files

- `index.html` — the app (front end + all logic).
- `hcm_migration.sql` — Supabase schema + AD cohort seed (run once).
- `README.md` — this file.
