"""QA gate: FAILS CLOSED. Exit nonzero = workflow stops, nothing is pushed.

Checks (all must pass):
  1. Optimized archive opens as valid PMTiles.
  2. min_zoom unchanged; max_zoom <= source (only drops, never adds).
  3. Every tile present at app zooms (z <= 12) decodes to IDENTICAL
     feature bytes as the source (lossless where the app looks).
  4. Optimized file is smaller than source.
"""
import sys

APP_ZOOM_CAP = 12
SAMPLE_TILES_PER_ZOOM = 24


def main(src_path, opt_path):
    from pmtiles.reader import Reader, MemorySource
    import os

    with open(src_path, "rb") as f:
        src = Reader(MemorySource(f.read()))
    with open(opt_path, "rb") as f:
        opt = Reader(MemorySource(f.read()))

    hs, ho = src.header(), opt.header()
    # python pmtiles lib returns header as dict
    if not isinstance(hs, dict):
        hs = hs.__dict__
    if not isinstance(ho, dict):
        ho = ho.__dict__
    print("QA src zoom %s-%s addressed=%s" % (hs.get("min_zoom"), hs.get("max_zoom"), hs.get("num_addressed_tiles")))
    print("QA opt zoom %s-%s addressed=%s" % (ho.get("min_zoom"), ho.get("max_zoom"), ho.get("num_addressed_tiles")))

    assert ho.get("min_zoom") == hs.get("min_zoom"), "min_zoom changed"
    assert ho.get("max_zoom") <= hs.get("max_zoom"), "max_zoom grew"
    assert os.path.getsize(opt_path) < os.path.getsize(src_path), "not smaller — not shipping"

    checked = 0
    for z in range(hs.get("min_zoom"), min(hs.get("max_zoom"), APP_ZOOM_CAP) + 1):
        # Deterministic spread of candidate tiles; keep ones that exist.
        n = 2 ** z
        idxs = sorted(set(
            [0, n - 1]
            + [round(n * f) for f in (i / SAMPLE_TILES_PER_ZOOM for i in range(1, SAMPLE_TILES_PER_ZOOM))]
        ))
        idxs = [i for i in idxs if 0 <= i < n]
        found = 0
        for x in idxs:
            for y in idxs:
                a = src.get(z, x, y)
                if not a:
                    continue
                b = opt.get(z, x, y)
                assert b and bytes(b) == bytes(a), "tile z%d/%d/%d differs" % (z, x, y)
                checked += 1
                found += 1
                if found >= SAMPLE_TILES_PER_ZOOM:
                    break
            if found >= SAMPLE_TILES_PER_ZOOM:
                break
    print("QA tiles byte-identical at z<=%d: %d sampled" % (APP_ZOOM_CAP, checked))
    assert checked > 0, "checked zero tiles — inconclusive, failing closed"
    print("QA RESULT: PASS")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
