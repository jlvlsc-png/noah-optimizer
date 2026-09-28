# noah-optimizer

Server-side forge for NOAH hazard PMTiles. GitHub's free runners do the heavy
lifting on GitHub's network — your link touches nothing, your wallet nothing.

## Why

The source archives (`bettergovph/project-noah-hazard-maps`) are huge and
served over a throttled CDN route. The app never requests tiles above z12, so
deep zooms are dead weight. This pipeline re-clusters, drops unused zooms,
recompresses, QA-gates, and publishes optimized copies to our dataset.

## Setup (one time, in your browser)

1. This repo → **Settings → Secrets → Actions** → New secret:
   `HF_TOKEN` = your HuggingFace **write** token (used only at push time,
   never logged, never stored in the repo).
2. Actions → **Optimize NOAH PMTiles** → **Run workflow**.

## Run order (one layer per run — clean QA per artifact)

1. `flood_100yr` (biggest app-visible win)
2. `landslide` (biggest file — may approach the 6h job limit; if it times
   out, re-run: downloads resume, and we split it next)
3. `ssa1` → `ssa2` → `ssa3` → `ssa4`

Each run uploads a `qa-<layer>` artifact (sizes, zoom ranges, tile checks).

## Wiring (Site Frog side)

Per landed layer, one config line in `READY/Site Frog/hazard-config.js`:

```js
pmtilesUrl: 'https://huggingface.co/datasets/Jrabb1t/ph-hazards/resolve/main/noah-opt/<layer>.pmtiles'
```

Rollback = revert that line to the bettergovph URL. Done layers so far
(unoptimized mirrors, already live): `noah/debris_flow.pmtiles`,
`noah/flood_25yr.pmtiles`, `noah/flood_5yr.pmtiles`.

## Timing table (fill per run)

| layer | src size | opt size | src maxzoom | opt maxzoom | result |
|---|---|---|---|---|---|
| flood_100yr | 1016MB | 558MB (−45%) | 14 | 12 | PASS, wired |
| landslide | 2844MB | 1398MB (−51%) | 14 | 12 | PASS, wired |
| ssa1 | 62MB | 30MB (−51%) | 14 | 12 | PASS, wired |
| ssa2 | 68MB | 34MB (−50%) | 14 | 12 | PASS, wired |
| ssa3 | 69MB | 34MB (−50%) | 14 | 12 | PASS, wired |
| ssa4 | 67MB | 33MB (−50%) | 14 | 12 | PASS, wired |

## Recipe (job/optimize.sh + job/qa.py)

- `pmtiles extract --maxzoom=12` when the source carries deeper zooms,
  else lossless gzip recompress.
- QA fails closed: byte-identical tiles at all app zooms (sampled),
  zoom range never grows, output must be smaller — else no push.
- v2 (only if v1 gains < 30% first-paint): geometry simplification via
  tippecanoe decode/re-encode pass.
