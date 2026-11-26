# Mihomo personal config

A mihomo configuration for the **mixomo** scheme on a router in Russia: only
the traffic you selected goes through the core, everything else goes straight
to the provider at the full speed of the line.

```
client -> MagiTrickle (DNS, marks the addresses of its lists)
       -> hev-socks5-tunnel (tun "Mihomo")
       -> mihomo (mixed-port 7890) -> the node
```

No subscriptions of mine, no node lists of mine, no "premium" endpoints. One
subscription, one config, 28 rule-sets.

Built and measured on a **Cudy WR3000S v1** (MT7981BA, 239 MB RAM + 131 MB
swap, OpenWrt 25.12.6, mixomo v0.3.4, MagiTrickle 0.8.2, hev-socks5-tunnel
2.20.0, mihomo v1.19.34). Every number below was measured, not read from a
README.

Русская версия: [README-RU.md](README-RU.md).

The scheme itself is not ours: it is
[Internet-Helper/mixomo-openwrt](https://github.com/Internet-Helper/mixomo-openwrt)
(Apache 2.0) with
[MagiTrickle](https://gitlab.com/magitrickle/magitrickle) as the part that
decides what goes into the core. What is in this repository is the **config for
that scheme**: the configuration of the core, the lists of MagiTrickle and the
scripts that put it all on the router.

## The installation

```sh
# 1. the scheme itself
curl -fsSL https://github.com/Internet-Helper/mixomo-openwrt/raw/main/install.sh | sh

# 2. the configuration of this repository
curl -fsSL -o /tmp/setup-mixomo.sh \
  https://raw.githubusercontent.com/Frog2233-DevOps/Mihomo-personal-config/main/scripts/setup-mixomo.sh
SUB_URL='https://your-provider/subscribe' DASHBOARD_PASSWORD='your-password' \
  sh /tmp/setup-mixomo.sh
```

The script downloads the config, the scripts and all 28 rule-sets, substitutes
the placeholders, writes the state of MagiTrickle, installs the daily refresh
and checks the result. It never prints the subscription URL and never prints
the password.

The address of the router is not fixed: it depends on the settings of the LAN
(`192.168.1.1` is only the default). The installer reads it out of `br-lan`.

Details: [docs/MIXOMO.md](docs/MIXOMO.md), in Russian:
[docs/MIXOMO-RU.md](docs/MIXOMO-RU.md).

## What makes it different

**Only the selected traffic goes through the core.** The layout that sends
*everything* through the core (the OpenClash one, kept in the branch
`legacy/openclash`) matches the rules for every packet of the household and
tracks every connection. That is why the speed drops and why UDP packets get
lost on the way. Here MagiTrickle answers the DNS, marks the addresses of its
lists, and only the marked traffic enters the core.

**The DNS policy uses a local rule-set, not `geosite`.** The obvious way to
send the Russian domains to the Russian resolver is
`nameserver-policy: "geosite:category-ru"`. It makes the core download
`GeoSite.dat` (4.3 MB) and keep the geosite matcher in RAM:

| | RSS | Start |
|---|---|---|
| `geosite:category-ru` | 86.4 MB | 4598 ms |
| `rule-set:ru-domains` (this config) | **52.2 MB** | **67 ms** |

Same behaviour, 34 MB less RAM. Verified by breaking the policy resolver: a
Russian domain fails with SERVFAIL and a foreign one resolves, in both
variants.

**The ad list is not in the core.** MagiTrickle drops it with the interface
`blackhole`, so ~110 000 domains stay out of the RAM of the core and out of
its rule matching. The core does not even load `anti-ad.mrs`.

**The rule lists are built, not downloaded.** The RKN lists ship bare domains
(`instagram.com`), and in mihomo a bare domain with `behavior: domain` matches
**only that exact domain** - `www.instagram.com` slips through. Measured: with
a bare list 0 of 12 subdomains matched, with the `+.` prefix 12 of 12. The
build script adds the prefix before converting to `.mrs`; hyphens stay in the
domain characters, so entries like `01-klinika-21.ru` are not lost.

**The rule order is derived from the overlaps, not from taste.**

| # | Rule | Why there |
|---|---|---|
| 1 | `private` -> DIRECT | LAN first |
| 2 | `custom-domains` -> `⭐ Custom` | **your** decision beats every list |
| 3 | the service groups | Telegram, Discord and the AI services are on the RKN list too (13, 22 and 15 overlapping domains) - with the RKN rule first, picking a node for them would be unreachable |
| 4 | `rkn-blocked` -> `🚫 RKN Blocked` | **before** the Russian domains: `007dom.ru` is Russian by TLD but on the RKN list - the other order sends it straight around the block |
| 5 | `category-ai-ru` -> DIRECT | that is Russian AI (Yandex Alice), not OpenAI |
| 6 | `ru-domains`, `ru-ips` -> DIRECT | |
| 7 | `microsoft`, `apple` -> DIRECT | |
| 8 | `cdn` -> `🌐 CDN` | after the Russian domains, so the CDNs of Russian services stay direct |
| 9 | QUIC -> REJECT | UDP tunnels are unstable, TCP is more reliable |
| 10 | MATCH -> `🎯 Final` | |

The rule of `games` stands **above** the RKN list: 121 of its domains are on
the RKN list and 51 on the Roblox list. Without it those 172 domains would
change their group.

**The Russian nodes are not in the automatic groups.** The RKN blocks traffic
by Russian networks, so a Russian exit IP does not unblock anything - it would
break exactly the sites this config exists to open. They are still one click
away in `🎯 Manual`.

**No heavy regexes.** The old version excluded the Russian nodes with a
lookahead (`^(?!.*(?:...)).*$`) - a backtracking regex on every node name.
`exclude-filter` is subtracted from `filter` by the core, so a plain
alternation does the same job.

**The security defaults are not decorative.** An empty dashboard secret makes
the API answer with `Access-Control-Allow-Origin: *` - any web page in the
LAN could drive the proxy. The geo databases (16.5 + 4.4 MB) are switched off
because this config never reads them.

## The proxy groups

18 groups, emoji in the names.

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

A service that is not on a list of MagiTrickle never reaches the core: the
rules of the core only decide what happens to the traffic that was selected.
The local groups (Custom, Streaming, AI, GitHub, Steam) are built from the
rule-sets by `scripts/gen-mtrickle.sh`.

## The placeholders

Two things to set, everything else has a working default:

| Where | Placeholder | What to put there |
|---|---|---|
| `RU-Mihomo-mixomo.yaml` -> `proxy-providers` -> `Main` -> `url` | `PASTE_SUBSCRIPTION_URL_HERE` | your subscription URL |
| `RU-Mihomo-mixomo.yaml` -> `secret` | `CHANGE_ME` | the password of your dashboard |

`scripts/setup-mixomo.sh` substitutes both from `SUB_URL` and
`DASHBOARD_PASSWORD`.

## Files

| Path | |
|---|---|
| `RU-Mihomo-mixomo.yaml` | the config of the core for the scheme - the only file that is edited by hand |
| `magitrickle/magitrickle.yaml` | the template of the state of MagiTrickle: the groups and the subscriptions |
| `magitrickle/magitrickle.mtrickle` | the same groups in the JSON format of the web interface |
| `lists/custom-domains.list` | your domains -> `ruleset/custom-domains.mrs` -> `⭐ Custom` |
| `lists/bypass-ports.list` | the ports that never reach the core |
| `ruleset/` | 28 compiled rule-sets, 1.7 MB |
| `scripts/setup-mixomo.sh` | installs the scheme on the router: the config, the rule-sets, the state of MagiTrickle, the cron and the checks |
| `scripts/gen-mtrickle.sh` | writes the state of MagiTrickle from the rule-sets and from your own list |
| `scripts/update-mixomo.sh` | runs on the router: rebuilds the rule-sets and the state of MagiTrickle and reloads the core |
| `scripts/build-ruleset.sh` | rebuilds the rule-sets from the upstream lists |
| `scripts/apply-rulesets.sh` | runs on the router: tells the running core to reload its config through its own API, without a restart |
| `scripts/check-groups.sh` | runs on the router: what ended up in every group |
| `scripts/bypass-ports.sh`, `scripts/mixomo-bypass.init` | keep the traffic of the listed ports out of the core |
| `scripts/selftest.sh`, `scripts/selftest.py` | `mihomo -t`, the checks of the config and `shellcheck` for the scripts of the router |
| `tests/run-all.sh` | the full regression suite of the scheme |
| `docs/MIXOMO.md`, `docs/MIXOMO-RU.md` | the scheme, the installation, the measurements, the troubleshooting |
| `AGENTS.md` | the rules that must not be broken, for AI models and for humans |

The OpenClash layout (the config for the "everything through the core" scheme)
is in the branch `legacy/openclash`.

## Numbers

Measured on the router (Cudy WR3000S v1, 239 MB RAM, mihomo v1.19.34):

| | |
|---|---|
| RAM, the core with the config of the scheme | 60.7 MB RSS (average of 3 runs) |
| RAM, the core with the "lite" variant | 60.8 MB RSS - no saving, the variant was removed |
| RAM, the rule-sets on the flash | 1.7 MB in 28 files |
| Rule-sets rebuilt | daily by `rulesets.yml` |

The numbers of the daemon, of the oom-killer and the measurements of the
lists are in [docs/MIXOMO.md](docs/MIXOMO.md).

## Contributing

The scripts are committed with the executable bit. The shell scripts and the
lists keep LF line endings (`.gitattributes`) - a CRLF in them breaks them on
the router.

```sh
bash scripts/selftest.sh    # mihomo -t, shellcheck, the consistency checks
bash tests/run-all.sh       # the full suite - this is what CI runs
```

## Sources of the rule lists

* [1andrevich/Re-filter-lists](https://github.com/1andrevich/Re-filter-lists) - the RKN lists
* [privacy-protection-tools/anti-AD](https://github.com/privacy-protection-tools/anti-AD) - ad domains
* [MetaCubeX/meta-rules-dat](https://github.com/MetaCubeX/meta-rules-dat) - the ready-made lists

## License

MIT, see [LICENSE](LICENSE).
