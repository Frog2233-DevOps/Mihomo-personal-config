# Mihomo personal config

A mihomo / OpenClash configuration for a router in Russia: Russian traffic
goes straight out, blocked and foreign traffic goes through the proxy,
everything else is decided by rule-sets you can rebuild yourself.

No subscriptions of mine, no node lists of mine, no "premium" endpoints. One
subscription, one config, 28 rule-sets.

Built and measured on a **Cudy WR3000S v1** (MT7981BA, 256 MB RAM, 128 MB
NAND, OpenWrt 25.12.x, OpenClash v0.48.002, mihomo v1.19.33). Every number
below was measured, not read from a README.

Русская версия: [README-RU.md](README-RU.md).

## What makes it different

**The DNS policy uses a local rule-set, not `geosite`.**
The obvious way to send Russian domains to the Russian resolver is
`nameserver-policy: "geosite:category-ru"`. It makes the core download
`GeoSite.dat` (4.3 MB) and keep the geosite matcher in RAM:

| | RSS | Start |
|---|---|---|
| `geosite:category-ru` | 86.4 MB | 4598 ms |
| `rule-set:ru-domains` (this config) | **52.2 MB** | **67 ms** |

Same behaviour, 34 MB less RAM. Verified by breaking the policy resolver: a
Russian domain fails with SERVFAIL and a foreign one resolves, in both
variants.

**The rule lists are built, not downloaded.** The RKN lists ship bare domains
(`instagram.com`), and in mihomo a bare domain with `behavior: domain` matches
**only that exact domain** - `www.instagram.com` slips through. Measured: with
a bare list 0 of 12 subdomains matched, with the `+.` prefix 12 of 12. The
build script adds the prefix before converting to `.mrs`.

**The rule order is derived from the overlaps, not from taste.**

| # | Rule | Why there |
|---|---|---|
| 1 | `private`, `fake-ip-filter` -> DIRECT | LAN first |
| 2 | `custom-domains` -> `⭐ Custom` | **your** decision beats every list |
| 3 | `antiad` -> REJECT | |
| 4 | the service groups | Telegram, Discord and the AI services are on the RKN list too (13, 22 and 15 overlapping domains) - with the RKN rule first, picking a node for them would be unreachable |
| 5 | `rkn-blocked` -> `🚫 RKN Blocked` | **before** the Russian domains: `007dom.ru` is Russian by TLD but on the RKN list - the other order sends it straight around the block |
| 6 | `category-ai-ru` -> DIRECT | that is Russian AI (Yandex Alice), not OpenAI |
| 7 | `ru-domains`, `ru-ips` -> DIRECT | |
| 8 | `microsoft`, `apple` -> DIRECT | |
| 9 | `cdn` -> `🌐 CDN` | after the Russian domains, so the CDNs of Russian services stay direct |
| 10 | QUIC -> REJECT | UDP tunnels are unstable, TCP is more reliable |
| 11 | MATCH -> `🎯 Final` | |

**The Russian nodes are not in the automatic groups.** The RKN blocks traffic
by Russian networks, so a Russian exit IP does not unblock anything - it would
break exactly the sites this config exists to open. They are still one click
away in `🎯 Manual`.

**No heavy regexes.** The old version excluded the Russian nodes with a
lookahead (`^(?!.*(?:...)).*$`) - a backtracking regex on every node name.
`exclude-filter` is subtracted from `filter` by the core, so a plain
alternation does the same job.

**YAML anchors.** The shared parts of the groups live in one `x-fragments`
block. Tested against the real `YAML.rb` of OpenClash: it resolves the
anchors on load, keeps them on dump, and the result still passes `mihomo -t`.

**The security defaults are not decorative.** An empty dashboard secret makes
the API answer with `Access-Control-Allow-Origin: *` - any web page in the
LAN could drive the proxy. The geo databases (16.5 + 4.4 MB) are switched off
because this config never reads them. The dashboard zip is not downloaded
because the core unpacks it without any integrity check.

Details and measurements: [docs/DESIGN.md](docs/DESIGN.md).

## The proxy groups

18 groups, emoji in the names. Full description in
[docs/GROUPS.md](docs/GROUPS.md).

| Group | Type | What it is for |
|---|---|---|
| `🎯 Final` | select | the entry point, the target of the last rule |
| `🚀 Auto` | url-test | the fastest stable foreign node |
| `⚡ Turbo` | url-test | tolerance 0, switches faster - games and calls |
| `🔁 Failover` | fallback | keeps the first node that answers |
| `🎯 Manual` | select | one specific node, Russian ones included |
| `💬 Telegram` `🎮 Discord` `🤖 AI` | select | per-service node choice |
| `▶️ YouTube` `🎬 Streaming` `🐙 GitHub` `📱 Social` | select | per-service node choice |
| `🎮 Steam` `🧱 Roblox` `🕹️ Games` | select | per-service node choice |
| `🌐 CDN` | select | the CDN hostnames of the big providers |
| `⭐ Custom` | select | **your** domains, `lists/custom-domains.list` |
| `🚫 RKN Blocked` | select | the blocked domains without a service of their own |

