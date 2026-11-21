# Mihomo personal config

A mihomo / OpenClash configuration for a router that sits in Russia: Russian
traffic goes straight out, blocked and foreign traffic goes through the
proxy, and everything in between is decided by rule-sets you can rebuild
yourself.

Built and measured on a **Cudy WR3000S v1** (MT7981BA, 256 MB RAM, 128 MB
NAND, OpenWrt 25.12.x, OpenClash v0.48.002).

Русская версия: [README-RU.md](README-RU.md).

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
| `README-RU.md` | The same documentation in Russian. |

## The placeholders you have to replace

There are exactly two things you must set: **the subscription URL** and **the
dashboard password**. Everything else has a working default.

| File | Placeholder | What to put there | Required? |
|---|---|---|---|
| `RU-Mihomo.conf` → `SUB_INFO_URL` | `PASTE_SUBSCRIPTION_URL_HERE` | your subscription URL | **yes** |
| `RU-Mihomo.conf` → the `ruby_map_edit` line | `PASTE_SUBSCRIPTION_URL_HERE` | the same subscription URL | **yes** |
| `RU-Mihomo.conf` → `DASHBOARD_PASSWORD` | `CHANGE_ME` | a password of your own | **yes** |
| `RU-Mihomo.yaml` → `proxy-providers` → `Main` → `url` | `PASTE_SUBSCRIPTION_URL_HERE` | your subscription URL | only if you do not use `RU-Mihomo.conf` |
| `RU-Mihomo.yaml` → `secret` | `CHANGE_ME` | the same password | no, OpenClash overwrites it |
| `RU-Mihomo.yaml` → `authentication` | `mihomo:CHANGE_ME` | a password of your own | no, OpenClash replaces it with a random one |
| `lists/custom-domains.list` | - | your own domains, one per line | no |

Why the dashboard password must not stay empty: with an empty `secret` the
mihomo API answers with `Access-Control-Allow-Origin: *`, which means any web
page open in the LAN can drive your proxy, read your connections and change
the settings.

After you change the subscription URL **in `RU-Mihomo.yaml`**, regenerate the
two derived configs, otherwise they keep the old URL:

```sh
./scripts/make-lite.sh
./scripts/make-smart.sh
```

`RU-Mihomo-lite.yaml` and `RU-Mihomo-smart.yaml` are generated files. Never
edit them by hand - the next generation overwrites your change.

## Installation

### 0. Check the flash layout first

The `mihomo` arm64 binary is 57.5 MB and takes 25-29 MB in UBIFS. Together
with OpenClash, ruby and the rule-sets it does **not** fit into the standard
layout of a 128 MB NAND router.

| Layout | Overlay |
|---|---|
| standard | 44 MB - does not fit |
| ubootmod | 84.8 MB - use this one |

