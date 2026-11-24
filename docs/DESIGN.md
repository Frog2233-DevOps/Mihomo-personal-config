# Design notes

**English** | [Русский](DESIGN-RU.md)

Every statement in this file was measured, not read from a README. Where a
number is given, this is how it was obtained.

The measurements were taken on a **Cudy WR3000S v1** (MT7981BA, 2x Cortex-A53
1.3 GHz, 256 MB RAM, 128 MB NAND, 5x1 GbE) with OpenWrt 25.12.5, the
`ubootmod` firmware layout and OpenClash v0.48.002. The core was the real
`mihomo-linux-arm64 v1.19.33`, running in an emulator of the same SoC
(QEMU, machine `mt7981-router`), not on a PC.

---

## 1. The router and its limits

| | |
|---|---|
| RAM | 256 MB, `zram` 168 MB (compressed swap, not extra RAM) |
| Flash | 128 MB NAND |
| Overlay (standard layout) | 44 MB - **not enough** |
| Overlay (ubootmod layout) | 84.8 MB - this is the one to use |

The `mihomo` arm64 binary is 57.5 MB on disk and takes 25-29 MB in UBIFS.
Together with OpenClash (10.7 MB), ruby and the rule-sets (1.5 MB) the
standard layout does not fit. The `ubootmod` layout gives ~50 MB more.

`zram` does not give mihomo more memory: the 52 MB of the core have to be
resident all the time. `zram` only saves the peaks - the ruby rewrite at
startup, the unpacked core in `/tmp` (`/tmp` is a tmpfs, so that is RAM).

### Measured RAM

| Configuration | RSS |
|---|---|
| bare core, no config | ~45 MB |
| lite config, 154 nodes | **52.2 MB** |
| full config (with the ad list) | 57.8 MB |
| `GOMEMLIMIT=64MiB GOGC=50` | 53 MB (no real gain, a safety net) |

`MemTotal` in the emulator was 239 568 kB, `MemAvailable` after the start was
around 100 MB. The lite variant fits comfortably.

---

## 2. What OpenClash does to the config

`yml_change.sh` is 946 lines of ruby. On every start it rewrites:

* DNS (`enable`, `listen`, `enhanced-mode`, the nameservers)
* `fake-ip-filter`
* `hosts`
* `sniffer`
* `authentication` (from its own UCI section)
* `external-controller` (`0.0.0.0:<cn_port>`) and `secret` (from
  `dashboard_password`)
* `allow-lan`, `bind-address`

It does **not** rewrite `proxy-groups`. It only reads the group names and
imports them into its own storage (`uci.rb`, `import_groups`).

What it *does* rewrite silently:

* `config_cus_up` overwrites `filter` and `exclude-filter` of every
  `proxy-provider` from the node filter in the OpenClash UI. **Therefore all
  filters in this config live on the groups, never on the provider.**
* `yml_rules_change.sh` can overwrite `tolerance`, `interval` and `url` of
  every `url-test` / `fallback` / `load-balance` / `smart` group, and can
  change their `type` to `smart` (the `AUTO_SMART_SWITCH` option).
  `RU-Mihomo.conf` sets `AUTO_SMART_SWITCH = 0`.
* If proxy groups are created in the OpenClash UI, OpenClash **rebuilds the
  whole `proxy-groups:` block** (`uci.rb`, `write_groups`). Do not create
  groups in the UI when you use this config.

### YAML anchors

The anchors in this config are not a guess - they were tested against the
real `YAML.rb` of OpenClash:

* all ruby scripts of OpenClash are started with `-ryaml -rYAML`, and
  OpenClash's `YAML.rb` aliases `load` to `unsafe_load`, so aliases and merge
  keys are resolved on load;
* the dump (`YAML.dump_string`) keeps the anchors (`&1` / `*1`), and the
  result still passes `mihomo -t`;
* `mihomo` itself (yaml.v3) accepts aliases to sequences, aliases to
  scalars and merge keys.

Only plain aliases are used here, no `<<:` merge keys, so the file stays
readable for tools that do not implement merge keys.

One caveat: `Psych.load_file` of a *plain* ruby (without OpenClash's
`YAML.rb`) rejects every alias - `Psych::AliasesNotEnabled`. That only
matters for your own scripts, not for OpenClash.

---

## 3. DNS

The scheme:

