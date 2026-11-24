# Installation

**English** | [Русский](INSTALL-RU.md)

Target: OpenWrt 25.12.x on a router with a MediaTek MT798x SoC, OpenClash
v0.48.002. Tested on a **Cudy WR3000S v1**.

Everything below was checked against the sources of OpenClash v0.48.002 and
against a running router.

The commands use `192.168.1.1`, the default address of OpenWrt. Put your own
address (or an alias from `~/.ssh/config`) there.

**About `scp -O`.** OpenSSH 9 and newer copies over SFTP by default, and
the stock dropbear of OpenWrt has no `sftp-server`. Every `scp` below has `-O`
(the classic SCP protocol) for that reason.

---

## Quick install

After OpenClash is installed (section 1), the whole configuration can be put
on the router with one script:

```sh
curl -fsSL -o /tmp/install.sh \
  https://raw.githubusercontent.com/Frog2233-DevOps/Mihomo-personal-config/main/scripts/install.sh
# read /tmp/install.sh before running it - it came from the network
SUB_URL='https://your-provider/subscription-link' \
DASHBOARD_PASSWORD='your-own-password' \
  sh /tmp/install.sh
```

It works directly on the router under `sh` (no bash, python or jq needed) and:

* downloads `RU-Mihomo.yaml`, `RU-Mihomo.conf`, the four helper scripts,
  `lists/custom-domains.list` and all 28 compiled rule-sets;
* substitutes the subscription URL and the dashboard password in both the
  config and the overwrite file (the credentials are never printed);
* installs everything into the OpenClash layout, keeps an existing custom
  list, backs up a changed config as `.bak`;
* checks the file count and runs `mihomo -t` if a core is already present;
* installs the **daily rule-set refresh** into the router's crontab when the
  default `ROOT=/etc/openclash` is used, keeping existing entries and never
  adding the line twice (section 5.1).

Nothing is installed until every download has succeeded, so a network failure
leaves the current setup untouched.

Options: `VARIANT=lite|smart` (default `full`), `BRANCH=dev` to test the
integration branch, `REPO=owner/repo` for a fork, `ROOT=<dir>` for another
config root, `ENABLE_CRON=0|1` to override the automatic cron setup. Example:

```sh
VARIANT=lite BRANCH=dev SUB_URL='...' DASHBOARD_PASSWORD='...' sh /tmp/install.sh
```