If your router still has the standard layout, flash the `ubootmod` image
first. The procedure is in the OpenWrt sources:
`package/boot/uboot-mediatek/patches/468-add-cudy_wr3000s-v1.patch` and the
commits of [openwrt/openwrt#22625](https://github.com/openwrt/openwrt/pull/22625)
(taken into 25.12.4). The official image for the profile
`cudy_wr3000s-v1-ubootmod` exists for 25.12.5 and 25.12.6.

Check what you have:

```sh
df -h /overlay
```

### 1. Install OpenClash

OpenClash v0.48.002 publishes both an `.apk` and an `.ipk`. On OpenWrt
25.12.6 use the `.apk`:

```sh
cd /tmp
wget https://github.com/vernesong/OpenClash/releases/download/v0.48.002/luci-app-openclash-0.48.002.apk
apk add --allow-untrusted ./luci-app-openclash-0.48.002.apk
```

The dependencies of the `.apk` are all in the 25.12.6 repositories for
`aarch64_cortex-a53`: `libc`, `dnsmasq-full`, `bash`, `curl`, `ca-bundle`,
`ip-full`, `ruby`, `ruby-yaml`, `kmod-tun`, `unzip`.

After the installation the plugin is in LuCI under *Services -> OpenClash*.
The first start generates a random dashboard password and an
`authentication` section.

### 2. Copy the config and the rule-sets to the router

From your computer:

```sh
ssh root@192.168.1.1 'mkdir -p /etc/openclash/config /etc/openclash/ruleset /etc/openclash/backup'
scp RU-Mihomo.yaml root@192.168.1.1:/etc/openclash/config/
scp RU-Mihomo.conf root@192.168.1.1:/etc/openclash/
scp ruleset/*.mrs  root@192.168.1.1:/etc/openclash/ruleset/
```

The rule-set paths in the config are relative (`./ruleset/...`), they are
resolved against the working directory of the core, which is `/etc/openclash`
on the router.

### 3. Set the subscription and the dashboard password

Edit `/etc/openclash/RU-Mihomo.conf` on the router:

```ini
[General]
# the one and only subscription
SUB_INFO_URL = https://your-provider/subscription-link

# the password for the dashboard and the API. NOT empty: with an empty secret
# the API answers with "Access-Control-Allow-Origin: *".
DASHBOARD_PASSWORD = your-own-password

# the config to use: RU-Mihomo.yaml (with ad blocking) or
# RU-Mihomo-lite.yaml (about 4 MB less RAM, without ad blocking)
CONFIG_FILE = /etc/openclash/config/RU-Mihomo.yaml
```

Then import the overwrite file in LuCI: *OpenClash -> Config Manage -> Config
Subscribe*, point it at the raw URL of `RU-Mihomo.conf` - or copy the file to
`/etc/openclash/backup/` and pick it in the overwrite settings.

If you do not want to use the overwrite file at all, put the subscription URL
straight into `RU-Mihomo.yaml` instead:

```yaml
proxy-providers:
  Main:
    url: 'https://your-provider/subscription-link'
```

and set `secret` and `authentication` yourself. In that case you are on your
own with the password of the API.

### 4. Start and check

```sh
/etc/init.d/openclash restart
```

Wait for the log to say the core is ready, then check what ended up in the
groups:

```sh
scp scripts/check-groups.sh root@192.168.1.1:/etc/openclash/
ssh root@192.168.1.1 'sh /etc/openclash/check-groups.sh'
```

It prints every group with its nodes and warns when a node that must not be
used (LTE server, info node) slipped in, or when a Russian node ended up in
one of the automatic groups. The result should look like this:

* `🚀 Auto`, `⚡ Turbo`, `🔁 Failover` - only the foreign nodes
* `🎯 Manual` - every node, the Russian ones included, without the LTE and
  the "info" nodes
* the service groups - `🚀 Auto`, `🎯 Manual`, `DIRECT`

RAM and flash:

```sh
ssh root@192.168.1.1 'ps | grep -i mihomo'      # RSS in the last column
ssh root@192.168.1.1 'df -h /overlay'           # free flash
ssh root@192.168.1.1 'logread | grep -i mihomo | tail -30'
```

Reference numbers (154 nodes, zram 168 MB): lite **52 MB** RSS, full **58 MB**
RSS, bare core ~45 MB.

### 5. Keep the rule-sets fresh

On the router, with a cron job (the router needs internet access to GitHub):

```sh
crontab -e
# every morning at 5:31
31 5 * * * /usr/bin/mihomo convert-ruleset ... # see scripts/build-ruleset.sh
```

The easier way is the GitHub Actions workflow in this repository:
`.github/workflows/rulesets.yml` rebuilds the rule-sets every day and commits
them. To push them to the router as well, add the repository secrets
`ROUTER_HOST`, `ROUTER_USER`, `ROUTER_PORT`, `ROUTER_PATH` and
`SSH_PRIVATE_KEY` - the workflow then calls `scripts/deploy.sh`.

Locally:

```sh
./scripts/build-ruleset.sh
./scripts/selftest.sh
```

### 6. The smart core (optional)

`RU-Mihomo-smart.yaml` needs the fork
[vernesong/mihomo](https://github.com/vernesong/mihomo/releases), the
upstream core does not know the type `smart` ("unsupported type: smart").

In OpenClash, set the core type to *Smart* - `CORE_TYPE = Smart` in
`RU-Mihomo.conf` - and put `RU-Mihomo-smart.yaml` on the router instead of
`RU-Mihomo.yaml`.

The LightGBM model is 9.3 MB, and `prefer-asn: true` makes the core download
`ASN.mmdb` (8.7 MB). On a router with little flash leave both off: the smart
group ranks the nodes by its own measurements without them.

## Troubleshooting

**No nodes in the groups.** The subscription did not load. Check
`logread | grep -i openclash` and the URL in `SUB_INFO_URL`. The proxy servers
are resolved directly (`77.88.8.8`), so a broken DNS makes the whole
subscription unreachable.

**A rule-set does not match.** `mihomo -t` does not check whether the files
exist. Look for "rule set ... not found" in the log, and run
`./scripts/selftest.sh` - it checks the files.

**The dashboard asks for a password you do not know.** It is
`DASHBOARD_PASSWORD` from `RU-Mihomo.conf` (or the random one that OpenClash
generated at the install time).

**The config is different after every start.** That is OpenClash: it rewrites
DNS, `fake-ip-filter`, `hosts`, the sniffer and `authentication` on every
start. That is why `RU-Mihomo.conf` switches off its own DNS handling
(`ENABLE_CUSTOM_DNS = 0`, `CUSTOM_FAKEIP_FILTER = 0`,
`CUSTOM_NAME_POLICY = 0`).

**You want your own node filter.** Put it on the *groups*, not on the
provider: OpenClash rewrites the provider filters from its own UI.

**Your groups disappeared after you touched the OpenClash UI.** OpenClash
rebuilds the whole `proxy-groups:` block from its own storage. Do not create
proxy groups in the UI when you use this config.

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
