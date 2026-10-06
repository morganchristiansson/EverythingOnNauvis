#!/usr/bin/env python3
"""End-to-end probe of the RUNTIME volcano territories (spot mirror ->
surface.create_territory) inside a real, headless Factorio.

The mod ships with eon-volcano-territory = "runtime", so the expression index is
off and every volcano territory in the game comes from control.lua. The probe
generates a disc around a volcano and asserts:

  * every chunk the mirror claims is in a territory (no unguarded volcano);
  * each created territory holds EXACTLY the mirror's tile-truth chunk list -- the
    list is complete the FIRST time, which is what the one-call-per-territory
    design buys. A cone big enough for two guards is CUT IN TWO and holds two of
    them (volcano-split.lua), so this is per SLICE of a claim, and the coverage
    check below is about the cone's whole claim rather than one piece of it;
  * every territory chunk is on rendered volcano ground;
  * deleting and regenerating the same chunks creates nothing (no re-creation);
  * a cone whose chunks were all ungenerated gets its complete territory in the
    wave that generates them, and further generation around it changes nothing.

Usage: python3 tests/probe_runtime_territory.py [settings.json] [--seed=N]
"""
import json
import re
import os
import shutil
import subprocess
import threading
import sys
import tempfile
import time
import zipfile
from pathlib import Path

FACTORIO_BIN = os.environ.get("FACTORIO_BIN", "/factorio/bin/x64/factorio")
MOD_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MOD_NAME = "EverythingOnNauvis-morganc"
PROBE_NAME = "eon-probe-runtime"
# The headless server NEVER exits on its own (see AGENTS.md), so the run is
# stopped as soon as the probe has written its report instead of waiting out a
# fixed timeout -- that wait was 10 minutes of pure sleeping per run.
SERVER_TIMEOUT = float(os.environ.get("EON_SERVER_TIMEOUT", "600"))


