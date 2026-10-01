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
    """Flip default_value in settings.lua (restored by restore_default_value)."""
    with open(SETTINGS_FILE) as f:
        content = f.read()
    for literal in ("true", "false"):
        marker = f"default_value = {literal}"
        if marker in content:
            with open(SETTINGS_FILE, "w") as f:
                f.write(content.replace(marker, f"default_value = {value}"))
            return literal
    raise RuntimeError("could not find default_value in settings.lua")


def restore_default_value(old_literal):
    with open(SETTINGS_FILE) as f:
        content = f.read()
    with open(SETTINGS_FILE, "w") as f:
        f.write(content.replace(f"default_value = {not old_literal}".lower(),
                                f"default_value = {old_literal}"))


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
    """True if every condition has a minimum of 0 (vanilla platform-exclusive shape)."""
    return bool(conditions) and all((c.get("min") or 0) == 0 for c in conditions)


def is_planet_normalized_set(conditions):
    """True if rewritten correctly: any property, minimum clamped to (0, 1], no maximum."""
    return bool(conditions) and all(
        "max" not in c
        and 0 < (c.get("min") or 0) <= 1
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
    old_literal = None
    try:
        with tempfile.TemporaryDirectory(prefix="eon-test-off.") as base_dir:
            old_literal = set_default_value("true") or old_literal
            test_setting_off(run_dump_data(base_dir))
        set_default_value("false")
        try:
            with tempfile.TemporaryDirectory(prefix="eon-test-on.") as base_dir:
                dumped = run_dump_data(base_dir)
                test_setting_on(dumped)
                test_mirror_invariants(dumped)
        finally:
            restore_default_value(old_literal)
    finally:
        # Never leave a modified settings.lua behind
        content = open(SETTINGS_FILE).read()
        if "default_value = true" in content and old_literal == "false":
            set_default_value("false")

    print()
    if failures:
        print(f"{len(failures)} FAILURE(S)")
        sys.exit(1)
    print("All tests passed.")


if __name__ == "__main__":
    main()
