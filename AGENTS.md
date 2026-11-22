# AGENTS.md

Context for an AI model (or a human) working on this repository. Everything
here was measured on a real router; if you change something, measure it
again and update this file.

## What this repository is

A mihomo configuration for OpenClash on a router in Russia. The config
routes Russian traffic directly, blocked and foreign traffic through the
proxy, and everything else by rule-sets.

Target: Cudy WR3000S v1 (MT7981BA, 256 MB RAM, 128 MB NAND), OpenWrt
25.12.x, OpenClash v0.48.002, mihomo v1.19.33.

## The file that is the source of truth

`RU-Mihomo.yaml` is the only file that is edited by hand.

`RU-Mihomo-lite.yaml` and `RU-Mihomo-smart.yaml` are **generated**:

```sh
./scripts/make-lite.sh     # -> RU-Mihomo-lite.yaml   (no ad list)
./scripts/make-smart.sh    # -> RU-Mihomo-smart.yaml  (type: smart)
```

Never edit the generated files by hand - the next generation overwrites it.

## Before you commit

```sh
./scripts/selftest.sh
```

It runs `mihomo -t` on all three configs and checks the filters, the groups,
the rule targets and the rule-set files. A pull request that does not pass
it will not be merged.

## Rules that must not be broken

These are not style preferences, each of them has a reason that was measured.

1. **The filters live on the groups, never on the provider.** OpenClash
   rewrites `filter` and `exclude-filter` of every `proxy-provider` from its
   own UI and would silently disable the logic.
2. **`nameserver-policy` uses `'rule-set:ru-domains'`, never
   `geosite:category-ru`.** With the geosite variant the core downloads
   `GeoSite.dat` (4.3 MB) and keeps the geosite matcher in RAM: 86 MB RSS
   instead of 52 MB, and a start time of 4.6 s instead of 67 ms.
3. **`geo-auto-update: false`** and `ENABLE_GEOIP_DAT = 0` in
   `RU-Mihomo.conf`. `GeoIP.dat` is 16.5 MB and `GeoSite.dat` is 4.4 MB -
   21 MB of a 84.8 MB overlay that this config never reads.
4. **No `behavior: classical` with `format: mrs`.** Such a rule matches
   nothing and fails silently.
5. **No `\p{IsCyrillic}`.** It crashes mihomo v1.19.33 with a panic in the
   regexp compiler. Use `\x{...}` escapes (the file stays ASCII that way).
6. **The order of the rules is fixed.** The service groups come before the
   RKN list (Telegram, Discord and the AI services are on the RKN list too,
   otherwise their groups would be unreachable), the RKN list comes before
   the Russian domains (domains like `007dom.ru` would go DIRECT and around
   the block), and `custom-domains` comes above everything that comes from a
   list.
7. **`DASHBOARD_PASSWORD` must not be empty.** With an empty secret the
   API answers with `Access-Control-Allow-Origin: *` - any web page in the
   LAN can drive the proxy. OpenClash overwrites the `secret` in the YAML
   with the value from this option.
8. **No `external-ui-url`.** The core downloads that zip without checking
   the integrity. OpenClash ships its own dashboard.
9. **Do not add a top level `proxies:` block.** OpenClash deletes the
   entries of the group lists when a node filter is set in its UI, and the
   group lists of this config share one array through a YAML anchor.
10. **The proxy groups must not be created in the OpenClash UI.** OpenClash
    rebuilds the whole `proxy-groups:` block from its own storage and would
    overwrite the design of this config.
11. **Plain aliases only, no `<<:` merge keys.** Both work, but a plain
    alias is also readable for tools that do not implement merge keys.

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

`scripts/selftest.sh` checks that the noise part of `foreign-filter` is
still identical to `noise-filter`. If you change one of them, change the
other as well, or the check will fail.

A Russian exit IP does not unblock anything (the RKN blocks traffic by
Russian networks), so the automatic groups exclude the Russian nodes. They
are still reachable through `🎯 Manual`.

## Style

* `README.md` and `README-RU.md` describe the same thing in two
  languages. Keep them in sync when you change the installation steps.
* The file is UTF-8, but everything except the emoji in the group names is
  ASCII. The Russian words in the regexes are written as `\x{...}`.
* The group names carry an emoji and are quoted: `- name: "🚀 Auto"`.
* In the rules the group name is **not** quoted - mihomo would take the
  quotes as part of the name: `- RULE-SET,telegram,💬 Telegram`.
* Comments in the YAML are short. The long explanations live in
  `docs/DESIGN.md`, and every statement there has a measurement behind it.
* One subscription, `proxy-providers -> Main`. The URL is a placeholder
  (`PASTE_SUBSCRIPTION_URL_HERE`); OpenClash substitutes the real one.
* The shell scripts and the lists keep LF line endings (`.gitattributes`).
  A CRLF breaks them on the router.

## The rule-sets on the router

The rule-sets are local files and the router refreshes them itself with
`scripts/update-rulesets.sh` (its own cron, no secrets needed). The build
script tries the direct link first and then the mirrors - keep that order
when you add a source: `raw.githubusercontent.com` is not always fast from
Russia.

The scripts take the root of the repository from their own location (the
folder above `scripts/`), so on the router they keep the layout of the
repository: `/etc/openclash/scripts/` and `/etc/openclash/lists/` side by
side, the result in `/etc/openclash/ruleset/`. Copied flat into
`/etc/openclash/` the root becomes `/etc` and the build fails with
`/etc/lists/custom-domains.list not found`. `update-rulesets.sh` checks the
layout before it builds. If you add a file that the build reads from the
repository, install it on the router in the same relative place and say so in
`docs/INSTALL.md`.

OpenWrt has no `/etc/cron.d`: the cron job goes into the crontab of root
(`docs/INSTALL.md`, section 5.1).

## Adding a new service group

1. Add the rule-set to `scripts/build-ruleset.sh` (and to the download list
   of MetaCubeX if it exists there).
2. Add the `rule-provider` block to `RU-Mihomo.yaml`.
3. Add the group with the shared choice list (`proxies: *service-choices`).
4. Add the rule **in the service block**, before the RKN list.
5. Add the group to `scripts/check-groups.sh` and to `docs/GROUPS.md`.
6. Run `./scripts/build-ruleset.sh` and `./scripts/selftest.sh`.
