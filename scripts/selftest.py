#!/usr/bin/env python3
"""selftest.py - consistency checks for the mixomo configuration.

No external modules, so it runs anywhere python3 is available.

Checks:
  1. the noise part of foreign-filter is identical to noise-filter
  2. every group used in the rules exists
  3. every member of a group exists (a group or DIRECT/REJECT)
  4. every provider used by a group exists
  5. every rule-provider file exists in ruleset/
  6. the settings that the scheme forces: mixed-port 7890, redir-host, the
     rule-sets in ./rule-files/, the ad list NOT in the core, the DNS policy
     on the local rule-set
  7. the order of the rules: custom-domains and games above the RKN list,
     the Russian domains below it
  8. no bare YAML 1.1 booleans where a string is meant
  9. the state of MagiTrickle: configVersion 0.1.*, the ad list on the
     interface blackhole, the RKN lists on raw.githubusercontent.com
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILTIN = {"DIRECT", "REJECT", "REJECT-DROP", "PASS", "COMPATIBLE", "GLOBAL"}
fail = []

CFG = "RU-Mihomo-mixomo.yaml"
MT = "magitrickle/magitrickle.yaml"


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


main = read(CFG)
cfg = parse(main)
names = [g["name"] for g in cfg["groups"]]


def check(ok, message):
    """Print the result of one check and remember the failures."""
    if ok:
        print("  OK   %s" % message)
    else:
        fail.append(message)


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
    check(inner(noise) in inner(foreign),
          "foreign-filter contains the noise part of noise-filter")

# --- 2. the groups used in the rules exist -----------------------------------
targets = set()
for rule in cfg["rules"]:
    targets.add(rule.split(",")[-1].strip())
missing = sorted(t for t in targets if t not in names and t not in BUILTIN)
check(not missing,
      "all %d rule targets exist%s"
      % (len(targets), ("" if not missing else " (missing: %s)" % ", ".join(missing))))

# --- 3./4. the members of the groups -----------------------------------------
member_problems = []
for group in cfg["groups"]:
    for member in group["proxies"]:
        if member.startswith("*"):
            member_problems.append("group '%s' refers to an unresolved alias '%s'"
                                   % (group["name"], member))
        elif member not in names and member not in BUILTIN:
            member_problems.append("group '%s' refers to an unknown member '%s'"
                                   % (group["name"], member))
    for provider in group["use"]:
        if provider not in cfg["providers"]:
            member_problems.append("group '%s' refers to an unknown provider '%s'"
                                   % (group["name"], provider))
check(not member_problems,
      "every group member and every provider exists%s"
      % ("" if not member_problems else " (%s)" % "; ".join(member_problems)))

# --- 5. the rule-set files exist ---------------------------------------------
# The config of the scheme points to ./rule-files/ (the directory of mixomo on
# the router), the repository keeps the compiled files in ruleset/.
missing_files = []
for p in cfg["rule_provider_paths"]:
    name = os.path.basename(p)
    if not os.path.exists(os.path.join(ROOT, "ruleset", name)):
        missing_files.append(p)
check(not missing_files,
      "every rule-set file exists (%d)%s"
      % (len(cfg["rule_provider_paths"]),
         ("" if not missing_files else " (missing: %s)" % ", ".join(missing_files))))

# --- 6. the settings that the scheme forces ---------------------------------
# The mixomo installer keeps a config only with this port, and the scheme
# needs redir-host: with fake-ip the client sends ALL of its traffic to
# 198.18.0.0/16 and only the marked addresses reach the core - the rest
# would leave the router towards a fake address.
port = re.search(r"^mixed-port:\s*(\S+)", main, re.M)
check(bool(port) and port.group(1) == "7890",
      "mixed-port is 7890 (got: %s)" % (port.group(1) if port else "nothing"))

mode = re.search(r"^\s+enhanced-mode:\s*(\S+)", main, re.M)
check(bool(mode) and mode.group(1) == "redir-host",
      "enhanced-mode is redir-host (got: %s)" % (mode.group(1) if mode else "nothing"))

wrong_path = [p for p in cfg["rule_provider_paths"] if not p.startswith("./rule-files/")]
check(not wrong_path,
      "every rule-set is in ./rule-files/%s"
      % ("" if not wrong_path else " (wrong: %s)" % ", ".join(wrong_path)))

# The ad list is dropped by MagiTrickle (the interface blackhole), it is not
# in the core of this layout: that keeps ~110 000 domains out of its RAM.
ad_in_core = [p for p in cfg["rule_provider_paths"] if "anti-ad" in p or "antiad" in p]
check(not ad_in_core,
      "the ad list is not in the core%s"
      % ("" if not ad_in_core else " (%s)" % ", ".join(ad_in_core)))

# Without the provider of the Russian domains the core does not start at all.
check("'rule-set:ru-domains'" in main or '"rule-set:ru-domains"' in main,
      "the DNS policy uses the local rule-set ru-domains")

# --- 7. the order of the rules -----------------------------------------------
def rule_index(name):
    for i, rule in enumerate(cfg["rules"]):
        if rule.startswith("RULE-SET,%s," % name):
            return i
    return -1


custom = rule_index("custom-domains")
rkn = rule_index("rkn-blocked")
ru = rule_index("ru-domains")
games = rule_index("games")

check(custom >= 0 and rkn >= 0 and custom < rkn,
      "custom-domains stands above the RKN list")
check(games >= 0 and rkn >= 0 and games < rkn,
      "the rule of games stands above the RKN list (121 domains are on both)")
check(ru >= 0 and rkn >= 0 and ru > rkn,
      "the Russian domains stand below the RKN list")

# --- 8. no bare YAML 1.1 booleans where a string is meant --------------------
# YAML 1.1 reads a bare "off" / "on" / "yes" / "no" as a boolean. A value like
# find-process-mode: off would become false and the core would refuse to
# start. Every such value has to be quoted.
BARE_BOOL = re.compile(r"^\s*[A-Za-z0-9_-]+:\s+(on|off|yes|no|y|n|true|false)\s*(#.*)?$")
bare = []
for i, line in enumerate(main.split("\n"), 1):
    m = BARE_BOOL.match(line)
    if m and m.group(1) in ("on", "off", "yes", "no", "y", "n"):
        bare.append("%s:%d: bare '%s'" % (CFG, i, m.group(1)))
check(not bare, "no bare YAML 1.1 booleans%s"
      % ("" if not bare else " (%s)" % "; ".join(bare)))

# --- 9. the state of MagiTrickle ---------------------------------------------
mt = read(MT)

version = re.search(r"^configVersion:\s*['\"]?([^'\"\s]+)", mt, re.M)
check(bool(version) and version.group(1).startswith("0.1."),
      "the state of MagiTrickle has the configVersion 0.1.* (got: %s)"
      % (version.group(1) if version else "nothing"))

# The ad list must be dropped by the router, not by the core.
ad_block = re.search(r'name:\s*"[^"]*Anti-AD"\s*\n\s*interface:\s*(\S+)', mt)
check(bool(ad_block) and ad_block.group(1) == "blackhole",
      "the ad list of MagiTrickle is on the interface blackhole (got: %s)"
      % (ad_block.group(1) if ad_block else "nothing"))

# The lists are fetched from raw.githubusercontent.com and not from the assets
# of the releases of github.com. The assets are not always published (the
# asset "community.lst" is not there at all - measured: 404), and the file
# of the branch is the same file (measured: the same md5).
release_urls = re.findall(r"url:\s*(\S*github\.com/\S*releases\S*)", mt)
check(not release_urls,
      "the lists of MagiTrickle are not fetched from the releases of github.com"
      + (": %s" % ", ".join(release_urls) if release_urls else ""))

# Every list has to be on a raw address or on a mirror of one.
list_urls = re.findall(r"url:\s*(\S+)", mt)
bad_urls = [u for u in list_urls
            if not (u.startswith("https://raw.githubusercontent.com/")
                    or u.startswith("https://cdn.jsdelivr.net/gh/"))]
check(not bad_urls,
      "every list of MagiTrickle is fetched from raw.githubusercontent.com"
      + (": %s" % ", ".join(bad_urls) if bad_urls else ""))

print()
if fail:
    print("FAILED:")
    for item in fail:
        print("  - %s" % item)
    sys.exit(1)
print("All checks passed.")
