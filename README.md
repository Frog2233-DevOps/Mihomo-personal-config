# Mihomo personal config

A mihomo / OpenClash configuration for a router that sits in Russia: Russian
traffic goes straight out, blocked and foreign traffic goes through the
proxy, and everything in between is decided by rule-sets you can rebuild
yourself.

Built and measured on a **Cudy WR3000S v1** (MT7981BA, 256 MB RAM, 128 MB
NAND, OpenWrt 25.12.x, OpenClash v0.48.002).

## What is in the repository

| Path | What it is |
|---|---|
| `RU-Mihomo.yaml` | The main config. Ad blocking on. This is the one to use. |
| `RU-Mihomo-lite.yaml` | Generated from the main config without the ad rule-set (~4 MB less RAM). |
| `RU-Mihomo-smart.yaml` | Generated from the main config for the *smart* core (vernesong/mihomo). |
| `RU-Mihomo.conf` | OpenClash overwrite file: DNS mode, IPv6 off, the dashboard password. |
| `lists/custom-domains.list` | **Your** domains. They get their own rule-set and their own group. |
| `ruleset/` | The compiled rule-sets (`.mrs`), 28 files, 1.5 MB in total. |
| `scripts/build-ruleset.sh` | Rebuilds `ruleset/` from the upstream lists and your own list. |
| `scripts/make-lite.sh` | Regenerates `RU-Mihomo-lite.yaml`. |
| `scripts/make-smart.sh` | Regenerates `RU-Mihomo-smart.yaml`. |
| `scripts/deploy.sh` | Copies the config and the rule-sets to the router over SSH. |
| `scripts/check-groups.sh` | Runs on the router: shows what ended up in every group. |
| `scripts/selftest.sh` | Validates everything: `mihomo -t`, filters, groups, files. |
| `docs/DESIGN.md` | Why every decision was made. Every statement there was measured. |
| `docs/INSTALL.md` | Installation on OpenWrt / OpenClash, step by step. |
| `docs/GROUPS.md` | What every proxy group is for. |
| `docs/RULESETS.md` | Where the rule lists come from and how they are built. |
| `AGENTS.md` | Context file for AI models working on this repository. |

## Quick start

1. Copy `lists/custom-domains.list` your own domains into it (optional).
2. Put the subscription URL into `RU-Mihomo.conf` (`SUB_INFO_URL`) and set
   `DASHBOARD_PASSWORD` to a password of your own.
3. Copy `RU-Mihomo.yaml` and the `ruleset/` folder to the router, see
   [docs/INSTALL.md](docs/INSTALL.md).

Rebuild the rule-sets whenever you want fresh lists:

```bash
./scripts/build-ruleset.sh
./scripts/selftest.sh
```

## The three variants

| File | Ad blocking | Core | RAM (measured) |
|---|---|---|---|
| `RU-Mihomo.yaml` | yes | Meta (upstream) | 58 MB |
| `RU-Mihomo-lite.yaml` | no | Meta (upstream) | 52 MB |
| `RU-Mihomo-smart.yaml` | yes | Smart (vernesong fork) | depends on the model |

The lite variant exists because the ad list is 102 005 domains and costs
about 4 MB of RAM - on a 128 MB router that matters. The smart variant needs
the `vernesong/mihomo` binary, the upstream core does not know the type
`smart`.

## Numbers measured on the router

| | |
|---|---|
| RAM of the lite config | 52 MB RSS (154 nodes) |
| RAM of the full config | 58 MB RSS |
| Bare core, no config | 45 MB RSS |
| Flash for the rule-sets | 1.5 MB |
| Flash for the OpenClash package | 10.7 MB |
| Start time | 67 ms (without the geo databases) |

The geo databases are switched off on purpose: `GeoIP.dat` is 16.5 MB and
`GeoSite.dat` is 4.4 MB, and this config never reads them.

## Sources of the rule lists

* [1andrevich/Re-filter-lists](https://github.com/1andrevich/Re-filter-lists) - the RKN lists
* [privacy-protection-tools/anti-AD](https://github.com/privacy-protection-tools/anti-AD) - ad domains
* [MetaCubeX/meta-rules-dat](https://github.com/MetaCubeX/meta-rules-dat) - the ready-made lists

## License

MIT, see [LICENSE](LICENSE).