* fake-ip, so the domain is known before the connection;
* `respect-rules: true`, so a blocked domain is resolved through the proxy
  route and a Russian one is not;
* the main resolvers are DoH **by IP** (`1.1.1.1`, `9.9.9.9`): resolving a
  hostname needs a resolver in the first place;
* the proxy servers are resolved directly (`77.88.8.8` - Yandex DNS, answers
  reliably from Russia), otherwise the subscription never loads;
* Russian domains are resolved through Yandex DNS directly, otherwise the
  answer comes from outside Russia and you get the RKN stub.

### The GeoSite finding

The obvious way to send Russian domains to the Russian resolver is
`nameserver-policy: "geosite:category-ru"`. Measured on the router:

| | RSS | Start | GeoSite.dat |
|---|---|---|---|
| `geosite:category-ru` | **86.4 MB** | 4598 ms | downloaded, 4.3 MB |
| `rule-set:ru-domains` | **52.2 MB** | 67 ms | not downloaded at all |

`geosite:category-ru` makes the core download `GeoSite.dat` and keep the
whole geosite matcher in RAM. `rule-set:ru-domains` points at the local
`.mrs` file that is already there. The behaviour is identical - checked by
breaking the policy resolver: a Russian domain then fails with SERVFAIL and
a foreign one resolves, in both variants.

`mihomo` supports `rule-set:` in `nameserver-policy` (config/config.go).

### `fake-ip-filter`

It accepts DOMAIN rule-sets only: an IP rule-set here makes the core refuse
to start.

---

## 4. The rule order

The order is not a matter of taste, it was derived from the overlaps between
the lists:

1. `private`, `fake-ip-filter` -> DIRECT
2. `custom-domains` -> `⭐ Custom` - **your** decision wins over every list
3. `antiad` -> REJECT
4. the service groups -> **before** the RKN list
5. `rkn-blocked`, `rkn-community`, `rkn-blocked-ips` -> `🚫 RKN Blocked`
6. `category-ai-ru` -> DIRECT
7. `ru-domains`, `ru-ips` -> DIRECT
8. `microsoft`, `apple` -> DIRECT
9. `cdn` -> `🌐 CDN`
10. QUIC -> REJECT
11. MATCH -> `🎯 Final`

Why:

* **the services before the RKN list.** Telegram, Discord and the AI services
  are on the RKN list as well - measured 13, 22 and 15 overlapping domains.
  With the RKN rule first, choosing a node for those services would be
  unreachable, and for Telegram and Discord that is critical: they need a
  specific node.
* **the RKN list before the Russian domains.** There are domains like
  `007dom.ru`: Russian by TLD, but on the RKN list. With `ru-domains` first
  such a domain would go DIRECT, i.e. straight around the block.
* **`category-ai-ru` is Russian AI** (Yandex Alice and friends), not
  OpenAI. A foreign exit IP is wrong for them. The foreign AI services have
  their own lists (`openai`, `anthropic`, `google-gemini`, `xai`).
* **the CDN rule after the Russian domains**, so that the CDN hostnames of
  Russian services stay direct.

### The bare domain trap

The RKN lists ship bare domains (`instagram.com`). In mihomo a bare domain
with `behavior: domain` matches **only that exact domain** - `www.instagram.com`
slips through. Measured: with a bare list, 0 of 12 subdomains matched; with
the `+.` prefix (DOMAIN-SUFFIX), 12 of 12.

`scripts/build-ruleset.sh` adds the prefix before the conversion, so the
lists in `ruleset/` are correct.

### `no-resolve` on the private rule

The `private` rule-set is an IP list (`behavior: ipcidr`). To match a domain
against it, the core has to resolve the domain first. `no-resolve` skips that
resolution - and then a local host by name stops matching the private rule.

Measured with mihomo v1.19.33, fake-ip and a local DNS server, a request to
`nas.test` that resolves to `192.168.1.10`:

| Rule | What the core does |
|---|---|
| `RULE-SET,private,DIRECT` | `match RuleSet(private) using DIRECT` |
| `RULE-SET,private,DIRECT,no-resolve` | `match Match using PROXY` |

The second row sends the local host to the proxy. The domains of the
`fake-ip-filter` are not affected (their IP is known before the rules run),
but every other local name is. So the option stays off - it was measured and
rejected, not overlooked.

