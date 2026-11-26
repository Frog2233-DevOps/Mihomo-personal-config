# AGENTS.md

Context for an AI model (or a human) working on this repository. Everything
here was measured on a real router; if you change something, measure it again
and update this file.

## What this repository is

The configuration of the core for the **mixomo** scheme on a router in Russia.
Only the traffic that MagiTrickle marked goes into the core, everything else
goes straight to the provider.

```
client -> MagiTrickle (DNS, marks the addresses of its lists)
       -> hev-socks5-tunnel (tun "Mihomo")
       -> mihomo (mixed-port 7890) -> the node
```

Target: Cudy WR3000S v1 (MT7981BA, 239 MB RAM + 131 MB swap), OpenWrt
25.12.6, mixomo v0.3.4, MagiTrickle 0.8.2, hev-socks5-tunnel 2.20.0, mihomo
v1.19.34.

The layout that sends *everything* through the core (OpenClash) is not in
`main` any more - it is in the branch `legacy/openclash`. Do not merge it
back: the two layouts are different schemes, not two variants of one.

## The files that are edited by hand

| File | What it is |
|---|---|
| `RU-Mihomo-mixomo.yaml` | the config of the core - the only config file of the scheme |
| `magitrickle/magitrickle.yaml` | the template of the state of MagiTrickle: the groups and the subscriptions |
| `magitrickle/magitrickle.mtrickle` | the same groups in the JSON format of the web interface |
| `lists/custom-domains.list` | your own domains |
| `lists/bypass-ports.list` | the ports that must not touch the core |

Everything else is generated:

* `ruleset/*.mrs` - built by `scripts/build-ruleset.sh`, never by hand (they
  are binary files).
* `/etc/magitrickle/state/config.yaml` - the state of the service, built by
  `scripts/gen-mtrickle.sh` from the template and from the rule-sets.

There is no "lite" and no "smart" variant any more. The lite variant was
measured on the router and removed: the core with the full config keeps
**60.7 MB** of RSS, with the lite one **60.8 MB** (three runs each) - there is
no saving, so the variant was not worth the extra file.

## Before you commit

```sh
bash scripts/selftest.sh
bash tests/run-all.sh
```

`selftest.sh` runs `mihomo -t` on the config of the scheme, checks that every
script of the router is POSIX `sh` and is happy with `shellcheck`, and runs the
consistency checks of `selftest.py` (the groups, the rule targets, the
rule-set files, the settings that the scheme forces, the order of the rules,
the state of MagiTrickle). `tests/run-all.sh` adds the tests of the scheme
itself: the config, the groups, the state file, the rehearsal of the
installation.

A pull request that does not pass both will not be merged.

With a real router the full cycle can be checked as well - the rehearsal of
the installation is `tests/10_mixomo_rehearsal.sh` (it needs root, it writes
into a directory of its own and it replaces the services with fakes).

CI runs both on every pull request (`.github/workflows/validate.yml`).

## Rules that must not be broken

These are not style preferences, each of them has a reason that was measured.

1. **The filters live on the groups, never on the provider.** A provider-level
   filter hits every group that uses the provider, and the groups need
   different filters: the automatic groups exclude the Russian nodes, the
   manual group keeps them.
2. **`nameserver-policy` uses `'rule-set:ru-domains'`, never
   `geosite:category-ru`.** With the geosite variant the core downloads
   `GeoSite.dat` (4.3 MB) and keeps the geosite matcher in RAM: 86 MB RSS
   instead of 52 MB, and a start time of 4.6 s instead of 67 ms.
3. **`geo-auto-update: false`** and no `GeoIP.dat` / `GeoSite.dat` in the
   layout of the scheme. They are 16.5 + 4.4 MB that this config never
   reads.
4. **No `behavior: classical` with `format: mrs`.** Such a rule matches
   nothing and fails silently.
5. **No `\p{IsCyrillic}`.** It crashes mihomo v1.19.33 with a panic in the
   regexp compiler. Use `\x{...}` escapes (the file stays ASCII that way).
6. **The order of the rules is fixed.** The service groups come before the
   RKN list (Telegram, Discord and the AI services are on the RKN list too,
   otherwise their groups would be unreachable), the RKN list comes before
   the Russian domains (domains like `007dom.ru` would go DIRECT and around
   the block), and `custom-domains` comes above everything that comes from a
   list. The rule of `games` stands above the RKN list: 121 of its domains
   are on the RKN list and 51 on the Roblox list.
7. **`DASHBOARD_PASSWORD` must not be empty.** With an empty secret the API
   answers with `Access-Control-Allow-Origin: *` - any web page in the LAN
   can drive the proxy. `scripts/setup-mixomo.sh` refuses an empty value and
   never prints it.
8. **No `external-ui-url`.** The core downloads that zip without checking
   the integrity.
