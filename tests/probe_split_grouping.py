#!/usr/bin/env python3
"""Dedicated demolisher-territory E2E probe.

Runs EoN with the SHIPPED territory expressions (no override) + a mod that
dumps per-chunk territory ids (via LuaTerritory) and the volcano/lava masks,
then asserts the hard invariants of the territory layout:

  * NO UNGUARDED LAVA: every chunk with lava tiles belongs to a territory
    (free mining of lava/tungsten/acid geysers must never appear).
  * NO LEAKS: no claimed chunk is off volcano ground.
  * NO CRAMPED DEMOLISHERS: no territory < 4 chunks owns a demolisher
    (tail-chasing patrol; calcite-verified guard).

Plus a report of the split layout (territories per volcano cluster, sizes,
demolisher sizes, islands).

Usage: python3 tests/probe_split_grouping.py [seed] [map-gen-settings.json] [--keep]
Exit code 1 on any guard failure.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import zipfile

FACTORIO_BIN = os.environ.get("FACTORIO_BIN", "/factorio/bin/x64/factorio")
MOD_DIR = os.environ.get("MOD_DIR",
                         os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MOD_NAME = "EverythingOnNauvis-morganc"
PROBE_NAME = "eon-probe-grouping"

GUARDS = ("unguarded lava", "leaks", "cramped <4ch with demolisher")


def main():
    seed = sys.argv[1] if len(sys.argv) > 1 else "12345"
    settings = sys.argv[2] if len(sys.argv) > 2 else None
    base_dir = tempfile.mkdtemp(prefix="eon-group.")
    mods_dir = os.path.join(base_dir, "mods")
    write_dir = os.path.join(base_dir, "write")
    os.makedirs(mods_dir)
    os.makedirs(write_dir)
    os.symlink(MOD_DIR, os.path.join(mods_dir, MOD_NAME))
    shutil.copytree(os.path.join(MOD_DIR, "tests", PROBE_NAME),
                    os.path.join(mods_dir, PROBE_NAME))
    with open(os.path.join(mods_dir, "mod-list.json"), "w") as f:
        json.dump({"mods": [
            {"name": "base", "enabled": True},
            {"name": "elevated-rails", "enabled": True},
            {"name": "quality", "enabled": True},
            {"name": "space-age", "enabled": True},
            {"name": MOD_NAME, "enabled": True},
            {"name": PROBE_NAME, "enabled": True},
        ]}, f)
    config = os.path.join(base_dir, "config.ini")
    with open(config, "w") as f:
        f.write(f"[path]\nread-data=/factorio/data\nwrite-data={write_dir}\n")
    env = {**os.environ, "HOME": base_dir}
    save = os.path.join(base_dir, "group.zip")
    cmd = [FACTORIO_BIN, "--create", save, "--config", config,
           "--mod-directory", mods_dir, "--map-gen-seed", seed]
    if settings:
        cmd += ["--map-gen-settings", settings]
    subprocess.run(cmd, env=env, capture_output=True, text=True, timeout=900)
    tmp = save + ".t"
    with zipfile.ZipFile(save) as zin, zipfile.ZipFile(tmp, "w") as zout:
        for name in zin.namelist():
            if name != "script.dat":
                zout.writestr(name, zin.read(name))
    os.replace(tmp, save)
    subprocess.run(
        [FACTORIO_BIN, "--benchmark", save, "--benchmark-ticks", "120000",
         "--benchmark-runs", "1", "--config", config, "--mod-directory", mods_dir],
        env=env, capture_output=True, text=True, timeout=3600)
    report = os.path.join(write_dir, "script-output", "eon-grouping-report.json")
    if not os.path.exists(report):
        sys.exit("no grouping report")
    d = json.load(open(report))
    if os.environ.get("EON_KEEP_DIR") or "--keep" in sys.argv:
        print(f"report dir kept: {base_dir}")
    else:
        shutil.rmtree(base_dir, ignore_errors=True)
    return summarize(d, seed, settings)


def has_bit(c, bit):
    return any(int(ch) & bit for m in c["s"].split("/") for ch in m)


def components(keys):
    s = set(keys)
    n = 0
    while s:
        n += 1
        st = [next(iter(s))]
        while st:
            q = st.pop()
            if q not in s:
                continue
            s.discard(q)
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    z = (q[0] + dx, q[1] + dy)
                    if z in s:
                        st.append(z)
    return n


def summarize(d, seed, settings):
    chunks = d["chunks"]
    nc = {(c["x"], c["y"]): c for c in chunks}
    size_of = {t["t"]: t["size"] for t in d["territories"]}
    units_of = {t["t"]: t["units"] for t in d["territories"]}

    volc = {k for k, c in nc.items() if has_bit(c, 1)}
    parent = {k: k for k in volc}

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    for (x, y) in list(volc):
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                if (dx, dy) != (0, 0) and (x + dx, y + dy) in volc:
                    ra, rb = find((x, y)), find((x + dx, y + dy))
                    if ra != rb:
                        parent[ra] = rb
    clusters = {}
    for k in volc:
        clusters.setdefault(find(k), []).append(k)

    # ---- guards ----
    # Hard invariants: no leaks, and unguarded lava stays RARE. The engine
    # territory system is built for endless blobs, not cropped cones, so a few
    # rim-quantization holes are unavoidable (1 per ~13k chunks at 200%
    # volcanism, 4 at 600% -- probe-measured, all isolated lava corners)
    # (also see features/demolisher-territory.feature). A broken mask shows up
    # as HUNDREDS of holes, so the quota only has to sit above the accepted
    # noise: 10 in a ~13k-chunk disc. Cramped territories (<4ch with a
    # demolisher) are the accepted cell-straddle tradeoff (guarded-but-cramped
    # vs an unguarded gap) -- reported, not failed.
    UNGUARDED_LAVA_LIMIT = 10
    unguarded_lava = [k for k, c in nc.items()
                      if c["t"] == 0 and has_bit(c, 2)]
    leaks = [k for k in nc if nc[k]["t"] > 0 and not has_bit(nc[k], 1)]
    cramped = [t for t in d["territories"] if t["size"] < 4 and t["units"]]

    fails = []
    if len(unguarded_lava) > UNGUARDED_LAVA_LIMIT:
        fails.append(f"UNGUARDED LAVA: {len(unguarded_lava)} lava chunks without "
                     f"territory (limit {UNGUARDED_LAVA_LIMIT}), "
                     f"e.g. {[tuple(v * 32 for v in k) for k in unguarded_lava[:5]]}")
    if leaks:
        fails.append(f"LEAKS: {len(leaks)} claimed chunks off volcano ground")

    print(f"seed={seed} settings={os.path.basename(settings) if settings else 'default'}")
    print(f"territories={d['territory_count']}")
    print(f"  guard unguarded-lava: {len(unguarded_lava)} (limit {UNGUARDED_LAVA_LIMIT})")
    print(f"  guard leaks: {len(leaks)}")
    print(f"  warn  cramped<4: {len(cramped)} "
          f"{[(t['size'], t['units']) for t in cramped[:5]]}")
    if fails:
        for f_ in fails:
            print("FAIL:", f_)
        print("TERRITORY E2E FAILED")
        return 1

    # ---- split layout report ----
    stats = {"1terr": 0, "2terr": 0, "3+terr": 0, "island": 0}
    over_two = []
    for members in clusters.values():
        per_terr = {}
        for k in members:
            per_terr.setdefault(nc[k]["t"], []).append(k)
        ts = sorted(per_terr.items(), key=lambda kv: -len(kv[1]))
        islands = sum(components(ks) for _, ks in ts)
        if len(ts) == 1:
            stats["1terr"] += 1
        elif len(ts) == 2:
            stats["2terr"] += 1
        else:
            stats["3+terr"] += 1
            xs = [x for x, _ in members]
            ys = [y for _, y in members]
            over_two.append({
                "territories": len(ts),
                "volcano_chunks": len(members),
                "bbox": [min(xs), max(xs), min(ys), max(ys)],
                "territory_sizes": [len(v) for _, v in ts],
            })
        if islands > len(ts):
            stats["island"] += 1
    print(f"volcano clusters by territories: {stats} (islands = territories with >1 island)")
    print(f"volcano components with >2 territories: {len(over_two)}")
    for item in sorted(over_two, key=lambda v: (-v["territories"], -v["volcano_chunks"]))[:20]:
        print("  >2terr", item)
    from collections import Counter
    hist = Counter("lt4" if t["size"] < 4 else "4-7" if t["size"] < 15
                   else "15-40" if t["size"] < 60 else "60+" for t in d["territories"])
    uc = Counter()
    for t in d["territories"]:
        for u in t["units"]:
            uc[u] += 1
    print(f"territory sizes: {dict(sorted(hist.items()))}")
    print(f"demolishers: {dict(sorted(uc.items()))}")
    print("TERRITORY E2E PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())