### `behavior: classical` with `format: mrs`

Such a rule is **silently not matched** - 0 of 12 domains instead of 12 of
12. Every rule-set in this config therefore uses `behavior: domain` or
`behavior: ipcidr`.

---

## 5. The node filters

Two regexes, both on the groups:

* `noise-filter` - LTE/4G servers and the subscription "info" nodes
  (traffic counters, expiry, tariffs). They are never usable as a proxy.
* `foreign-filter` - `noise-filter` plus the Russian markers. The automatic
  groups use it, because **a Russian exit IP does not unblock anything**: the
  RKN blocks traffic by Russian networks, so a Russian node would break
  exactly the sites this config exists to open.

The old config used a lookahead (`^(?!.*(?:...)).*$`) to express the same
thing. It works, but it is a backtracking regex on every node name and it is
hard to read. `exclude-filter` is subtracted from `filter` by the core, so a
plain alternation does the same job.

The Russian words and the Russian flag are written as `\x{...}` escapes, so
the file stays readable and the regexes stay ASCII:

```
\x{1F1F7}\x{1F1FA}  the flag
\x{041C}\x{043E}\x{0441}\x{043A}\x{0432}\x{0430}  "Москва"
```

**`\p{IsCyrillic}` must not be used** - it crashes mihomo v1.19.33 with a
panic in the regexp compiler. The engine is `dlclark/regexp2`, a full PCRE
implementation, so lookaheads do work if you ever need one.

`scripts/selftest.sh` checks that the noise part of `foreign-filter` is
still identical to `noise-filter` - otherwise an LTE node could slip into an
automatic group.

### The probe URL

Every automatic group measures its nodes against
`https://cp.cloudflare.com/generate_204`. HTTPS, not HTTP: the probe travels
through the node that is being measured, and a plain HTTP answer can be forged
by anything on the way. The TLS handshake is part of the measurement, that is
the point. The URL is one YAML anchor (`&probe-url`), so all the groups and the
health check of the provider use the same one.

### `find-process-mode`

`off`. On a router the traffic of the clients is forwarded - there is no local
process to look for, and this config has no `PROCESS-NAME` rules. The lookup
would only cost CPU. (The default of mihomo is `strict`, which looks up the
process for traffic that comes from the device itself.)

---

## 6. The proxy groups

See [GROUPS.md](GROUPS.md) for what every group is for.

The group `RU Nodes` is gone. `🎯 Manual` replaces it: it holds every node
of the subscription, the Russian ones included, so a Russian exit is still
one click away.

The three automatic groups are:

* `🚀 Auto` - url-test, tolerance 50 ms, 300 s
* `⚡ Turbo` - url-test, tolerance 0, 120 s: it switches faster and sticks
  to the fastest node even when the difference is small
* `🔁 Failover` - fallback: it keeps the first node that answers and only
  moves when it dies

---

## 7. Security

The config was audited against the code of OpenClash v0.48.002 and the
behaviour of the core was measured.

| Setting | Why |
|---|---|
| `secret: CHANGE_ME` -> `DASHBOARD_PASSWORD` | With an empty secret the API answers with `Access-Control-Allow-Origin: *`: any web page in the LAN can drive the proxy. OpenClash generates a random password at install time and `rmempty = true` in the LuCI form means clearing the field **deletes** the option - so the password is set in `RU-Mihomo.conf`. |
| `external-controller-cors.allow-origins: []` | No web page from the internet may talk to the API. |
| `external-controller-cors.allow-private-network: false` | A public site in the LAN may not reach the API either (verified with a preflight request: the header disappears). The dashboard itself is same-origin and still works. |
| `authentication` | The HTTP/SOCKS port needs credentials. OpenClash replaces the block with its own random password. |
| `skip-auth-prefixes` | Only the private networks, so that the router itself can use the proxy. |
| no `external-ui-url` | The core downloads and unpacks that zip **without any integrity check** (verified: it accepted a zip over plain HTTP from 127.0.0.1). OpenClash ships its own dashboard anyway. |
| `geo-auto-update: false` | `GeoIP.dat` (16.5 MB) and `GeoSite.dat` (4.4 MB) are never read by this config. |

The subscription URL does not leak through the API: `/configs`,
`/providers/proxies`, `/proxies`, `/connections` and `/rules` were checked -
the token is in none of them.