The script does **not** install OpenClash, reflash the router or change the
flash layout (section 0), and it does not start OpenClash. After it finishes,
import the overwrite file in LuCI and restart the plugin as described in
section 4. For a manual installation, follow sections 2-5.

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
ssh root@192.168.1.1 'mkdir -p /etc/openclash/config /etc/openclash/ruleset /etc/openclash/backup'
scp -O RU-Mihomo.yaml root@192.168.1.1:/etc/openclash/config/
scp -O RU-Mihomo.conf root@192.168.1.1:/etc/openclash/
scp -O ruleset/*.mrs root@192.168.1.1:/etc/openclash/ruleset/
```

The rule-set paths in the config are relative (`./ruleset/...`), so they are
resolved against the working directory of the core, which is `/etc/openclash`
on the router.

The `.mrs` files copied here are the ones from the repository. Section 5
makes the router build fresh ones itself.

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

The repository is public. Do not commit the subscription URL or the password:
edit the copy on the router, or keep a private copy of `RU-Mihomo.conf` outside
the repository.

---

## 4. Start and check

```sh
/etc/init.d/openclash restart
```

Wait for the log to say the core is ready, then check what ended up in the
groups:

```sh
scp -O scripts/check-groups.sh root@192.168.1.1:/etc/openclash/
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
over and let the router refresh the lists itself.

**The layout matters.** `build-ruleset.sh` takes the folder above its own as
the root of the repository and reads `lists/custom-domains.list` from there.
So `scripts/` and `lists/` have to lie side by side, the same as in the
repository:

```text
/etc/openclash/
  scripts/build-ruleset.sh
  scripts/update-rulesets.sh
  scripts/apply-rulesets.sh
  lists/custom-domains.list
  ruleset/                      <- the result, the .mrs files
```

Do **not** copy the two scripts straight into `/etc/openclash/`: the root
becomes `/etc` and the build stops with
`ERROR: /etc/lists/custom-domains.list not found`.

Install, from the root of the repository on your computer:

```sh
ssh root@192.168.1.1 'mkdir -p /etc/openclash/scripts /etc/openclash/lists'
scp -O scripts/build-ruleset.sh scripts/update-rulesets.sh scripts/apply-rulesets.sh root@192.168.1.1:/etc/openclash/scripts/
scp -O lists/custom-domains.list root@192.168.1.1:/etc/openclash/lists/
ssh root@192.168.1.1 'chmod +x /etc/openclash/scripts/*.sh'
```

Run it once by hand and look at the result:

```sh
ssh root@192.168.1.1 '/etc/openclash/scripts/update-rulesets.sh; echo exit=$?'
ssh root@192.168.1.1 'ls /etc/openclash/ruleset/*.mrs | wc -l'     # 28
```

The first run builds all the rule-sets, installs them into
`/etc/openclash/ruleset/` and applies them. Check the log of the run
(`/tmp/update-rulesets.log` when it is started from cron).

**The last step is the apply.** The core reads the rule-sets when it loads
the config, so somebody has to tell it to read them again. There are two ways,
and `scripts/apply-rulesets.sh` does both:

| `APPLY=` | What happens |
|---|---|
| `reload` (default) | The core is asked to reload its config through its own API (`PUT /configs?force=true`). The core process stays alive, the proxy is not interrupted, the new rule-sets work after a second. |
| `restart` | OpenClash is restarted. Simple, but the proxy is down for half a minute. |
| `none` | Nothing. The new lists are used after the next restart. |
| `check` | Only looks: how many rule-providers the running core has and how many rules they hold. |

If the reload does not work, the script restarts OpenClash by itself - the
new lists are always applied, one way or another. To see what the core has
right now:

```sh
ssh root@192.168.1.1 'APPLY=check sh /etc/openclash/scripts/apply-rulesets.sh'
```

**Files from Windows.** The `.gitattributes` of the repository keeps the
scripts in LF. If you copied them from an older checkout and the router
answers `not found` or `sh\r`, strip the carriage returns:

```sh
ssh root@192.168.1.1 "sed -i 's/\r$//' /etc/openclash/scripts/*.sh /etc/openclash/lists/custom-domains.list"
```

**Switching from an older config.** The rule-sets that the new config no longer
uses stay on the flash. Do not delete anything **before** the first successful
run: while the build fails, the old files are what OpenClash is working with,
and an empty `ruleset/` stops it from starting. After the run succeeded,
`ls -lt /etc/openclash/ruleset/` shows the new files on top; delete the old
ones below them (or all of them and run the script again).

#### The cron

OpenWrt has no `/etc/cron.d`; the cron of the router is the crontab of root, and
OpenClash keeps its own tasks in the same crontab. **`scripts/install.sh`
adds this line automatically** (unless `ENABLE_CRON=0`), preserves the other
entries and does not duplicate the job on a reinstall. If you installed by
hand, add the line without overwriting the file:

```sh
ssh root@192.168.1.1 "(crontab -l 2>/dev/null | grep -v update-rulesets; echo '30 5 * * * /etc/openclash/scripts/update-rulesets.sh >/tmp/update-rulesets.log 2>&1') | crontab - && /etc/init.d/cron enable && /etc/init.d/cron restart"
ssh root@192.168.1.1 'crontab -l'                                   # the line is there
```

Every morning the router rebuilds the lists with its own core, installs them
and applies them. If the build fails - no network, a list unreachable -
**the old lists stay in place** and the log says so. Nothing breaks.

The script tries the direct link first and then the mirrors
(`cdn.jsdelivr.net`, `gh-proxy.com`, `ghfast.top`), because from Russia
`raw.githubusercontent.com` is not always fast.

### 5.2 From GitHub Actions

`.github/workflows/rulesets.yml` rebuilds the rule-sets every day and commits
them to the repository. To push them to the router as well, add the
repository secrets `ROUTER_HOST`, `ROUTER_USER`, `ROUTER_PORT`,
`ROUTER_PATH` and `SSH_PRIVATE_KEY` - the workflow then calls
`scripts/deploy.sh`, which copies the files, applies them and prints what the
router has now.

The workflow needs a runner that can reach the router: a GitHub-hosted runner
is somewhere in the internet and does not see your LAN. Use a self-hosted
runner on your own machine, or a runner behind a VPN.

**Both ways at once?** Pick one. The router cron works without any secret and
survives a dead workflow; the Actions path works even when the router is
off at night. If both are on, the router cron wins - it runs at 5:30 and the
workflow commits once a day.

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

**`ERROR: .../lists/custom-domains.list not found`.** The scripts lie in the
wrong place. `scripts/` and `lists/` must be side by side (section 5.1), for
example `/etc/openclash/scripts` and `/etc/openclash/lists`.

**`scp` fails with `sftp-server: not found` or `subsystem request failed`.**
`deploy.sh` already tries `-O` first and falls back automatically. If you
call `scp` yourself, add `-O`: dropbear has no SFTP server.

**`scp: stat local "8022": No such file or directory`.** A non-default SSH
port was passed with `-p`. For `scp` the flag is capital `-P`; `deploy.sh`
uses both forms (`-p` for `ssh`, `-P` for `scp`).

**`check-groups.sh` prints `NOT FOUND` for every group and then "OK".** The
API returned 401, not the proxy list: the dashboard password is missing or
wrong. Pass `SECRET=<password>` or check `/etc/openclash/secret`. The script
now rejects such an answer instead of reporting false positives.

**The build summary says `Bytes: 0`.** It used GNU `stat -c%s`, which busybox
does not support. The script now counts with `wc -c`.

**`can't create /etc/cron.d/...: nonexistent directory`.** There is no
`/etc/cron.d` on OpenWrt. Use the crontab, see section 5.1.

**The script says `not found` or `sh\r` although the file is there.** It has
Windows line endings. Strip them with the `sed` command from section 5.1.

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

## 8. Verification

Before opening a pull request, from the repository root:

```sh
./scripts/selftest.sh          # mihomo -t on all three configs + consistency
bash tests/run-all.sh          # regression suite (also run by CI on every PR)
```

`tests/run-all.sh` covers the configs, the domain normalizer (including
hyphenated and punycode domains), the deploy flags, the busybox build, the
API checks, the EN/RU documentation pairs and the workflow copies. A router
is not required for it.

To check the **full cycle** — build, deploy, apply, check — against a real
router or the Cudy WR3000S QEMU emulator (from 4pda topic 1087457, post
#10376):

```sh
ROUTER_HOST=192.168.1.1 ROUTER_PORT=22 SECRET=<dashboard-password> \
  bash tests/04_cycle.sh
```

It deploys with a non-default port, verifies the router layout and all 28
rule-sets, asks the running core for its rule providers and checks that a
wrong dashboard password is rejected. See `docs/DESIGN.md` section 9 for
what the emulator can and cannot reproduce.
