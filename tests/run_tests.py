#!/usr/bin/env python3
"""
Validation tests for EverythingOnNauvis-morganc surface condition handling.

Runs the factorio binary headlessly with --dump-data (once per mod setting state) and
asserts on the resulting data.raw JSON:

  Setting off:
    - All surface_conditions are stripped (except explosions, so the atomic bomb keeps
      creating vanilla nuclear-ground on Nauvis instead of ammoniacal-ocean/lava).

  Setting on ("remove space platform restrictions" disabled):
    - Space platform exclusive prototypes (all condition minimums are 0) are kept verbatim.
    - Everything else is rewritten to {property="pressure", min<=300} without max, which
      every planetary surface satisfies (lowest planet pressure is Aquilo's 300, Nauvis
      resolves to an engine default of 1000) but space platforms (pressure 0) do not.

Usage:
    python3 tests/run_tests.py

Environment overrides:
    FACTORIO_BIN  path to the factorio executable (default /factorio/bin/x64/factorio)
    MOD_DIR       path to the mod source tree   (default repo root of this file)
"""

import json
import os
import re
import subprocess
import sys
import tempfile

FACTORIO_BIN = os.environ.get("FACTORIO_BIN", "/factorio/bin/x64/factorio")
MOD_DIR = os.environ.get("MOD_DIR",
                         os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

MOD_NAME = "EverythingOnNauvis-morganc"
SETTINGS_FILE = os.path.join(MOD_DIR, "settings.lua")

# (prototype type, name) tuples that are exclusive to space platforms in vanilla
PLATFORM_EXCLUSIVE = [
    ("assembling-machine", "crusher"),
    ("thruster", "thruster"),
    ("asteroid-collector", "asteroid-collector"),
    ("space-platform-hub", "space-platform-hub"),
    ("recipe", "space-science-pack"),
    ("recipe", "promethium-science-pack"),
    ("recipe", "thruster-fuel"),
    ("recipe", "thruster-oxidizer"),
    ("recipe", "advanced-thruster-fuel"),
    ("recipe", "advanced-thruster-oxidizer"),
]

# (prototype type, name) tuples that belong on planets in vanilla
PLANET_EXCLUSIVE = [
    ("recipe", "foundry"),
    ("recipe", "electromagnetic-plant"),
    # vanilla caps pressure at 600 (Aquilo's value, Nauvis is 1000) and sets no
    # minimum: the max-only shape the rewrite has to notice
    ("recipe", "quantum-processor"),
    ("recipe", "big-mining-drill"),
    ("recipe", "recycler"),
    # vanilla requires magnetic-field = 99 (Fulgora) here; Nauvis has none,
    # so these prove the property normalization works
    ("recipe", "lightning-rod"),
    ("recipe", "electromagnetic-science-pack"),
    # fuel-based furnaces and other burner-tier entities (vanilla ten_pressure_condition)
    ("furnace", "stone-furnace"),
    ("furnace", "steel-furnace"),
    ("mining-drill", "burner-mining-drill"),
    ("boiler", "boiler"),
    ("roboport", "roboport"),
    ("inserter", "burner-inserter"),
    # chests: regular and logistic (vanilla gives them gravity >= 0.1)
    ("container", "wooden-chest"),
    ("container", "iron-chest"),
    ("container", "steel-chest"),
    ("logistic-container", "passive-provider-chest"),
    ("logistic-container", "active-provider-chest"),
    ("logistic-container", "storage-chest"),
    ("logistic-container", "buffer-chest"),
    ("logistic-container", "requester-chest"),
    ("agricultural-tower", "agricultural-tower"),
]

failures = []


def check(label, condition, detail=""):
    status = "PASS" if condition else "FAIL"
    print(f"  [{status}] {label}" + (f" ({detail})" if detail and not condition else ""))
    if not condition:
        failures.append(f"{label}: {detail}")


def set_default_value(value):
    """Set EVERY default_value in settings.lua to <value>, regardless of the
    current literal. The old mechanism replaced only the first literal it found
    ("true"): with a mix of true and false defaults -- eon-nauvis2-clone is false --
    flipping "on" was a no-op for the false defaults and the nauvis2 asserts
    silently tested the wrong state. main() restores the file from a snapshot.
    """
    with open(SETTINGS_FILE) as f:
        content = f.read()
    flipped = content.replace("default_value = true", f"default_value = {value}")
    flipped = flipped.replace("default_value = false", f"default_value = {value}")
    with open(SETTINGS_FILE, "w") as f:
        f.write(flipped)


def run_dump_data(base_dir):
    """Runs factorio --dump-data with the mod enabled; returns parsed data.raw dict."""
    mods_dir = os.path.join(base_dir, "mods")
    write_dir = os.path.join(base_dir, "write")
    os.makedirs(mods_dir)
    os.makedirs(write_dir)

    # Symlink the mod into a clean mod directory (also acts as the user data dir,
    # so no stale mod-settings.dat can override the setting default).
    os.symlink(MOD_DIR, os.path.join(mods_dir, MOD_NAME))
    with open(os.path.join(mods_dir, "mod-list.json"), "w") as f:
        json.dump({"mods": [
            {"name": "base", "enabled": True},
            {"name": "elevated-rails", "enabled": True},
            {"name": "quality", "enabled": True},
            {"name": "space-age", "enabled": True},
            {"name": MOD_NAME, "enabled": True},
        ]}, f)

    config_path = os.path.join(base_dir, "config.ini")
    with open(config_path, "w") as f:
        f.write(f"[path]\nread-data=/factorio/data\nwrite-data={write_dir}\n")

    result = subprocess.run(
        [FACTORIO_BIN, "--dump-data", "--config", config_path,
         "--mod-directory", mods_dir],
        env={**os.environ, "HOME": base_dir},
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        text=True, timeout=900,
    )
    dump_path = os.path.join(write_dir, "script-output", "data-raw-dump.json")
    if not os.path.exists(dump_path):
        print(result.stderr[-2000:])
        raise RuntimeError("factorio did not produce data-raw-dump.json")
    with open(dump_path) as f:
        return json.load(f)


def get_condition_sets(data, entries):
    """Yields (type/name, conditions or None) for each entry, tolerating missing ones."""
    for type_name, name in entries:
        table = data.get(type_name, {})
        proto = table.get(name) if isinstance(table, dict) else None
        yield f"{type_name}/{name}", proto.get("surface_conditions") if proto else None


def is_platform_exclusive_set(conditions):
    """True if every condition is the vanilla platform-exclusive shape: min 0, max 0.

    The minimum must be present and 0: a max-only condition (quantum-processor caps
    pressure at 600, Aquilo's value) has no minimum and was read as platform-exclusive
    here, which is why its ceiling survived the rewrite and Nauvis could not craft it.
    """
    return bool(conditions) and all(
        c.get("min") == 0 and c.get("max") == 0 for c in conditions
    )


def is_planet_normalized_set(conditions):
    """True if rewritten correctly: any property, minimum clamped to (0, 1] or absent, no maximum."""
    return bool(conditions) and all(
        "max" not in c
        and (c.get("min") is None or 0 < c["min"] <= 1)
        for c in conditions
    )


# Entries whose vanilla condition must survive the rewrite unchanged in property,
# as (type, name, expected conditions). Documents the flavor-preserving behaviour.
PROPERTY_PRESERVED = [
    ("container", "wooden-chest", [{"property": "gravity", "min": 0.1}]),
    ("recipe", "lightning-rod", [{"property": "magnetic-field", "min": 1}]),
    ("recipe", "electromagnetic-science-pack", [{"property": "magnetic-field", "min": 1}]),
    ("furnace", "stone-furnace", [{"property": "pressure", "min": 1}]),
]


def test_setting_off(data):
    print("Setting off (restrictions removed):")
    for label, conditions in get_condition_sets(data, PLATFORM_EXCLUSIVE + PLANET_EXCLUSIVE):
        check(f"{label} has no surface_conditions", conditions is None, repr(conditions))

    explosions = data["explosion"]
    check("nuke-effects-aquilo is deleted (Aquilo no longer exists)",
          "nuke-effects-aquilo" not in explosions)
    check("nuke-effects-vulcanus is deleted (Vulcanus no longer exists)",
          "nuke-effects-vulcanus" not in explosions)
    check("nuke-effects-nauvis is kept",
          "nuke-effects-nauvis" in explosions)
    check("nuke-effects-space is kept with platform-only conditions",
          explosions["nuke-effects-space"].get("surface_conditions") ==
          [{"property": "pressure", "min": 0, "max": 0}])
    rocket_fx = data["projectile"]["atomic-rocket"]["action"]["action_delivery"]["target_effects"]
    rocket_entities = [e.get("entity_name") for e in rocket_fx
                       if e.get("type") == "create-entity"]
    check("atomic-rocket no longer references deleted nuke effects",
          "nuke-effects-aquilo" not in rocket_entities
          and "nuke-effects-vulcanus" not in rocket_entities,
          repr(rocket_entities))

    # nauvis2 (eon-nauvis2-clone on, as it is in this block -- the block runs with
    # every setting default flipped to true): the swap planet exists, is an exact
    # merged-map clone, and the solar-system edge points at it.
    planets = data.get("planet", {})
    nauvis2 = planets.get("nauvis2")
    check("nauvis2 planet exists (clone setting on)", nauvis2 is not None)
    if nauvis2 is not None:
        ac = (nauvis2.get("map_gen_settings") or {}).get("autoplace_controls", {})
        check("nauvis2 carries the merged map (vulcanus_volcanism control)",
              "vulcanus_volcanism" in ac, repr(list(ac)[:3]))
        check("nauvis2 keeps the merged map_gen_settings",
              nauvis2.get("map_gen_settings") is not None)
    # The dummy nauvis planet is stripped: the primary surface only stages a swap,
    # so it is generated as a cheap vanilla default map, not the merged program.
    check("dummy nauvis has no map_gen_settings (vanilla primary)",
          planets.get("nauvis", {}).get("map_gen_settings") is None)
    check("solar-system edge points at aquilo (restored trip graph)",
          data.get("space-connection", {}).get("aquilo-solar-system-edge", {}).get("from") == "aquilo")
    # eon-restore-space-locations is on in this block: the four planets are gone
    # as planets (deleted, not hidden) and re-added as unlandable space-locations,
    # and the vanilla interplanetary connections are back.
    other_planets = ["vulcanus", "gleba", "fulgora", "aquilo"]
    check("other planets are deleted as planet prototypes",
          not any(name in planets for name in other_planets))
    locations = data.get("space-location", {})
    check("all four planets exist as space-locations",
          all(name in locations for name in other_planets))
    connections = data.get("space-connection", {})
    check("vanilla interplanetary connections are restored",
          all(name in connections for name in
              ["nauvis-vulcanus", "nauvis-gleba", "nauvis-fulgora", "vulcanus-gleba",
               "gleba-fulgora", "gleba-aquilo", "fulgora-aquilo"]))
    # The original nauvis is the dummy: hidden from the starmap, and every
    # default_import_location swept onto the clone (remove-planets.lua pointed them
    # all at "nauvis", which no longer exists as a destination).
    check("original nauvis planet is hidden (it is the dummy)",
          bool(planets.get("nauvis", {}).get("hidden")))
    bad = [f"{t}/{n}" for t, table in data.items()
           if isinstance(table, dict)
           for n, p in table.items()
           if isinstance(p, dict) and p.get("default_import_location") is not None
           and p["default_import_location"] != "nauvis2"]
    check("all default_import_locations point at nauvis2", not bad, str(bad[:3]))


def test_setting_on(data):
    print("Setting on (space platform restrictions kept):")
    for label, conditions in get_condition_sets(data, PLATFORM_EXCLUSIVE):
        check(f"{label} kept verbatim (platform exclusive)",
              is_platform_exclusive_set(conditions), repr(conditions))

    for label, conditions in get_condition_sets(data, PLANET_EXCLUSIVE):
        check(f"{label} rewritten to clamped requirement",
              is_planet_normalized_set(conditions), repr(conditions))

    for type_name, name, expected in PROPERTY_PRESERVED:
        actual = data.get(type_name, {}).get(name, {}).get("surface_conditions")
        check(f"{type_name}/{name} keeps its property",
              actual == expected, repr(actual))

    # Global invariant over everything except explosions
    unclassified = []
    for type_name, table in data.items():
        if type_name == "explosion" or not isinstance(table, dict):
            continue
        for name, proto in table.items():
            if not isinstance(proto, dict):
                continue
            conditions = proto.get("surface_conditions")
            if conditions and not (is_platform_exclusive_set(conditions)
                                   or is_planet_normalized_set(conditions)):
                unclassified.append(f"{type_name}/{name}: {conditions}")
    check("no prototype outside explosions has unhandled surface_conditions",
          not unclassified, f"{len(unclassified)} found, e.g. {unclassified[:3]}")

    explosions = data["explosion"]
    check("nuke-effects-aquilo is deleted (Aquilo no longer exists)",
          "nuke-effects-aquilo" not in explosions)
    check("nuke-effects-vulcanus is deleted (Vulcanus no longer exists)",
          "nuke-effects-vulcanus" not in explosions)


    # nauvis2 (eon-nauvis2-clone off, as it is in this block): a vanilla freeplay
    # game stays a single-Nauvis game -- no clone planet, no rewire.
    planets = data.get("planet", {})
    check("nauvis2 planet absent (clone setting off)", "nauvis2" not in planets)
    check("solar-system edge points at nauvis",
          data.get("space-connection", {}).get("aquilo-solar-system-edge", {}).get("from") == "nauvis")
    # eon-restore-space-locations is off in this block: hidden planets, no
    # space-locations, no interplanetary routes.
    other_planets = ["vulcanus", "gleba", "fulgora", "aquilo"]
    check("other planets kept but hidden with no map_gen_settings",
          all(name in planets and planets[name].get("hidden") is True
              and not planets[name].get("map_gen_settings")
              for name in other_planets))
    locations = data.get("space-location", {})
    check("no restored space-locations",
          not any(name in locations for name in other_planets))
    connections = data.get("space-connection", {})
    check("interplanetary connections are deleted",
          not any(name in connections for name in
                  ["nauvis-vulcanus", "nauvis-gleba", "nauvis-fulgora", "vulcanus-gleba",
                   "gleba-fulgora", "gleba-aquilo", "fulgora-aquilo"]))
    # Freeplay: nothing is hidden and imports stay on the real nauvis.
    check("original nauvis planet is not hidden",
          not planets.get("nauvis", {}).get("hidden"))
    check("nauvis keeps the merged map_gen_settings (clone off, it is the live map)",
          planets.get("nauvis", {}).get("map_gen_settings") is not None)
    bad = [f"{t}/{n}" for t, table in data.items()
           if isinstance(table, dict)
           for n, p in table.items()
           if isinstance(p, dict) and p.get("default_import_location") is not None
           and p["default_import_location"] != "nauvis"]
    check("all default_import_locations point at nauvis", not bad, str(bad[:3]))


def test_mirror_invariants(data):
    """The invariants the runtime spot mirror holds by ASSUMPTION.

    These are not in noise-mirror/ because the mirror cannot check them: it runs at
    control stage, where the data-stage expression graph does not exist. Each one
    is a fact about a shipped prototype that the mirror depends on and cannot
    see, so the fact is checked here -- against the dump, which is the only place
    it is still text.

    noise-mirror/spot-candidates.lua first_accepted() returns the first draw of a
    region's candidate stream and stops. That is the engine's answer ONLY while
    candidate_spot_count is 1: with a count of 2 the engine would reject a
    candidate too close to the first and place the second, and the mirror would
    hand back the rejected one. It used to carry a comment claiming new_volcanoes()
    "refuses any configuration where the simplification would not hold" -- it
    refuses nothing, so the claim was doing the work the check does now.
    """
    print("Runtime mirror invariants (facts the mirror cannot see):")
    noise = data.get("noise-function", {})
    # eon_mountain_volcano_spots is deliberately NOT here: it is a FIELD that calls
    # eon_volcano_spots_at twice with different seeds, which is where the mirror's
    # two SYSTEMS come from. One prototype to hold the invariant.
    name = "eon_volcano_spots_at"
    expression = noise.get(name, {}).get("expression", "")
    found = re.search(r"candidate_spot_count\s*=\s*([^,\\]+)", expression)
    value = found.group(1).strip() if found else None
    check(f"{name} places one spot per region (the mirror's first-draw shortcut)",
          value == "1", f"candidate_spot_count = {value!r}")


def main():
    if set(os.listdir(MOD_DIR)) is None:
        sys.exit("mod source not found")
    # Snapshot settings.lua and restore it verbatim in all paths: the flip below
    # touches every default, and the old restore-only-what-was-flipped bookkeeping
    # twice left the file modified (first-occurrence replaces).
    original_settings = open(SETTINGS_FILE).read()
    try:
        with tempfile.TemporaryDirectory(prefix="eon-test-off.") as base_dir:
            set_default_value("true")
            test_setting_off(run_dump_data(base_dir))
        with tempfile.TemporaryDirectory(prefix="eon-test-on.") as base_dir:
            set_default_value("false")
            dumped = run_dump_data(base_dir)
            test_setting_on(dumped)
            test_mirror_invariants(dumped)
    finally:
        open(SETTINGS_FILE, "w").write(original_settings)

    print()
    if failures:
        print(f"{len(failures)} FAILURE(S)")
        sys.exit(1)
    print("All tests passed.")


if __name__ == "__main__":
    main()