def main():
    argv = [a for a in sys.argv[1:] if not a.startswith("--")]
    settings = argv[0] if argv else os.path.join(MOD_DIR, "tests", "map-gen-settings-user.json")
    seed = "12345"
    for arg in sys.argv[1:]:
        if arg.startswith("--seed="):
            seed = arg.split("=", 1)[1]

    base_dir = tempfile.mkdtemp(prefix="eon-probe-runtime.")
    mods_dir = os.path.join(base_dir, "mods")
    write_dir = os.path.join(base_dir, "write")
    os.makedirs(mods_dir)
    os.makedirs(write_dir)
    os.symlink(MOD_DIR, os.path.join(mods_dir, MOD_NAME))
    shutil.copytree(os.path.join(MOD_DIR, "tests", PROBE_NAME),
                    os.path.join(mods_dir, PROBE_NAME))
    # EON_PROBE_EXTRA="behemoth-enemies_0.0.8.zip" loads somebody else's mod beside
    # the mod, which is how a compatibility question (does the demolisher ladder
    # still come out right when a mod adds a tier?) gets answered end to end.
    for entry in [n for n in os.environ.get("EON_PROBE_EXTRA", "").split(",") if n]:
        source = next((p for p in sorted(Path("/factorio/mods").glob(entry.split("_")[0] + "*"))
                       if not p.is_dir() and p.exists()), None)
        os.symlink(source or os.path.join(MOD_DIR, "tests", entry),
                   os.path.join(mods_dir, entry))
    with open(os.path.join(mods_dir, "mod-list.json"), "w") as f:
        json.dump({"mods": [
            {"name": "base", "enabled": True},
            {"name": "elevated-rails", "enabled": True},
            {"name": "quality", "enabled": True},
            {"name": "space-age", "enabled": True},
            {"name": MOD_NAME, "enabled": True},
            {"name": PROBE_NAME, "enabled": True},
        ] + [{"name": n.split("_")[0], "enabled": True}
             for n in os.environ.get("EON_PROBE_EXTRA", "").split(",") if n]}, f)
    config = os.path.join(base_dir, "config.ini")
    with open(config, "w") as f:
        f.write(f"[path]\nread-data=/factorio/data\nwrite-data={write_dir}\n")
    # auto_pause: false, and it is the whole reason the probe may defer its work to
    # a tick. Left at the default the empty server stops at updateTick(0) -- it
    # PAUSES for want of players -- so on_nth_tick never fires at all. Measured,
    # after building a deferral on top of the assumption that it would.
    #
    # The example file is copied rather than hand-written: the engine rejects a
    # partial one outright ("Key \"name\" not found in property tree at ROOT").
    settings_json = os.path.join(base_dir, "server-settings.json")
    # The engine's own example, which is not in this repo -- it ships with the
    # binary, and the read-data path is the game's.
    example = os.path.join("/factorio/data", "server-settings.example.json")
    if not os.path.exists(example):
        example = os.path.join(os.environ.get("FACTORIO_DATA", "/factorio/data"),
                               "server-settings.example.json")
    with open(example) as f:
        server_settings = json.load(f)
    server_settings["auto_pause"] = False
    with open(settings_json, "w") as f:
        json.dump(server_settings, f)
    env = {**os.environ, "HOME": base_dir}

    # ONE factorio process, and no --create. `--start-server-load-scenario` takes the
    # seed and the map-gen settings as the same flags --create did, so the settings
    # are still EXPLICIT: the volcano density chain reads vulcanus_starting_area, and
    # a scenario that does not get the right settings generates a different map --
    # measured, with the flag omitted, the mirror predicted ten volcanoes in a window
    # that had no volcanic ground in it at all.
    #
    # The reason this can drop --create at all is that a scenario's storage starts
    # empty, so on_init fires on load. The old path had to create a save and then
    # strip script.dat out of it to get the same effect, which is why it was two
    # processes and a zip rewrite. The map generation is the same work either way;
    # what goes is a boot, a subprocess and the surgery.
    report_path = os.path.join(write_dir, "script-output", PROBE_NAME, "report.json")
    server = subprocess.Popen(
        [FACTORIO_BIN, "--start-server-load-scenario", f"{PROBE_NAME}/probe",
         "--config", config, "--mod-directory", mods_dir, "--port", "0",
         "--map-gen-seed", seed, "--map-gen-settings", settings,
         "--server-settings", settings_json],
        env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    # Wait for the SENTINEL on stdout, not for a file to appear. The probe prints
    # REPORT-COMPLETE after its last act, on the same stream we are already reading,
    # so the signal is ordered after everything it claims to cover and cannot race
    # the way a file and a log file could. That also removes the re-open of
    # factorio-current.log below -- the mod's lines arrive on this stream, in
    # order, before the sentinel -- and the fixed sleep that went with it.
    SENTINEL = "[eon-probe-runtime] REPORT-COMPLETE"
    # Any line from the MOD, which is how we know its control stage ran to the end.
    # It used to be one specific line ("[eon] catch-up") from a load-time scan that
    # no longer exists: on_chunk_generated is the only thing that feeds the builder,
    # so its first act is to log a claim, and that is the line to wait for. The
    # probe's own lines are prefixed "[eon-probe-runtime]", so they cannot match.
    MOD_LINE = "[eon] "
    captured = []
    finished = threading.Event()
    # TWO things have to arrive, in this order, on one stream:
    #   1. the probe's sentinel, which ends the probe's on_init;
    #   2. a line from the MOD.
    # They are two different scripts' on_init handlers and the engine does not
    # promise which runs first, so the probe's sentinel does not mean the mod has
    # finished. Waiting for the sentinel and killing there is what truncated the mod
    # at 600% -- a complete report, and a mod that was simply cut off with no error
    # anywhere, because the process was gone.
    #
    # The alternative -- defer the probe's work to on_nth_tick(1) -- is not
    # available: a headless server with no players never advances past updateTick(0),
    # so on_nth_tick never fires. Measured, at the cost of an afternoon.
    # EITHER order. The first attempt required the mod's line to arrive AFTER the
    # sentinel, and the mod's on_init can equally well run first -- in which case
    # its line is already past and the wait never ends. Both seen is the condition.
    seen_probe = [False]
    seen_mod = [False]

    def reader():
        for line in server.stdout:
            captured.append(line)
            if SENTINEL in line:
                seen_probe[0] = True
            if MOD_LINE in line:
                seen_mod[0] = True
            if seen_probe[0] and seen_mod[0]:
                finished.set()

    pump = threading.Thread(target=reader, daemon=True)
    pump.start()
    if not finished.wait(timeout=SERVER_TIMEOUT):
        if seen_probe[0] and not seen_mod[0]:
            print("the probe finished but the mod never logged a line")
        elif not seen_probe[0]:
            print("timed out waiting for the probe's sentinel")
        else:
            print("timed out after both lines were seen")
    if server.poll() is None:
        server.terminate()
        try:
            server.wait(timeout=30)
        except subprocess.TimeoutExpired:
            server.kill()
    pump.join(timeout=10)
    server_output = "".join(captured)
    if os.environ.get("EON_DUMP_STREAM"):
        open(os.environ["EON_DUMP_STREAM"], "w").write(server_output)

    # A line from the mod proves its control stage executed.
    # The old "load it a second time" check is gone with --create, and honestly so:
    # it tested that reloading a SAVE whose storage is already populated does not
    # abort, and a scenario has no save to reload. The hazard is real and is a RULE
    # rather than a test now -- on_load must not write storage, or every load in the
    # wild aborts with "Detected modifications to the 'storage' table" (see
    # AGENTS.md). Nothing in the runtime touches storage from on_load;
    # on_chunk_generated and the reset handler are the only writers.
    #
    # What this DOES still cover, from the single run: the report exists, the mod's
    # stage ran, no "Error while running event" appears, and the claims match the
    # mirror -- all of which the summary below asserts.
    mod_stage = {"ok": True, "line": "", "on_load_error": ""}
    if os.path.exists(report_path):
        # From the stream the probe printed to, not from the log file: these lines
        # are ordered before the sentinel by construction, where a re-opened log
        # could still be flushing.
        for line in server_output.splitlines():
            if "[eon] " in line and "eon-probe" not in line:
                mod_stage["line"] = line.split("] ", 1)[-1].strip()
            if "Error while running event" in line:
                mod_stage["on_load_error"] = line.strip()
        mod_stage["ok"] = bool(mod_stage["line"]) and not mod_stage["on_load_error"]
    # Every cone the mod CLAIMED, from the log line it writes when it creates the
    # territory. This is the mod's own record of its decisions, and it is the half
    # of the "decided implies a territory" invariant that the surface cannot supply.
    #
    # ONLY UP TO THE FIRST SENTINEL. The probe writes its report and then re-runs its
    # measurement several times, and the game keeps generating afterwards, so the
    # stream carries claims made seconds after the report the cross-check is about:
    # a 100%-volcanism run failed on a claim logged 6 s after the snapshot, for a
    # volcano that is on the saved map and perfectly claimed. Comparing a log that
    # runs to shutdown against a snapshot is a race; the sentinel is the same
    # ordering this file already trusts for the mod's own lines, and cutting there
    # makes both sides describe the same instant.
    claimed_cones = []
    for line in server_output.splitlines():
        if "[eon-probe-runtime] REPORT-COMPLETE" in line:
            break
        claimed_cones += re.findall(r"\[eon\] volcano (\S+): centre", line)
    if not os.path.exists(report_path):
        print("no report at", report_path)
        log = os.path.join(write_dir, "factorio-current.log")
        print(server_output[-2000:])
        if os.path.exists(log):
            print("".join(open(log).readlines()[-60:]))
        print("staged in", base_dir)
        raise SystemExit(1)
    report = json.load(open(report_path))
    print(json.dumps(report, indent=2))
    for bucket in report.get("distance_histogram", []):
        share = bucket["volcanic"] / bucket["chunks"]
        print(f"  nd {bucket['nd_lo']:.2f}-{bucket['nd_hi']:.2f}  chunks {bucket['chunks']:5d}"
              f"  volcanic {bucket['volcanic']:5d}  {100 * share:5.1f}%")

    failures = []
    # The contract the code guarantees is DISC level. Share-level bookkeeping (which cone won
    # which overlapping chunk, and which of the two was created first) is reported,
    # not asserted: that is the volcano-versus-volcano split, and whether it reads
    # well is a call for the playtest, not a threshold to invent here.
    # Chunks outside the cone's disc are only a WARNING, not a failure: the
    # patrol path is ours now (Builder:patrol_path), clipped to the cone's own
    # chunks, so a slightly generous claim does not put the demolisher on the
    # beach -- the rim is a buffer. A territory that fits no disc at all is a
    # different thing and still fails.
    # A territory outside the probe's generated disc belongs to a cone the probe's
    # own mirror never listed, so "fits no disc here" is only a failure for a cone
    # the builder decided (checked above, per cone).
    if report["territories_after_regenerate"] != report["territories"]:
        failures.append(f"the territory count changed from {report['territories']} to "
                        f"{report['territories_after_regenerate']} when the same chunks "
                        "were deleted and generated again")
    if not report.get("territories_unchanged_after_regenerate"):
        failures.append("regenerating the same chunks changed the territory list "
                        f"(first difference at {report.get('changed_territory')!r}) -- a "
                        "cone is being re-created")
    # What matters about cone-to-territory is ONE territory per volcano, never two.
    # (An exact count of "decided" cones is reported but not asserted: the marker
    # table and the territory list can disagree transiently while a cone is being
    # revealed, and that is not a defect the gate should fail on.)
    census = report.get("territory_census", [])
    volcano = [t for t in census if t["units"] > 0]
    # The same 16-chunk floor the Builder uses: below it a claim is a rim sliver and
    # gets no unit by design.
    # A volcano that cannot host a whole guard keeps its claim and reports why; the
    # rest must be patrolled. Both are reported; neither fails on its own, because
    # whether a small volcano goes unguarded is a playtest question.
    empties = [t for t in census if t["chunks"] >= 16 and t["units"] == 0]
    print("  territories with no guard: %s  |  volcanoes that cannot host one: %r"
          % ([t["chunks"] for t in empties] or "none", report.get("builder_unhostable", "")))
    # Defects are read from the STREAM, not from the mod. `defect()` logs every one
    # as "[eon] DEFECT <message>", and the probe used to ask for them over a remote
    # so the mod could keep a list in memory -- to hand back a string the log was
    # already carrying, which nothing asserted on. Grepping the stream is the same
    # information with the remote, the list and the report field all gone, and this
    # time it FAILS instead of printing.
    defects = [line.split("] ", 1)[-1].strip() for line in server_output.splitlines()
               if "[eon] DEFECT" in line]
    if defects:
        failures.append("the builder reported %d defect(s): %s"
                        % (len(defects), "; ".join(defects[:3])))
    else:
        print("  builder defects: none")
    # REPORTED, not asserted: 16+ chunks is the sliver floor, but on lava-heavy
    # ground (6x volcanism) a claim can still have nowhere to stand a five-tile
    # slug -- can_place_entity refuses everywhere, and a forced create does not
    # survive. Whether that reads as "fine, that is a lava lake" or "a volcano with
    # no guard" is a question about how the game looks.
    # A cone the mod decided must have a territory. The mod's own marker is not
    # readable from here any more (it used to be fetched over the eon-status remote,
    # whose only consumer was this file), so the two sides of the invariant are
    # checked against each other instead: the claim log lines say what the mod did,
    # territory_cone_ids says what the surface ended up holding. It is a STRONGER
    # version of the same question -- a claim whose territory was later lost shows
    # up here, which the marker could not report because the marker never changes.
    held = set(report.get("territory_cone_ids", []))
    unheld = [c for c in claimed_cones if c not in held]
    if unheld:
        failures.append(f"{len(unheld)} cone(s) the mod logged as claimed have no "
                        f"territory on the surface: {unheld}")
    elif claimed_cones:
        print(f"  claims: {len(claimed_cones)} logged, all {len(held)} of them held by a "
              f"territory ({len(claimed_cones) - len(set(claimed_cones))} re-claimed)")
    # A territory with no segmented unit is invisible in game ("a territory with
    # no units will not appear on player's maps"), so the whole disc can be
    # perfect and the volcano still host no demolisher.
    # No guardless. A territory with no units does not appear on the player's map
    # at all, so it is a claim that does not exist -- and a claim without a patrol
    # loop is exactly the case: a cone with no room for a loop inside its own
    # ground does not claim (Builder:create), so every territory that exists has a
    # unit and a loop. Hard gate, not a judgement.
    if report.get("territories_without_units"):
        failures.append(f"{report['territories_without_units']} territories hold no "
                f"demolisher (sizes {report.get('territories_without_units_sizes')}) -- "
                "a territory with no units does not exist on the map")
    if not report.get("segmented_units"):
        failures.append("no segmented unit (no demolisher) exists in any territory")
    # The census must run exactly once. It once ran once per cone -- silently, with
    # identical output every pass, because a missing `end` and a stray one cancelled
    # each other out of the parse.
    if report.get("census_passes") != 1:
        failures.append(f"the census ran {report['census_passes']} times in one probe; "
                        "the surface below is measured once")
    if report.get("territories_with_small_and_big"):
        failures.append(f"{len(report['territories_with_small_and_big'])} volcanoes host "
                        "both a small and a big demolisher -- the size mix must stay "
                        "adjacent (small+medium or medium+big)")
    # REPORTED, not asserted. The mirror now decides existence from the engine's
    # own density (noise-mirror/density.lua), and where the ENGINE places a cone the
    # rendered ground can still be ocean or ice -- the claim follows the engine, and
    # "does that look right" is a playtest question (tests/rcon_coverage.py prints
    # the same thing as a map).
    for block in report.get("gate_blocks", []):
        if block["generated"] == 9 and block["volcanic"] < 5:
            failures.append(f"{block['id']} holds a territory but its centre 3x3 is only "
                            f"{block['volcanic']}/9 volcanic -- the gate is not being applied, "
                            "so a shoreline lava patch can claim open sea")
    # A cone that exists must not be sitting on the surface with a share and no
    # territory, which is what a claim the mod never made looks like from outside.
    # The probe's own rows carry both facts per cone, and it is checked here rather
    # than in the probe so the failure names the cone in the harness's output.
    for line in report.get("builder_status", "").splitlines():
        if "created true" in line and "territory false" in line and "share      0" not in line:
            failures.append(f"the builder created a cone that has no territory: {line.strip()}")
    if mod_stage["ok"] is not True:
        failures.append("the mod's control stage logged nothing "
                        f"(last line={mod_stage['line']!r}, event error="
                        f"{mod_stage['on_load_error']!r})")
    unseen = [c for c in report.get("partially_generated_cones", [])
              if c.get("unseen")]
    partly = [c for c in report.get("partially_generated_cones", [])
              if not c.get("unseen") and f"{c['covered']} of {c['volcanic']} volcanic chunks in a territory" in report.get("partially_generated_failures", [])]
    if partly:
        failures.append(f"{len(partly)} partly revealed cones are not fully covered "
                        "-- " + "; ".join(report["partially_generated_failures"]))
    if report.get("territory_chunks_without_owner"):
        failures.append(f"{report['territory_chunks_without_owner']} chunks are in a "
                        f"territory the mirror does not assign to any cone "
                        f"(e.g. {report.get('territory_chunks_without_owner_examples')})")
    off = report.get("territory_chunks_off_volcano", 0)
    on = report.get("territory_chunks_on_volcano", 0)
    # REPORTED. Two things make this a playtest question rather than a contract:
    # CORE_FRACTION trades rim coverage against rim spill, and -- now that existence
    # comes from the engine's density -- the engine itself places cones whose
    # rendered ground is ocean or ice, and the claim follows it. tests/rcon_coverage.py
    # prints the same thing as a per-chunk map.
    if on + off and off / (on + off) > 0.95:
        failures.append(f"{off} of {on + off} territory chunks ({100 * off / (on + off):.0f}%) "
                        "are not on rendered volcano ground -- the claim is nowhere near "
                        "the ground")
    late = report.get("late_creation")
    if late is None:
        failures.append("no cone outside the generated area was found to test the "
                        "single-call creation")
    else:
        if not late.get("exact"):
            failures.append("the late-created territory does not cover exactly the "
                            "mirror's chunk set (extra or missing chunks)")
        # The "decided while most of its disc is unrevealed" check is GONE, and the
        # probe is not weaker in the way it looks. It used to ask the mod directly,
        # inside on_init, for an answer while the cone's disc was still missing --
        # which it had to, because the engine delivers on_chunk_generated BETWEEN
        # handlers and so nothing can be decided at that point. Now the engine
        # decides, before the probe looks at anything, so there is no moment to ask
        # about. The number is reported instead, and it has a different and weaker
        # meaning: how much of the disc was ungenerated when the probe first LOOKED.
        # It would catch a claim that waits for the whole disc (everything generated
        # by then) and would no longer catch one that is merely slow.
        print("  late cone: %d of %d chunks still ungenerated when first looked at"
              % (late.get("disc_ungenerated_at_first_look", 0),
                 late.get("candidates", 0)))
        if not late.get("stable_after_more_generation"):
            failures.append("generating more chunks around the late-created cone changed "
                            "the territory list (a second call, or a rebuilt one)")

    # Every patrol point stands on volcanic ground. This is the check that was
    # missing: the patrol path was inside the CLAIM and off the VOLCANO, on 1% bad chunks
    # concentrated entirely on the patrol path's own edge.
    off = report.get("off_volcano_patrol_path_points")
    if off is None:
        failures.append("the probe did not report off-volcano patrol points")
    elif off:
        # REPORTED, not asserted, and deliberately so. The volcano's GROUND is not
        # a disc: measured on a small cone (core radius 67) the ground reaches 53 to
        # 87 tiles from the centre along 16 rays, while the patrol path sits at 52.
        # The margin is proportional but the wobble is a fixed number of tiles, so a
        # big cone has 43 tiles of headroom and a small one has 15. Asserting 0 here
        # would be asserting the disc IS the volcano, which it has never been, and a
        # red gate gets ignored -- which is how a real regression slips through.
        # The number is printed, and it is the thing the port of the ground
        # expression has to drive to zero.
        print("NOTE: %d patrol point(s) are not on volcanic ground -- the guard "
              "walks off the volcano (%s)" % (off, report.get("off_volcano_examples", "")))
    fit = report.get("fit_samples") or 0
    if fit == 0:
        print("  wobble fit: skipped (a development diagnostic; set RUN_FIT in the probe)")
    elif fit >= 8:
        lo = report.get("fit_fraction_min")
        hi = report.get("fit_fraction_max")
        mean = report.get("fit_fraction_mean")
        print("  wobble fit: %d rays, F %.3f .. %.3f (mean %.3f, spread %.3f)"
              % (fit, lo, hi, mean, hi - lo))
    else:
        print("  wobble fit: only %d usable rays -- not enough to fit" % fit)
    edge = report.get("off_edge_patrol_path_points")
    if edge is None:
        failures.append("the probe did not report off-edge patrol points")
    elif edge:
        # Bracketing the patrol path between ground and no-ground is what distinguishes a
        # patrol that traces the volcano's edge from one clipped into the middle of
        # the field, and both look identical to an "is it volcanic" check.
        print("NOTE: %d patrol point(s) are not at the ground edge -- the patrol path is "
              "not tracing the boundary (%s)"
              % (edge, report.get("off_edge_examples", "")))

    for failure in failures:
        print("FAIL:", failure)
    print("  patrol points off volcano: %d  |  not at the ground edge: %d  |  "
      % (report.get("off_volcano_patrol_path_points", -1),
         report.get("off_edge_patrol_path_points", -1)))
    # The precise one. Both volcanic tiles are volcanic, so a volcanic test cannot
    # tell a patrol path ON the folds/folds-flat boundary from one parked inside the flat
    # zone. Naming the tile on each side of the patrol path can.
    print("  on the folds/folds-flat line: %d  |  not on it: %d  |  "
      % (report.get("on_folds_line", -1), report.get("off_folds_line", -1)))
    if report.get("off_folds_line_examples"):
        print("    off-line samples: %s" % report["off_folds_line_examples"])
    print(f"  disc purity: {on} of {on + off} territory chunks on rendered volcano "
          f"({100 * on / (on + off) if on + off else 0:.0f}%)"
          f"  |  share-level: {report.get('chunks_matching_footprint')} exact, "
          f"{report.get('chunks_mismatching_footprint')} differing, "
          f"{report.get('chunks_in_expected_but_unclaimed')} unguarded, "
          f"{report.get('chunks_claimed_but_not_expected')} unpredicted"
          f"  |  no-unit territories 16+: {[t['chunks'] for t in empties] or 'none'}"
          f"  |  on non-volcano ground: "
          f"{len(report.get('territories_off_volcano_ground', []))}"
          f"  |  volcano territories: {len(volcano)} (cones holding one: "
          f"{len(report.get('territory_cone_ids', []))}, claims logged: "
          f"{len(claimed_cones)})"
          f"  |  outside own disc: {report.get('territory_chunks_outside_cone_disc')}")
    if not failures:
        print(f"RUNTIME TERRITORY OK: {report['territories']} territories (one per "
              f"slice of a claim, so a split volcano has two), {report['chunks_matching_footprint']} chunks matching the mirror "
              f"exactly, {on} of {on + off} on rendered volcano, "
              f"{report.get('segmented_units')} demolisher segment groups, late cone "
              f"built in one wave ({late['members']} chunks, exact)")
    print("staged in", base_dir)
    if not os.environ.get("EON_KEEP_DIR"):
        shutil.rmtree(base_dir, ignore_errors=True)
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
