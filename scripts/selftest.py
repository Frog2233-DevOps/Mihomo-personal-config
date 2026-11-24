#!/usr/bin/env python3
"""selftest.py - consistency checks for the RU-Mihomo configuration.

No external modules, so it runs anywhere python3 is available.

Checks:
  1. the noise part of foreign-filter is identical to noise-filter
  2. every group used in the rules exists
  3. every member of a group exists (a group or DIRECT/REJECT)
  4. every provider used by a group exists
  5. every rule-set file exists in ruleset/
  6. the generated variants are really the generated variants
  7. no bare YAML 1.1 booleans where a string is meant (ruby/Psych would
     turn "off" into false and the core would refuse to start)
  8. automation/*.yml matches .github/workflows/*.yml (fix-exec.sh copies
     the former over the latter, so a drift silently reverts CI fixes)
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILTIN = {"DIRECT", "REJECT", "REJECT-DROP", "PASS", "COMPATIBLE", "GLOBAL"}
fail = []


def read(name):
    with open(os.path.join(ROOT, name), encoding="utf-8") as fh:
        return fh.read()


def parse(text):
    """A small parser for the parts of the file we need."""
    out = {
        "groups": [],      # [{"name":..., "proxies": [...], "use": [...]}]
        "rules": [],
        "providers": [],
        "rule_provider_paths": [],
        "fragments": {},   # alias -> list of items
        "anchors": {},     # alias -> scalar value
    }
    section = None
    group = None
    mode = None          # "proxies" | "use" | None
    frag = None
    in_frag = None

    for raw in text.split("\n"):
        if not raw.strip() or raw.strip().startswith("#"):
            continue

        # top level key
        top = re.match(r"^([A-Za-z0-9_-]+):\s*(.*)$", raw)
        if top and not raw.startswith(" "):
            section = top.group(1)
            group = None
            mode = None
            frag = None
            in_frag = None
            continue

        if section == "x-fragments":
            m = re.match(r"^  ([A-Za-z0-9_-]+): &([A-Za-z0-9_-]+)\s*(.*)$", raw)
            if m:
                frag = m.group(1)
                in_frag = m.group(1)
                out["anchors"][m.group(2)] = m.group(3).strip()
                if m.group(3).strip():
                    out["fragments"][frag] = []
                    in_frag = None
                continue
            if in_frag:
                item = raw.strip()
                if item.startswith("- "):
                    out["fragments"].setdefault(in_frag, []).append(item[2:].strip().strip("'\""))
                    continue
                in_frag = None

        if section == "proxy-providers":
            m = re.match(r"^  ([A-Za-z0-9_-]+):\s*$", raw)
            if m:
                out["providers"].append(m.group(1))
            continue

        if section == "rule-providers":
            m = re.match(r"^\s+path: (\S+)$", raw)
            if m:
                out["rule_provider_paths"].append(m.group(1))
            continue

        if section == "proxy-groups":
            m = re.match(r'^  - name: "([^"]+)"', raw)
            if m:
                group = {"name": m.group(1), "proxies": [], "use": []}
                out["groups"].append(group)
                mode = None
                continue
            if group is None:
                continue
            m = re.match(r"^    (proxies|use):\s*(.*)$", raw)
            if m:
                mode = m.group(1)
                value = m.group(2).strip()
                if value.startswith("*"):
                    alias = value[1:]
                    out[mode] = []
                    group[mode] = out["fragments"].get(alias, [])
                    if not group[mode]:
                        group[mode] = ["*" + alias]
                elif value:
                    group[mode] = [value.strip("'\"")]
                continue
            m = re.match(r"^      - (.+)$", raw)
            if m and mode:
                group[mode].append(m.group(1).strip().strip("'\""))
                continue
            if re.match(r"^    [A-Za-z0-9_-]+:", raw):
                mode = None
            continue

        if section == "rules":
            m = re.match(r"^  - (.+)$", raw)
            if m:
                out["rules"].append(m.group(1).strip())
            continue

    return out


main = read("RU-Mihomo.yaml")
cfg = parse(main)
names = [g["name"] for g in cfg["groups"]]

# --- 1. the filters ---------------------------------------------------------
def anchor_value(alias):
    m = re.search(r"^\s+[A-Za-z0-9_-]+: &%s\s+(.*)$" % re.escape(alias), main, re.M)
    return m.group(1).strip() if m else None


noise = anchor_value("noise-filter")
foreign = anchor_value("foreign-filter")
if not noise or not foreign:
    fail.append("the anchors noise-filter / foreign-filter were not found")
else:
    def inner(value):
        value = value.strip("'\"")
        value = re.sub(r"^\(\?i\)", "", value)
        return value.strip("()")
    if inner(noise) not in inner(foreign):
        fail.append("foreign-filter does not contain the noise part of noise-filter")
    else:
        print("  OK   foreign-filter contains the noise part of noise-filter")

# --- 2. the groups used in the rules exist -----------------------------------
targets = set()
for rule in cfg["rules"]:
    targets.add(rule.split(",")[-1].strip())
missing = sorted(t for t in targets if t not in names and t not in BUILTIN)
if missing:
    fail.append("groups used in the rules but not defined: %s" % ", ".join(missing))
else:
    print("  OK   all %d rule targets exist" % len(targets))

# --- 3./4. the members of the groups -----------------------------------------
for group in cfg["groups"]:
    for member in group["proxies"]:
        if member.startswith("*"):
            fail.append("group '%s' refers to an unresolved alias '%s'"
                        % (group["name"], member))
        elif member not in names and member not in BUILTIN:
            fail.append("group '%s' refers to an unknown member '%s'"
                        % (group["name"], member))
    for provider in group["use"]:
        if provider not in cfg["providers"]:
            fail.append("group '%s' refers to an unknown provider '%s'"
                        % (group["name"], provider))
if not any("unknown member" in f or "unknown provider" in f or "alias" in f for f in fail):
    print("  OK   every group member and every provider exists")

# --- 5. the rule-set files exist ---------------------------------------------
for path in cfg["rule_provider_paths"]:
    if not os.path.exists(os.path.join(ROOT, path.lstrip("./"))):
        fail.append("missing rule-set file: %s" % path)
if not any("missing rule-set file" in f for f in fail):
    print("  OK   every rule-set file exists (%d)" % len(cfg["rule_provider_paths"]))

# --- 6. the generated variants -----------------------------------------------
lite = read("RU-Mihomo-lite.yaml")
if "antiad" in lite:
    fail.append("RU-Mihomo-lite.yaml still references antiad")
else:
    print("  OK   the lite variant has no antiad")

smart = read("RU-Mihomo-smart.yaml")
if "type: smart" not in smart:
    fail.append("RU-Mihomo-smart.yaml has no smart group")
else:
    print("  OK   the smart variant has a smart group")

# --- 7. no bare YAML 1.1 booleans where a string is meant ---------------------
# OpenClash rewrites the config with ruby (Psych) at every start, and Psych
# reads a bare "off" / "on" / "yes" / "no" as a boolean. A value like
# find-process-mode: off would become false and the core would refuse to
# start. Every such value has to be quoted.
BARE_BOOL = re.compile(r"^\s*[A-Za-z0-9_-]+:\s+(on|off|yes|no|y|n|true|false)\s*(#.*)?$")
for name in ("RU-Mihomo.yaml", "RU-Mihomo-lite.yaml", "RU-Mihomo-smart.yaml"):
    for i, line in enumerate(read(name).split("\n"), 1):
        m = BARE_BOOL.match(line)
        if m and m.group(1) in ("on", "off", "yes", "no", "y", "n"):
            fail.append("%s:%d: bare '%s' - quote it, ruby reads it as a boolean"
                        % (name, i, m.group(1)))
if not any("bare '" in f for f in fail):
    print("  OK   no bare YAML 1.1 booleans (ruby would turn them into false)")

# --- 8. the workflow copies --------------------------------------------------
# fix-exec.sh (and its PowerShell twin) copies automation/*.yml on top of
# .github/workflows/*.yml. If the copies drift, following the documented
# "fix" silently reverts changes made to the real workflows.
workflows = os.path.join(ROOT, ".github", "workflows")
automation = os.path.join(ROOT, "automation")
if os.path.isdir(workflows) and os.path.isdir(automation):
    drift = []
    for name in sorted(os.listdir(workflows)):
        if not name.endswith(".yml"):
            continue
        canonical = os.path.join(workflows, name)
        copy = os.path.join(automation, name)
        if not os.path.isfile(copy):
            drift.append("%s (missing in automation/)" % name)
            continue
        with open(canonical, "rb") as fh:
            left = fh.read()
        with open(copy, "rb") as fh:
            right = fh.read()
        if left != right:
            drift.append(name)
    if drift:
        fail.append("workflow copies differ: %s - sync automation/ with .github/workflows/"
                    % ", ".join(drift))
    else:
        print("  OK   automation/*.yml matches .github/workflows/*.yml")

print()
if fail:
    print("FAILED:")
    for item in fail:
        print("  - %s" % item)
    sys.exit(1)
print("All checks passed.")
