# Installation

Target: OpenWrt 25.12.x on a router with a MediaTek MT798x SoC, OpenClash
v0.48.002. Tested on a **Cudy WR3000S v1**.

Everything below was checked against the sources of OpenClash v0.48.002 and
against a running router.

---

## 0. Before you start: the flash layout matters

The `mihomo` arm64 binary is 57.5 MB and takes 25-29 MB in UBIFS. Together
with OpenClash, ruby and the rule-sets it does not fit into the standard
layout of a 128 MB NAND router.

| Layout | Overlay |
|---|---|
| standard | 44 MB - **does not fit** |
| ubootmod | 84.8 MB - use this one |

The `ubootmod` layout moves the UBI partition from 64 MiB to 122.25 MiB and
gives ~50 MB more. The procedure is described in the OpenWrt sources:
`package/boot/uboot-mediatek/patches/468-add-cudy_wr3000s-v1.patch` and the
commit messages of [openwrt/openwrt#22625](https://github.com/openwrt/openwrt/pull/22625)
(taken into 25.12.4). The official image for the profile
`cudy_wr3000s-v1-ubootmod` exists for 25.12.5 and 25.12.6.

---

## 1. Install OpenClash

OpenClash v0.48.002 publishes both an `.apk` and an `.ipk`. On OpenWrt
25.12.6 use the `.apk`:

```sh
cd /tmp
wget https://github.com/vernesong/OpenClash/releases/download/v0.48.002/luci-app-openclash-0.48.002.apk
apk add --allow-untrusted ./luci-app-openclash-0.48.002.apk
```

Dependencies of the `.apk` (all present in the 25.12.6 repositories for
`aarch64_cortex-a53`): `libc`, `dnsmasq-full`, `bash`, `curl`, `ca-bundle`,
`ip-full`, `ruby`, `ruby-yaml`, `kmod-tun`, `unzip`.

After the installation the plugin is in LuCI under *Services -> OpenClash*.
The first start generates a random dashboard password and an
`authentication` section.

---

## 2. Put the config on the router

From your computer:

```sh
scp RU-Mihomo.yaml root@192.168.1.1:/etc/openclash/config/
scp RU-Mihomo.conf root@192.168.1.1:/etc/openclash/
scp ruleset/*.mrs root@192.168.1.1:/etc/openclash/ruleset/
```

The `ruleset/` folder has to exist:

```sh
ssh root@192.168.1.1 'mkdir -p /etc/openclash/ruleset /etc/openclash/backup'
```

The rule-set paths in the config are relative (`./ruleset/...`), so they are
resolved against the working directory of the core, which is `/etc/openclash`
on the router.

---

## 3. Set the subscription and the dashboard password

Edit `/etc/openclash/RU-Mihomo.conf` on the router:

```ini
[General]
# the only subscription
SUB_INFO_URL = https://your-provider/subscription-link

# the password for the dashboard and the API. NOT empty: with an empty secret
# the API answers with "Access-Control-Allow-Origin: *".
DASHBOARD_PASSWORD = your-own-password

# the config to use: RU-Mihomo.yaml (with ad blocking) or
# RU-Mihomo-lite.yaml (about 4 MB less RAM, without ad blocking)
CONFIG_FILE = /etc/openclash/config/RU-Mihomo.yaml
```

Then import the overwrite file in LuCI: *OpenClash -> Config Manage -> Config
Subscribe*, point it at the raw URL of `RU-Mihomo.conf` (or copy the file to
`/etc/openclash/backup/` and pick it in the overwrite settings).

The subscription URL can also be substituted straight into the YAML with
the line at the end of `RU-Mihomo.conf`:

```ini
[Overwrite]
ruby_map_edit "$CONFIG_FILE" "['proxy-providers']" "Main" "['url']" "PASTE_SUBSCRIPTION_URL_HERE"
```

---

## 4. Start and check

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
one of the automatic groups.

RAM and flash:

```sh
ssh root@192.168.1.1 'ps | grep -i mihomo'          # RSS in the last column
ssh root@192.168.1.1 'df -h /overlay'               # free flash
ssh root@192.168.1.1 'logread | grep -i mihomo | tail -30'
```

Reference numbers (154 nodes, zram 168 MB): lite **52 MB** RSS, full **58 MB**
RSS, bare core ~45 MB.

---

## 5. Keep the rule-sets fresh

The rule-sets are **local files** (`type: file`, `./ruleset/*.mrs`). That is
deliberate: it keeps the core from downloading anything at startup and it is
what makes the RAM numbers work. The consequence is that somebody has to
refresh them - and that somebody does not have to be you.

### 5.1 On the router (recommended, no secrets)

The router already has the core that does the conversion. Copy the scripts
over and let the router refresh the lists itself:

```sh
scp scripts/build-ruleset.sh scripts/update-rulesets.sh root@192.168.1.1:/etc/openclash/
ssh root@192.168.1.1 'chmod +x /etc/openclash/*.sh'
ssh root@192.168.1.1 '/etc/openclash/update-rulesets.sh'      # the first run
```

If the scripts were uploaded from a Windows checkout they can carry Windows
line endings, and the shell of the router cannot parse them:

```
/etc/openclash/update-rulesets.sh: line 35: syntax error: unexpected word (expecting "do")
```

That is not a missing bash - the scripts are plain POSIX `sh`. It is the
line endings. One command fixes it:

```sh
sed -i 's/\r$//' /etc/openclash/*.sh
```

The repository has a `.gitattributes` that keeps the line endings of the
scripts at LF even on a Windows checkout, and `scripts/deploy.sh` strips the
stray CRs on the router after every upload.

Then put it into the cron of the router:

```sh
ssh root@192.168.1.1 "echo '30 5 * * * /etc/openclash/update-rulesets.sh >/tmp/update-rulesets.log 2>&1' > /etc/cron.d/openclash-ruleset"
```

Every morning the router rebuilds the lists with its own core, installs them
and restarts OpenClash. If the build fails - no network, a list unreachable -
**the old lists stay in place** and the log says so. Nothing breaks.

The script tries the direct link first and then the mirrors
(`cdn.jsdelivr.net`, `gh-proxy.com`, `ghfast.top`), because from Russia
`raw.githubusercontent.com` is not always fast.

### 5.2 From GitHub Actions

`.github/workflows/rulesets.yml` rebuilds the rule-sets every day and commits
them to the repository. To push them to the router as well, add the
repository secrets `ROUTER_HOST`, `ROUTER_USER`, `ROUTER_PORT`,
`ROUTER_PATH` and `SSH_PRIVATE_KEY` - the workflow then calls
`scripts/deploy.sh`.

### 5.3 On your computer

```sh
./scripts/build-ruleset.sh
./scripts/selftest.sh
```

---

## 6. The smart core (optional)

`RU-Mihomo-smart.yaml` needs the fork
[vernesong/mihomo](https://github.com/vernesong/mihomo/releases), the
upstream core does not know the type `smart`.

In OpenClash, set the core type to *Smart* (or `SMART_ENABLE = 1` in the
overwrite file) and put `RU-Mihomo-smart.yaml` on the router instead of
`RU-Mihomo.yaml`.

The LightGBM model is 9.3 MB. On a router with little flash leave
`uselightgbm: false` and `lgbm-auto-update: false` - the smart group ranks
the nodes by its own measurements without the model.

---

## 7. Troubleshooting

**No nodes in the groups.** The subscription did not load. Check
`logread | grep -i openclash` and the URL in `SUB_INFO_URL`. The proxy
servers are resolved directly (`77.88.8.8`), so a broken DNS makes the whole
subscription unreachable.

**A rule-set does not match.** `mihomo -t` does not check whether the files
exist. Look for "rule set ... not found" in the log, and run
`./scripts/selftest.sh`.

**The dashboard asks for a password you do not know.** It is
`DASHBOARD_PASSWORD` from `RU-Mihomo.conf` (or the random one that OpenClash
generated at the install time).

**The config is different after every start.** That is OpenClash: it rewrites
DNS, `fake-ip-filter`, `hosts`, the sniffer and `authentication` on every
start. That is why `RU-Mihomo.conf` switches off its own DNS handling
(`ENABLE_CUSTOM_DNS = 0`, `CUSTOM_FAKEIP_FILTER = 0`,
`CUSTOM_NAME_POLICY = 0`).

**The scripts fail with `syntax error: unexpected word (expecting "do")`.**
Windows line endings (CRLF) in the file. `sed -i 's/\r$//' /etc/openclash/*.sh`.
The scripts are plain POSIX `sh`, no bash needed.

**You want your own node filter.** Put it on the *groups*, not on the
provider: OpenClash rewrites the provider filters from its own UI.