## The three variants

| File | Ad blocking | Core | RAM (measured) |
|---|---|---|---|
| `RU-Mihomo.yaml` | yes | Meta (upstream) | 58 MB |
| `RU-Mihomo-lite.yaml` | no | Meta (upstream) | **52 MB** |
| `RU-Mihomo-smart.yaml` | yes | Smart (vernesong fork) | depends on the model |

The lite variant exists because the ad list is 102 005 domains and costs about
4 MB of RAM. The smart variant needs the `vernesong/mihomo` binary - upstream
does not know the type `smart`.

`RU-Mihomo-lite.yaml` and `RU-Mihomo-smart.yaml` are **generated**. Edit
`RU-Mihomo.yaml`, then:

```sh
./scripts/make-lite.sh && ./scripts/make-smart.sh
```

## The placeholders

Two things to set, everything else has a working default:

| File | Placeholder | What to put there |
|---|---|---|
| `RU-Mihomo.conf` -> `SUB_INFO_URL` | `PASTE_SUBSCRIPTION_URL_HERE` | your subscription URL |
| `RU-Mihomo.conf` -> the `ruby_map_edit` line | `PASTE_SUBSCRIPTION_URL_HERE` | the same URL |
| `RU-Mihomo.conf` -> `DASHBOARD_PASSWORD` | `CHANGE_ME` | a password of your own |
| `RU-Mihomo.yaml` -> `proxy-providers` -> `Main` -> `url` | `PASTE_SUBSCRIPTION_URL_HERE` | only if you do not use `RU-Mihomo.conf` |

If you change the URL in `RU-Mihomo.yaml`, regenerate the two derived configs -
otherwise they keep the old URL.

## Files

| Path | |
|---|---|
| `RU-Mihomo.yaml` | the main config, the source of truth |
| `RU-Mihomo-lite.yaml` | generated, without the ad rule-set |
| `RU-Mihomo-smart.yaml` | generated, for the smart core |
| `RU-Mihomo.conf` | OpenClash overwrite file: DNS mode, IPv6 off, the dashboard password |
| `lists/custom-domains.list` | your domains -> `ruleset/custom-domains.mrs` -> `⭐ Custom` |
| `ruleset/` | 28 compiled rule-sets, 1.5 MB |
| `scripts/build-ruleset.sh` | rebuilds the rule-sets from the upstream lists |
| `scripts/make-lite.sh`, `scripts/make-smart.sh` | regenerate the variants |
| `scripts/deploy.sh` | copies the config and the rule-sets to the router over SSH |
| `scripts/check-groups.sh` | runs on the router: what ended up in every group |
| `scripts/update-rulesets.sh` | runs on the router: rebuilds the rule-sets with its own core and restarts OpenClash - the lists update themselves |
| `scripts/fix-exec.sh`, `scripts/fix-exec.ps1` | mark the scripts as executable (bash and PowerShell) |
| `scripts/selftest.sh` | `mihomo -t` on every config + the checks on the filters, the groups and the files |
| `docs/DESIGN.md` | why every decision was made, with the measurements |
| `docs/INSTALL.md` | installation on OpenWrt / OpenClash |
| `docs/GROUPS.md` | what every group is for |
| `docs/RULESETS.md` | where the lists come from and how they are built |
| `AGENTS.md` | the rules that must not be broken, for AI models and for humans |

## Numbers

| | |
|---|---|
| RAM, lite config | 52 MB RSS (154 nodes) |
| RAM, full config | 58 MB RSS |
| Bare core, no config | 45 MB RSS |
| Rule-sets on flash | 1.5 MB |
| Start time | 67 ms |
| Rule-sets rebuilt | daily by `rulesets.yml` |
| Flash, everything together | ~46 MB (OpenClash 10.7 + core 25-29 + rule-sets 1.5 + dashboard 3-5) |

## Contributing

The scripts are committed with the executable bit. If a fresh clone does not
have it - some tools drop it - fix it once:

```sh
bash scripts/fix-exec.sh          # Git Bash, Linux, macOS
```

On Windows, in PowerShell, in the repository root:

```powershell
.\scripts\fix-exec.ps1
```

The scripts themselves are bash, so run them from Git Bash or WSL:

```sh
bash scripts/build-ruleset.sh
bash scripts/selftest.sh
```

## Sources of the rule lists

* [1andrevich/Re-filter-lists](https://github.com/1andrevich/Re-filter-lists) - the RKN lists
* [privacy-protection-tools/anti-AD](https://github.com/privacy-protection-tools/anti-AD) - ad domains
* [MetaCubeX/meta-rules-dat](https://github.com/MetaCubeX/meta-rules-dat) - the ready-made lists

## License

MIT, see [LICENSE](LICENSE).
