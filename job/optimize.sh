#!/usr/bin/env bash
# NOAH PMTiles optimizer — runs on GitHub's network (free tier), NOT yours.
# Recipe v1 (lossless at app zooms):
#   1. pull source archive from bettergovph (fast internal-ish pipe)
#   2. re-cluster + drop zooms above MAXZOOM_CAP (app caps requests at z12)
#   3. gzip recompress
#   4. QA gate (job/qa.py) — push ONLY on PASS
#   5. push noah-opt/<layer>.pmtiles to Jrabb1t/ph-hazards
set -euo pipefail

: "${HF_TOKEN:?set HF_TOKEN repo secret}"
: "${LAYER:?set LAYER input}"

SRC_REPO="bettergovph/project-noah-hazard-maps"
DST_REPO="Jrabb1t/ph-hazards"

case "$LAYER" in
  flood_100yr) SRC_FILE="PMTiles/layers/flood_100yr.pmtiles" ;;
  landslide)   SRC_FILE="PMTiles/layers/landslide.pmtiles" ;;
  ssa1)        SRC_FILE="PMTiles/layers/storm_surge_ssa1.pmtiles" ;;
  ssa2)        SRC_FILE="PMTiles/layers/storm_surge_ssa2.pmtiles" ;;
  ssa3)        SRC_FILE="PMTiles/layers/storm_surge_ssa3.pmtiles" ;;
  ssa4)        SRC_FILE="PMTiles/layers/storm_surge_ssa4.pmtiles" ;;
  *) echo "unknown layer $LAYER"; exit 1 ;;
esac

MAXZOOM_CAP="${MAXZOOM_CAP:-12}"
WORK="$RUNNER_TEMP/noah-opt"
mkdir -p "$WORK"
SRC="$WORK/src.pmtiles"
OUT="$WORK/${LAYER}.opt.pmtiles"

echo "=== pull $SRC_FILE ==="
python3 - "$SRC_REPO" "$SRC_FILE" "$SRC" <<'EOF'
import sys
from huggingface_hub import hf_hub_download
repo, fname, dest = sys.argv[1], sys.argv[2], sys.argv[3]
p = hf_hub_download(repo_id=repo, repo_type="dataset", filename=fname,
                    local_dir="/tmp/noah-dl", token=None)
import shutil
shutil.copy(p, dest)
print("pulled", dest)
EOF

echo "=== source metadata ==="
SRC_ZMAX=$(python3 - "$SRC" <<'EOF'
import sys
from pmtiles.reader import Reader, MemorySource
r = Reader(MemorySource(open(sys.argv[1], "rb").read()))
h = r.header()
# header() returns a dict in the python pmtiles lib
print(h["max_zoom"])
print("min_zoom=%s max_zoom=%s addressed=%s compression=%s" % (
    h.get("min_zoom"), h.get("max_zoom"),
    h.get("num_addressed_tiles"), h.get("tile_compression")), file=sys.stderr)
EOF
)
echo "source maxzoom=$SRC_ZMAX cap=$MAXZOOM_CAP"

if [ "$SRC_ZMAX" -gt "$MAXZOOM_CAP" ]; then
  echo "=== extract z0-$MAXZOOM_CAP (drops unused deep zooms, re-clusters) ==="
  pmtiles extract --maxzoom="$MAXZOOM_CAP" "$SRC" "$OUT"
else
  echo "=== full rewrite (re-cluster + recompress, no zooms to drop) ==="
  pmtiles extract "$SRC" "$OUT"
fi

echo "=== sizes ==="
ls -la "$SRC" "$OUT"
python3 - "$SRC" "$OUT" > qa-report.txt <<'EOF'
import sys
from pmtiles.reader import Reader, MemorySource
import os
a, b = sys.argv[1], sys.argv[2]
ra = Reader(MemorySource(open(a, "rb").read()))
rb = Reader(MemorySource(open(b, "rb").read()))
ha, hb = ra.header(), rb.header()
print("src bytes:", os.path.getsize(a))
print("opt bytes:", os.path.getsize(b))
for tag, h in (("src", ha), ("opt", hb)):
    if isinstance(h, dict):
        print("%s zoom: %s-%s addressed=%s compression=%s" % (
            tag, h.get("min_zoom"), h.get("max_zoom"),
            h.get("num_addressed_tiles", "?"), h.get("tile_compression", "?")))
    else:
        print("%s zoom: %s-%s addressed=%s compression=%s" % (
            tag, getattr(h, "min_zoom", "?"), getattr(h, "max_zoom", "?"),
            getattr(h, "num_addressed_tiles", "?"), getattr(h, "tile_compression", "?")))
EOF
cat qa-report.txt

echo "=== QA gate ==="
python3 job/qa.py "$SRC" "$OUT" | tee -a qa-report.txt

echo "=== push to $DST_REPO ==="
python3 - "$OUT" <<'EOF'
import os, sys
from huggingface_hub import upload_file
layer = os.environ["LAYER"]
upload_file(path_or_fileobj=sys.argv[1],
            path_in_repo="noah-opt/%s.pmtiles" % layer,
            repo_id="Jrabb1t/ph-hazards", repo_type="dataset",
            token=os.environ["HF_TOKEN"])
print("pushed noah-opt/%s.pmtiles" % layer)
EOF
echo "DONE $LAYER"