9. **The settings of the scheme must not be "improved".** `mixed-port` has to
   be 7890 (the installer of mixomo keeps a config only with that port),
   `enhanced-mode` has to be `redir-host` (with fake-ip the client sends
   **all** of its traffic to 198.18.0.0/16, and only the marked addresses
   reach the core - the rest would leave the router towards a fake address),
   the rule-sets belong in `./rule-files/` and the providers in
   `./proxy-providers/`.
10. **The ad list is deliberately not in the core.** MagiTrickle drops it with
    the interface `blackhole`, which keeps ~110 000 domains out of the RAM of
    the core and out of its rule matching.
11. **The state of MagiTrickle has to work with both builds.** The original
    build and the mod build read `dnsProxy.timeout` and
    `netfilter.ipset.additionalTTL` differently (a duration against a number
    of seconds). Do not set these fields: use the default of the build. The
    `configVersion` has to start with `0.1.` - the mod build rejects
    anything else, the original build accepts everything that starts with
    `0.`.
12. **A service that is not on a list of MagiTrickle never reaches the core.**
    The rules of the core only decide what happens to the traffic that was
    selected. When a service has to go through the proxy, it needs a list in
    MagiTrickle - a rule in `RU-Mihomo-mixomo.yaml` alone changes nothing.
13. **The ports that bypass the core use ACCEPT, not RETURN.** In the mangle
    table a `RETURN` from a chain only means "back to PREROUTING and keep
    looking": a packet that MagiTrickle already marked would stay marked and
    would still go into the core. `ACCEPT` ends the traversal of the table,
    the packet keeps its normal route. The chain of
    `scripts/bypass-ports.sh` is hooked into `PREROUTING` in the first
    position, because the chains of MagiTrickle are inserted there too - and
    MagiTrickle restores the position of its own chains after a restart by
    the rules around them, so a rule of ours in front of them stays in front
    of them.
14. **Do not put `no-resolve` on the `private` rule.** The `private` rule-set
    is an IP list; matching a domain against it needs a resolution. With
    `no-resolve` a local host by name stops matching it and is sent to the
    proxy instead - measured: `nas.test` -> `192.168.1.10` gives
    `match RuleSet(private) using DIRECT` without the option and
    `match Match using PROXY` with it. The option was measured and rejected.
15. **The domain normalizer must accept hyphens.** `scripts/build-ruleset.sh`
    uses `^[A-Za-z0-9_.-]+$` for a bare domain. Removing `-` silently drops
    valid entries (`01-klinika-21.ru`, `xn--...`): measured 20 833 of 82 146
    lines lost from the RKN list on 2026-11-23.
16. **The scripts of the router must not depend on one downloader.** A plain
    OpenWrt has only `uclient-fetch` and `wget`, mixomo installs `curl`.
    Choose the downloader at runtime; the daily cron runs unattended.
17. **A process search must not find the script itself.** `apply-rulesets.sh`
    looks for the config of the running core. The first command line that
    contains "clash" or "mihomo" is not necessarily the core. Take the first
    line that contains `-f ` **and** whose file exists.
18. **`check-groups.sh` must validate the API answer.** A 401 body is not an
    empty answer: without a `"proxies"` check every group was printed as
    `NOT FOUND` and the warnings reported a false `OK`. The `uclient-fetch`
    fallback must pass `--header="Authorization: Bearer ..."`.
19. **Every script that goes to the router is POSIX `sh`.** The router runs
    busybox ash, there is no bash there. `scripts/selftest.sh` checks every
    file of `scripts/` with `sh -n` and with `shellcheck -s sh`.
20. **The secret and the address of the API are read out of the config of the
    scheme** (`/etc/mihomo/config.yaml`), because that is the file the core
    runs with. Keep `apply-rulesets.sh` and `check-groups.sh` POSIX `sh`.
21. **The router refreshes the lists on its own.** The daily GitHub rebuild
    only commits files to the repository - without the router secrets it never
    reaches the device. `scripts/setup-mixomo.sh` therefore adds the
    `update-mixomo.sh` line (05:30) to the crontab of root, preserving the
    other entries and avoiding duplicates; `ENABLE_CRON=0` opts out.
    OpenWrt has no `/etc/cron.d`.
22. **`ruleset/*.mrs` are never written by hand.** They are binary files that
    `scripts/build-ruleset.sh` builds and the workflow `rulesets.yml` commits.
23. **No secrets in the repository.** The subscription URL and the dashboard
    password are placeholders (`PASTE_SUBSCRIPTION_URL_HERE`, `CHANGE_ME`) and
    are substituted by `scripts/setup-mixomo.sh`. Neither the URL nor the
    password may ever be printed into a log, a commit or a document.