The dashboard port is not reachable from the WAN: OpenClash rejects `cn_port`
on the WAN interface in four different firewall variants. A CGNAT range
(100.64.0.0/10) would bypass that chain, so do not expose the router to the
internet.

---

## 8. The smart core

`type: smart` exists only in the fork
[vernesong/mihomo](https://github.com/vernesong/mihomo). Upstream MetaCubeX
answers `unsupported type: smart`, even in v1.19.34.

`RU-Mihomo-smart.yaml` replaces the type of `🚀 Auto` with `smart` and adds
the options of the fork:

```yaml
policy-priority: "Premium:1.30;SG:1.15;\bRU\b:0.50"
uselightgbm: false
collectdata: false
sample-rate: 1
prefer-asn: true
```

* `policy-priority` - a multiplier for the node names that match. `< 1` lowers
  the priority, `> 1` raises it. The pattern is tried as a regex first and as
  a plain substring otherwise, the first match wins, several rules are
  separated by `;`.
* `uselightgbm` - use the LightGBM model to predict the weight of a node.
  Needs `Model.bin`, which is **9.3 MB**. On a router with little flash keep
  it off; the smart group works without it, it just ranks the nodes by its
  own measurements.
* `collectdata` / `sample-rate` - collect data for a model of your own.
  `profile.smart-collector-size` limits the size of that file (100 MB by
  default) - it is a key of the top level `profile` block, in the group it is
  ignored.
* `prefer-asn` - look the ASN up first when a node is chosen. **It makes the
  core download `ASN.mmdb`, which is 8.7 MB** (measured: the plain config
  does not download it, the smart config with `prefer-asn: true` does). It is
  off by default here: on a router with 84.8 MB of flash that space is worth
  more elsewhere. Turn it on if you have room.
* `tolerance` - two nodes whose delays differ by less than this count as
  equal, so a jittering delay does not reorder the list.

The smart config keeps `⚡ Turbo` as a plain url-test group: there is always
a fallback that does not depend on the smart core.

---

## 9. Known limitations

* `mihomo -t` does not check whether the rule-set files exist. A missing
  `.mrs` shows up in the log at runtime, not at validation time. Use
  `scripts/selftest.sh`, it checks the files.
* `REJECT` in mihomo answers with **HTTP 502**, not 403. Relevant for every
  check that looks at the status code.
* The RKN list changes daily. `scripts/build-ruleset.sh` is meant to run on a
  schedule - see `.github/workflows/rulesets.yml`.
* The `x-fragments` block is not part of mihomo. `mihomo` ignores unknown
  top level keys (verified).
* The core downloads `ASN.mmdb` (8.7 MB) when a group uses `prefer-asn` or
  `type: smart` with the ASN lookup on. The plain config never downloads it,
  the smart config does not either as long as `prefer-asn` stays `false`.
  Check the working directory of the router if the flash usage is higher
  than expected.

### Testing on the WR3000S emulator

The full cycle was checked on a real QEMU emulation of the board, not only on
a PC. The emulator is `github.com/stavultras/router-emulator` v4.1 with the
`nand-wr3000s` flash folder, linked from 4pda topic 1087457, post #10376. The
official Cudy web emulator (`support.cudy.com/emulator/WR3000S`) is only a
simulator of the stock web UI and cannot run OpenWrt or mihomo.

Measured in the emulator: OpenWrt 25.12.5 boots, 256 MB RAM, an 84.8 MB
overlay, kernel 6.12.94. `mihomo v1.19.33` runs with all 28 rule providers
(252 793 rules), RSS 37 MB with five test nodes. A request to
`01-klinika-21.ru` matched `RuleSet/rkn-blocked`, so the hyphen fix works
end to end. `check-groups.sh` showed the Russian node only in `🎯 Manual`
and no LTE/info node in any group. `update-rulesets.sh APPLY=reload`
rebuilt all 28 files on the router and reloaded the live core through its
API without a restart.

What the emulator cannot reproduce: the radio is silent (no real Wi-Fi), the
WAN is QEMU user-mode NAT (no real ISP path, no actual RKN blocking), and
OpenClash itself was not installed - the core was launched directly with the
config that OpenClash would produce. It is still a real OpenWrt system with
the target RAM/flash layout, which is why the shell scripts and the core
behave the same way as on the device.