24. **The state of MagiTrickle is generated, the template is not.**
    `magitrickle/magitrickle.yaml` holds the app section and the
    subscriptions; `scripts/gen-mtrickle.sh` builds the groups out of the
    rule-sets and writes `/etc/magitrickle/state/config.yaml`. The groups in
    the template are the *template*, the local groups (Custom, Streaming, AI,
    GitHub, Steam) are built from the rule-sets.
25. **The layout on the router is `/etc/mihomo`.** The config is
    `/etc/mihomo/config.yaml`, the rule-sets are in `/etc/mihomo/rule-files/`,
    the scripts in `/etc/mihomo/scripts/`, the lists in `/etc/mihomo/lists/`,
    the state of MagiTrickle in `/etc/magitrickle/state/config.yaml`. The
    scripts take the root from their own location, so they keep the layout of
    the repository - copied flat into `/etc/mihomo/` the root becomes `/etc`
    and the build fails with `/etc/lists/custom-domains.list not found`.

## The DNS scheme

* DoH by IP (`1.1.1.1`, `9.9.9.9`) - a hostname needs a resolver in the
  first place.
* The proxy servers are resolved directly (`77.88.8.8`), otherwise the
  subscription never loads.
* `respect-rules: true` needs a non-empty `proxy-server-nameserver`,
  otherwise the core refuses to start.
* `fake-ip-filter` accepts DOMAIN rule-sets only.

## The node filters

Two regexes in the `x-fragments` block:

* `noise-filter` - LTE/4G servers and the subscription info nodes.
* `foreign-filter` - `noise-filter` plus the Russian markers.

`scripts/selftest.py` checks that the noise part of `foreign-filter` is
still identical to `noise-filter`. If you change one of them, change the
other as well, or the check will fail.

A Russian exit IP does not unblock anything (the RKN blocks traffic by
Russian networks), so the automatic groups exclude the Russian nodes. They
are still reachable through `🎯 Manual`.

## Style

* `README.md` and `README-RU.md` describe the same thing in two languages.
  Keep them in sync when you change the installation steps.
* The documents come in pairs: `docs/MIXOMO.md` and `docs/MIXOMO-RU.md`.
  Change both.
* The file is UTF-8, but everything except the emoji in the group names is
  ASCII. The Russian words in the regexes are written as `\x{...}`.
* The group names carry an emoji and are quoted: `- name: "🚀 Auto"`.
* In the rules the group name is **not** quoted - mihomo would take the
  quotes as part of the name: `- RULE-SET,telegram,💬 Telegram`.
* Comments in the YAML are short. The long explanations live in
  `docs/MIXOMO.md`, and every statement there has a measurement behind it.
* One subscription, `proxy-providers -> Main`. The URL is a placeholder.
* The shell scripts and the lists keep LF line endings (`.gitattributes`).
  A CRLF breaks them on the router.
* A test that compares a multi-byte string with `grep` has to set
  `LC_ALL=C`: the byte comparison is the same on every system, and GNU grep
  in a UTF-8 locale is not (measured on MSYS: the pattern with an emoji does
  not match under `LC_ALL=C.UTF-8` and matches under `LC_ALL=C`).
* A test that needs a program that may be missing (`ruby`, `python3`) has to
  check it with `command -v` first and **skip**, not fail.

## The rule-sets on the router

The rule-sets are local files and the router refreshes them itself with
`scripts/update-mixomo.sh` (its own cron, no secrets needed). The build
script tries the direct link first and then the mirrors - keep that order
when you add a source.

`scripts/update-mixomo.sh` does three things: it rebuilds the rule-sets, it
rebuilds the state of MagiTrickle and it tells the core to read the new
files. The reload through the API keeps the connections alive; when it fails
the core is restarted.

## Applying the rule-sets

The core reads the rule-sets when it loads the config, so a new list is not
in use until the core is told to read it again. `scripts/apply-rulesets.sh`
does that, and it has four modes:

| `APPLY=` | What happens |
|---|---|
| `reload` (default) | `PUT /configs?force=true` on the running core: it reloads its config and reads the new files, the proxy stays up. Measured: the rule count of a provider changes without a restart. |
| `restart` | `/etc/init.d/mihomo restart`. The fallback when the reload fails. |
| `none` | Nothing. The lists are used after the next restart. |
| `check` | Only looks: how many rule-providers the core has and how many rules. |

## Adding a new service group

1. Add the rule-set to `scripts/build-ruleset.sh` (and to the download list
   of MetaCubeX if it exists there).
2. Add the `rule-provider` block to `RU-Mihomo-mixomo.yaml`.
3. Add the group with the shared choice list (`proxies: *service-choices`).
4. Add the rule **in the service block**, before the RKN list.
5. Add the group to `scripts/check-groups.sh` (the groups are read out of the
   config of the scheme, the built-in list is only the fallback).
6. Add the subscription of the service to `magitrickle/magitrickle.yaml` -
   without it the traffic of the service never reaches the core.
7. Run `./scripts/build-ruleset.sh` and `./scripts/selftest.sh`.
