# The mixomo scheme

[Русская версия](MIXOMO-RU.md)

## What it is

The mixomo scheme sends **only the selected traffic** through the core:

```
client -> MagiTrickle (DNS, marks the addresses of its lists)
       -> hev-socks5-tunnel (tun "Mihomo")
       -> mihomo (mixed-port 7890) -> the node
```

Everything that is not on a list goes to the provider at the full speed of the
line and never touches the core. The core is not a router for the whole
household any more - it is a proxy for the traffic you selected.

The scheme is not ours. It is
[Internet-Helper/mixomo-openwrt](https://github.com/Internet-Helper/mixomo-openwrt)
(Apache 2.0) with
[MagiTrickle](https://gitlab.com/magitrickle/magitrickle) as the part that
decides what goes into the core. What is in this repository is the **config
for that scheme**: the configuration of the core, the lists of MagiTrickle
and the scripts that put it all on the router.

## Why

Two problems of the "everything through the core" layout (the OpenClash one
of this repository):

1. **The speed drops.** Every packet of the clients is handled by the core:
   the rules are matched, the connections are tracked, the DNS is answered by
   the core. On a Cudy WR3000S (MT7981, 256 MB) the core uses 52-58 MB of
   RAM with the full rule-sets and the router has 239 MB in total.
2. **UDP packets are lost.** The UDP path of the core is the bottleneck: a
   Rust server that sends a lot of UDP gets timeouts because the packets
   pile up in the pipeline of the core.

Both problems come from the same place: the traffic goes through the core
whether it needs the proxy or not. In the mixomo scheme only the selected
traffic goes there, and the rest goes straight to the provider.

## What the scheme changes in the config

The first column is the OpenClash layout - it is not in `main` any more, it is
archived in the branch `legacy/openclash`. The comparison is here to show what
the scheme had to change and why.

| | the OpenClash layout (`legacy/openclash`) | `RU-Mihomo-mixomo.yaml` |
|---|---|---|
| `mixed-port` | 7893 | **7890** - the socks5 port of the tunnel, and the value mixomo checks |
| `redir-port` | - | 5001 - the transparent port of the core |
| `routing-mark` | - | 2 - the mark on the connections of the core |
| `dns.listen` | 0.0.0.0:1053 | **0.0.0.0:7880** - the DNS port of the scheme |
| `dns.enhanced-mode` | fake-ip | **redir-host** - see below |
| `tun` | off | off - the tunnel belongs to hev-socks5-tunnel |
| rule-sets | `./ruleset/` | `./rule-files/` - the directory of mixomo |
| provider | `./proxy_provider/` | `./proxy-providers/` - the directory of mixomo |
| ad list | in the core (`REJECT`) | **not in the core** - MagiTrickle drops it |

### Why redir-host and not fake-ip

In fake-ip the core answers with an address of 198.18.0.0/16. The client
sends **all** of its traffic to those addresses. But only the addresses that
MagiTrickle marked go into the core - the rest would leave the router
towards a fake address and never arrive anywhere. So fake-ip forces
"everything through the core", which is exactly what this scheme is meant to
avoid.

With redir-host the client gets a real address, MagiTrickle marks the same
real address, and the core recovers the domain from the TLS handshake
(the sniffer). The price is one more inspection of the handshake; the gain is
that the core sees only the traffic that was selected.

### Why the ad list is not in the core

The ad list has 110 000 domains. Keeping it in the core costs about 20 MB of
its RAM and the time of every rule match. MagiTrickle can drop the traffic
itself (the group has the interface `blackhole`), so the core never sees it
and does not keep it in its memory.

The difference in behaviour: the core rejects an ad connection with an RST
right away, the router drops it and the client waits for a timeout. If you
want the fast answer, uncomment the `antiad` rule-provider in
`RU-Mihomo-mixomo.yaml` **and** change the interface of the "Anti-AD" group
of MagiTrickle from `blackhole` to `Mihomo`.

## The files

| File | What it is |
|---|---|
| `RU-Mihomo-mixomo.yaml` | the configuration of the core for this scheme |
| `magitrickle/magitrickle.yaml` | the state of MagiTrickle: the groups and the subscriptions |
| `magitrickle/magitrickle.mtrickle` | the same groups in the JSON format of the web interface |
| `scripts/setup-mixomo.sh` | installs the scheme on the router |
| `scripts/gen-mtrickle.sh` | writes the state of MagiTrickle from the rule-sets |
| `scripts/mixomo-ipv6.sh`, `scripts/mixomo-ipv6.init` | keep the IPv6 of the tunnel device alive (the daemon dies without it) |
| `scripts/update-mixomo.sh` | the daily refresh of the rule-sets |
| `scripts/apply-rulesets.sh` | tells the running core to read the new files |
| `scripts/check-groups.sh` | what ended up in every group of the core |
| `scripts/bypass-ports.sh`, `scripts/mixomo-bypass.init` | keep the traffic of the listed ports out of the core |
| `scripts/build-ruleset.sh` | builds the rule-sets from the upstream lists |
| `scripts/mixomo-ram.sh` | the report: the memory of the router, the RSS of the two programs |
| `scripts/mixomo-memlimit.sh` | the soft memory limit (`GOMEMLIMIT`) of the core and of the daemon |
| `scripts/selftest.sh`, `scripts/selftest.py` | `mihomo -t`, `shellcheck` and the consistency checks |
| `docs/MIXOMO.md`, `docs/MIXOMO-RU.md` | this document, in English and in Russian |
| `docs/UPSTREAM-ISSUES.md` | the texts of the issues for the upstream projects (MagiTrickle) |
| `AGENTS.md` | the rules that must not be broken |

## Installation

### 1. mixomo

```shell
curl -fsSL https://github.com/Internet-Helper/mixomo-openwrt/raw/main/install.sh | sh
```

This installs the core, hev-socks5-tunnel, MagiTrickle and the web
interface. It asks which build of MagiTrickle you want: `Original` or
`Mod`. Both work with this repository - the mod build adds the TPROXY mode
and the `direct` interface, the scheme does not need them.

### 2. the scheme

```shell
curl -fsSL -o /tmp/setup-mixomo.sh \
  https://raw.githubusercontent.com/Frog2233-DevOps/Mihomo-personal-config/main/scripts/setup-mixomo.sh
SUB_URL='https://provider/subscribe' DASHBOARD_PASSWORD='your-password' \
  sh /tmp/setup-mixomo.sh
```

The script:

* stops and disables OpenClash (the two schemes fight over the routing
  table; the settings are backed up to `/etc/config/openclash.bak.<pid>`);
* installs the config into `/etc/mihomo/config.yaml` (the old one is kept as
  `config.yaml.bak`);
* installs the 28 rule-sets into `/etc/mihomo/rule-files/`;
* writes the state of MagiTrickle into `/etc/magitrickle/state/config.yaml`;
* installs the daily refresh into the crontab (05:30);
* starts the services and checks the result.

Useful variables: `STOP_OPENCLASH=0` keeps OpenClash running,
`INSTALL_MIXOMO=1` installs mixomo when it is missing, `ENABLE_CRON=0` skips
the crontab.

### 3. your own domains

```shell
vi /etc/mihomo/lists/custom-domains.list
sh /etc/mihomo/scripts/gen-mtrickle.sh
```

The list is yours: the script never overwrites it.

## The IPv6 of the tunnel device

The tunnel device `Mihomo` is created by `hev-socks5-tunnel` at every start
of the tunnel. A new device inherits `net.ipv6.conf.default.disable_ipv6` from
the kernel, so on a router with IPv6 switched off the device comes up with
IPv6 disabled:

```
sysctl net.ipv6.conf.Mihomo.disable_ipv6   ->  1
```

MagiTrickle links the address sets of its groups to that device and adds a
default route for it. The kernel refuses the IPv6 route of a device with IPv6
disabled and answers `-EACCES`, and the daemon gives up:

```
failed to enable group: failed to link ipset to interface:
error adding iface route: permission denied
```

Measured on the router (Cudy WR3000S, OpenWrt 25.12.6):

```
all.disable_ipv6    = 1
default.disable_ipv6 = 1
br-lan.disable_ipv6 = 1
Mihomo.disable_ipv6 = 1   <- after /etc/init.d/hev-socks5-tunnel restart
```

**What is measured on the router as it is now** (the Mod build of
MagiTrickle, daemon 0.5.2-badigit.18): the daemon does **not** die with the
device disabled - it writes

```
no addresses on interface for current IP family, skipping route family=10 iface=Mihomo
```

and keeps working (measured: the daemon is running, 11.8 MB of RSS). With
`disableIPv6: true` in the state file the daemon does not even try the
route, and the message is not there (measured: the daemon is running, 11.9 MB
of RSS). The death with "permission denied" was reported in the original
issue for this router; it was **not reproduced with this build** - which
build produced it is not checked here.

The fix of the scheme works for both cases: IPv6 is enabled on this one
device (never globally, never on `br-lan`), so the daemon has an address to
work with and the message is not there.

`scripts/mixomo-ipv6.sh` with the init script `scripts/mixomo-ipv6.init`
(installed as `/etc/init.d/mixomo-ipv6`) does it:

* it waits for the device (up to `MIXOMO_IPV6_WAIT` seconds, 60 by default);
* it switches IPv6 on for this one device and starts MagiTrickle again;
* the device is created again at every start of the tunnel and comes up
  with IPv6 disabled once more, so the state is checked every
  `MIXOMO_IPV6_INTERVAL` seconds (30) and repaired when it is needed.

The settings are in `/etc/mihomo/mixomo.conf`:

```
FIX_IPV6=1              0 switches the fix off
MIXOMO_IPV6_WAIT=60     how long to wait for the device
MIXOMO_IPV6_INTERVAL=30 how often the state is checked
```

The report:

```shell
sh /etc/mihomo/scripts/mixomo-ipv6.sh status

device Mihomo: exists
  net.ipv6.conf.Mihomo.disable_ipv6 = 0
magitrickle: running
fix: on
```

The order at the boot: the tunnel (`START=99`) -> the guard of the IPv6
(`START=99`) -> MagiTrickle (`START=99`). The guard waits for the device, so
the race at the start of the router is not a problem.

The second layer of the defence is the state file itself:
`scripts/gen-mtrickle.sh` writes `app.netfilter.disableIPv6` from the value
`IPV6` (`auto` by default: the daemon does not touch IPv6 when the router
has IPv6 switched off).

## The lists of MagiTrickle

The subscriptions are downloaded and refreshed by MagiTrickle itself:

| List | Source | Interface | Meaning |
|---|---|---|---|
| 🚫 RKN Blocked | Re-filter `domains_all.lst` | Mihomo | 81 460 domains of the list of the registrar |
| 🚫 RKN Community | Re-filter `community.lst` | Mihomo | the community list (715 domains) |
| 🛑 RKN IP | Re-filter `ipsum.lst` | Mihomo | 27 546 subnets of the list |
| 🛡 Anti-AD | anti-AD | **blackhole** | 110 000 ad domains, dropped by the router |
| 💬 Telegram | itdoginfo | Mihomo | |
| 🎮 Discord | itdoginfo | Mihomo | |
| 📱 Meta | itdoginfo | Mihomo | Instagram, Facebook |
| 🧱 Roblox | itdoginfo | Mihomo | |
| 🤖 Google AI | itdoginfo | Mihomo | |
| ▶️ YouTube | itdoginfo | Mihomo | off by default |
| 🐦 Twitter | itdoginfo | Mihomo | off by default |

The local groups are built by `scripts/gen-mtrickle.sh` from the rule-sets of
the core:

| Group | Source | On by default |
|---|---|---|
| ⭐ Custom | `lists/custom-domains.list` | yes |
| 🎬 Streaming | `ruleset/netflix.mrs` | yes |
| 🤖 AI | `ruleset/{openai,anthropic,xai}.mrs` | yes |
| 🐙 GitHub | `ruleset/github.mrs` | yes |
| 🎮 Steam | `ruleset/steam.mrs` | no |

Steam is off by default: it is reachable from Russia without a proxy, and
the traffic of these games then never touches the core. Every group is
switchable when the state is generated (`GROUP_CUSTOM`, `GROUP_STREAMING`,
`GROUP_AI`, `GROUP_GITHUB`, `GROUP_STEAM`):

```shell
GROUP_STEAM=1 GROUP_GITHUB=0 sh /etc/mihomo/scripts/gen-mtrickle.sh
```

**The rule of the scheme**: a service that is not on a list of MagiTrickle
does not reach the core at all, so no rule of the core can change it. When
you want a service through the proxy, put it into a list.

## The sources of the lists

The daemon downloads the lists of the subscriptions itself, one address per
subscription:

| List | Address |
|---|---|
| 🚫 RKN Blocked | `https://raw.githubusercontent.com/1andrevich/Re-filter-lists/main/domains_all.lst` |
| 🚫 RKN Community | `https://raw.githubusercontent.com/1andrevich/Re-filter-lists/main/community.lst` |
| 🛑 RKN IP | `https://raw.githubusercontent.com/1andrevich/Re-filter-lists/main/ipsum.lst` |
| 🛡 Anti-AD | `https://raw.githubusercontent.com/privacy-protection-tools/anti-AD/master/anti-ad-domains.txt` |
| the rest | itdoginfo |

The **branch** of the repository and not the assets of the release: the
assets are not published every time (the asset `community.lst` is not there
at all - measured on the router: 404, and the daemon answered "failed to
fetch subscription rules: unexpected status 404"), and the file of the
branch is the same file (measured: the same md5 through both addresses).

The check from the router - the router has its own way to the internet,
the computer of the administrator may have another one:

```shell
for u in \
  https://raw.githubusercontent.com/1andrevich/Re-filter-lists/main/domains_all.lst \
  https://raw.githubusercontent.com/1andrevich/Re-filter-lists/main/community.lst \
  https://raw.githubusercontent.com/1andrevich/Re-filter-lists/main/ipsum.lst ; do
  curl -sS -L --max-time 60 -o /dev/null -w '%{http_code} %{size_download}\n' "$u"
done
```

Measured on the router (Cudy WR3000S, OpenWrt 25.12.6):

| Address | Code | Lines | md5 |
|---|---|---|---|
| `releases/.../domains_all.lst` | 200 | 81 460 | c9b79dc0fde5829b2690450781a1ec2e |
| `main/domains_all.lst` | 200 | 81 460 | c9b79dc0fde5829b2690450781a1ec2e |
| `releases/.../ipsum.lst` | 200 | 27 546 | 0d1e2a41bb65888dc41a20e5191d75a2 |
| `main/ipsum.lst` | 200 | 27 546 | 0d1e2a41bb65888dc41a20e5191d75a2 |
| `releases/.../community.lst` | 404 | 1 | - |
| `main/community.lst` | 200 | 715 | c0b15a5af0a31a083addcace1251f8ec |

**When an address times out:**

1. Check it from the router with the command above. A timeout on the
   computer says nothing about the router.
2. The rule-sets of the core are not affected by it: `scripts/build-ruleset.sh`
   tries the addresses one after another (the branch, jsdelivr, the proxies,
   the release - the release is the last mirror).
3. A subscription of MagiTrickle has **one** address - the daemon does not
   know a list of addresses. If `raw.githubusercontent.com` does not work
   from the router, the way out is to serve the list from the router
   itself:

   ```shell
   curl -fsSL -o /www/rkn.lst 'https://raw.githubusercontent.com/1andrevich/Re-filter-lists/main/domains_all.lst'
   # and in the state file:  url: http://127.0.0.1/rkn.lst
   ```

   The redirect to https of `uhttpd` has to be off for that (the daemon
   follows it and the certificate of the router does not fit the address -
   measured: "tls: failed to verify certificate for 127.0.0.1 because it
   doesn't contain any IP SANs"):

   ```shell
   uci set uhttpd.main.redirect_https='0'
   uci commit uhttpd
   /etc/init.d/uhttpd restart
   ```

## The memory of the router

MagiTrickle keeps **every domain of every list in the RAM of the daemon** -
and the router has to hold the daemon, the core and the system at the same
time. The lists of the scheme are big: `domains_all.lst` has 81 460 lines,
`ipsum.lst` 27 546 subnets, the ad list 110 218.

Measured on a router (Cudy WR3000S, OpenWrt 25.12.6, 239 MB of RAM,
MagiTrickle 0.8.2-r1, daemon 0.5.2-badigit.18). The list was loaded through
the API of the daemon (`PATCH /api/v1/subscription?id=...`), the peak of the
RSS was read from `/proc`:

| List | Lines | Peak of the RSS | Result |
|---|---|---|---|
| none (the app only) | - | 14.8 MB | stable |
| 1 000 domains | 1 000 | 27.0 MB | ok |
| 2 000 domains | 2 000 | 40.2 MB | ok |
| 5 000 domains | 5 000 | 77.4 MB | ok |
| 5 000 domains, `GOMEMLIMIT=64MiB` | 5 000 | 64.0 MB | ok |
| 10 000 domains | 10 000 | - | killed by the oom-killer |
| 27 546 IP subnets | 27 546 | - | killed by the oom-killer |
| 81 460 domains | 81 460 | - | killed by the oom-killer |
| 110 218 ad domains | 110 218 | - | killed, the core with it |

That is about **13 kB of RAM for every domain of a list**. The kernel killed
the daemon at 94-111 MB of RSS (the swap was full at the same time), and
with the ad list it took the core with it. A daemon that is killed downloads
nothing: the lists of the subscriptions stay at the state they had.

What the scheme does about it:

* `scripts/gen-mtrickle.sh` counts the domains of the local groups and the
  lines of the lists **before** the state file is written. Every list that
  does not fit into `MAX_DOMAINS` (5 000 by default) is switched off, and
  the script says which one and why:

  ```
  WARNING: the list "🚫 RKN Blocked" has 81460 lines, only 4800 are left: it is switched off
  ```

  The size is read with `curl` (or `uclient-fetch`, or `wget` - whatever is
  on the router). The list is not downloaded when `PROBE=0`. A list whose size
  **cannot** be measured is switched off: the daemon keeps every domain of a
  list in its RAM, so the price of a wrong guess is the oom-killer (it takes
  the daemon and the core with it), while the price of a switched-off list is
  one list that does not work until it is switched on by hand.
* The groups of the scheme are switchable, and every domain of a group is
  also RAM of the daemon: `GROUP_CUSTOM`, `GROUP_STREAMING`, `GROUP_AI`,
  `GROUP_GITHUB`, `GROUP_STEAM`.
* The ad list follows the RAM of the router: `ANTI_AD=auto` (the default)
  switches it off on a router with less than `MIN_RAM_MB` (384) of RAM.
* `scripts/mixomo-memlimit.sh` sets `GOMEMLIMIT` for the core (96MiB) and
  for the daemon (64MiB). The limit is soft: the garbage collector works
  harder instead of the kernel killing the process. With 5 000 domains the
  peak was 64.0 MB with the limit and 77.4 MB without it.

**A list that is switched off is a loss**: the traffic of those domains does
not go through the proxy any more. What to do:

| Situation | What to do |
|---|---|
| the RKN list does not fit | a smaller list, or a router with more RAM, or `MAX_DOMAINS` (and a router that survives it) |
| the ad list does not fit | `ANTI_AD=0` and the ad list in the core: uncomment the `antiad` rule-provider in `RU-Mihomo-mixomo.yaml` and put the group "Anti-AD" on the interface `Mihomo` |
| the groups are too big | `GROUP_GITHUB=0`, `GROUP_STEAM=0`, ... |

The URL of a switched-off list points to nothing
(`http://127.0.0.1:1/switched-off.lst`), and the original URL stays in the
comment of the state file next to the reason:

```yaml
  - id: 701cde4f
    name: "🚫 RKN Blocked"
    interface: Mihomo
    enable: false
    # the list has 81460 lines, only 4860 are left for the subscriptions - it is switched off
    # the original url: https://raw.githubusercontent.com/1andrevich/Re-filter-lists/main/domains_all.lst
    url: http://127.0.0.1:1/switched-off.lst
```

Why: the daemon downloads a list when the user asks for an update in the web
interface - **even when the subscription is off**. With the real address of
a big list that update kills the daemon and the core with it (measured on
the router). With this address the update fails at once ("connection
refused"), the daemon stays alive (15.3 MB of RSS), and there is no
oom-killer event.

The report of the memory:

```shell
sh /etc/mihomo/scripts/mixomo-ram.sh          # the numbers
sh /etc/mihomo/scripts/mixomo-ram.sh --log    # with the messages of the oom-killer
```

The measurements above are the base of an issue for the upstream project
(MagiTrickle): the text of it is in
[UPSTREAM-ISSUES.md](UPSTREAM-ISSUES.md).

## The ports that bypass the core

Some traffic must not touch the core **at all**. A Rust server that sends a
lot of UDP is the example from the field: the UDP pipeline of the core is
the bottleneck, and the packets of the game server get lost on the way -
the connection times out.

In this scheme the traffic of the clients reaches the core only when
MagiTrickle marked its address. The traffic of a port that is on the list
below never gets there at all:

```shell
vi /etc/mihomo/bypass-ports.txt     # one port per line
/etc/init.d/mixomo-bypass restart
```

The file is yours - the installer never overwrites it. The installer also
takes the ports from the command line:

```shell
BYPASS_PORTS='25565 28015' sh /tmp/setup-mixomo.sh
```

### How it works

`scripts/bypass-ports.sh` builds a chain of its own and hooks it into
`PREROUTING` of the `mangle` and the `nat` table, in the first position -
in front of the chains of MagiTrickle:

```
-A MIXOMO_BYPASS ! -i lo -p udp --dport 25565 -m comment --comment mixomo-bypass -j ACCEPT
-I PREROUTING 1 -j MIXOMO_BYPASS
```

Two details are not decoration:

* **ACCEPT and not RETURN.** A `RETURN` from a chain of the mangle table
  only means "back to PREROUTING and keep looking" - a packet that
  MagiTrickle marked would stay marked and would still go into the core.
  `ACCEPT` ends the traversal of the table, the packet keeps its normal
  route to the provider.
* **The first position.** The chains of MagiTrickle are inserted into
  `PREROUTING` as well. A rule of ours that stands in front of them stays
  in front of them: MagiTrickle restores the position of its own chains
  after a restart by the rules around them (the "anchors"), so our jump is
  part of that anchor.

The init script `/etc/init.d/mixomo-bypass` starts MagiTrickle first and
hooks the rule in afterwards, and it is enabled at the installation.

### What it does not do

The traffic of these ports is not seen by the core, so it is also not
seen by the rules of the core: it is not proxied, not filtered and not
blocked by the RKN list. That is the point - the port is for a server that
has to be reached directly.

## The router

The address of the router is not always `192.168.1.1` - it depends on the
settings of the LAN. On the router of the measurements of this document it
is `192.168.25.1`. The installer does not guess it: it takes the address of
`br-lan`.

```shell
ip -4 addr show br-lan | awk '/inet /{print $2}' | cut -d/ -f1
```

| What | Where |
|---|---|
| the web interface of MagiTrickle | `http://<the address of the router>:8080/` |
| the dashboard of the core | `http://<the address of the router>:9090/ui` |

OpenWrt 25.12 has **apk** as the package manager (`opkg` is not there -
measured on the router: `/usr/bin/apk`, no `opkg`). The scripts of this
repository do not install any package: they need the core, `curl` and the
files of the scheme - and mixomo itself knows both package managers.

## The build of MagiTrickle: Original or Mod

The installer of mixomo asks which build of MagiTrickle to use. Both work
with this repository - the Mod build adds the TPROXY mode and the `direct`
interface, the scheme does not need them.

What is on the router (measured):

| File | What |
|---|---|
| `/etc/mixomo/templates/magitrickle-package-default.yaml` | the state of the package |
| `/etc/mixomo/templates/magitrickle-groups-mod.yaml` | the groups of the Mod build |
| `/etc/mixomo/templates/magitrickle-groups-original.yaml` | the groups of the Original build |
| `/etc/mixomo/templates/magitrickle-template.active` | the name of the template that is in use (`from-mixomo`) |
| `/etc/magitrickle/state/config.yaml.bak` | the state before the last write |

The rules that hold for both builds:

* the format of the state file is the same, `configVersion` starts with
  `0.1.` (the Mod build refuses everything else, the Original build takes
  every `0.*`);
* the fields `dnsProxy.timeout` and `netfilter.ipset.additionalTTL` are
  not written by the script: the builds read them differently (a duration
  against a number of seconds);
* the file `.mtrickle` (the groups in the JSON format of the web
  interface) carries **only the groups**. The subscriptions are not part of
  it - after an import of the file the lists of the subscriptions are empty
  and they have to be created again (by `scripts/setup-mixomo.sh` or by
  hand in the interface);
* the state of the groups (which of them are on) is not in the web
  interface - it is in the state file, and `scripts/gen-mtrickle.sh` writes
  it (`GROUP_CUSTOM`, `GROUP_STREAMING`, `GROUP_AI`, `GROUP_GITHUB`,
  `GROUP_STEAM`).
* the state of the **subscriptions** (which lists are on) is in the template
  `magitrickle/magitrickle.yaml` - the script reads it and writes it into
  the state file. The changes that are made in the web interface of the
  daemon do **not** survive the daily run of the script (05:30): the
  template is what it reads. A list that is off in the template stays off,
  whatever the size of it is.

## A manual config instead of the installer

The state file of MagiTrickle holds two things: the **groups** and the
**subscriptions**. The groups are built by `scripts/gen-mtrickle.sh` out of
the rule-sets of the core and your own list, the subscriptions are the
lists that the daemon downloads.

If the state file is replaced by hand (or by the template of mixomo), the
subscriptions are **not** there - and the scheme works "by half": the
groups work, the lists of the subscriptions do not exist, and the services
of those lists are not proxied. The web interface shows it: the lists are
missing there and their status is "Never updated".

The check:

```shell
grep -c 'url:' /etc/magitrickle/state/config.yaml    # the number of the subscriptions
```

The way out:

```shell
sh /etc/mihomo/scripts/gen-mtrickle.sh
```

The template is `/etc/mihomo/magitrickle.yaml`, the state file is
`/etc/magitrickle/state/config.yaml` - the script writes both (the groups
and the subscriptions) and keeps the old state as `.bak`.

## Checks

```shell
sh /etc/mihomo/scripts/check-groups.sh          # the groups of the core
sh /etc/mihomo/scripts/mixomo-ipv6.sh status    # the device, its IPv6, the daemon
sh /etc/mihomo/scripts/mixomo-ram.sh            # the memory of the router
ipset list -n | grep mt_                         # the address sets of MagiTrickle
ip route show table 1298229097                   # the route of the marked traffic
ip link show Mihomo                              # the tunnel device
grep -c 'url:' /etc/magitrickle/state/config.yaml # the number of the subscriptions
```

The web interface of MagiTrickle is at `http://<the address of the router>:8080/`,
the dashboard of the core at `http://<the address of the router>:9090/ui`. The
address of the router depends on the settings of the LAN - see "The router".

## Troubleshooting

**The traffic of a site does not go through the proxy.**
The site is not on a list of MagiTrickle. Check the DNS: the client has to
use the DNS of the router, otherwise MagiTrickle never sees the request and
never marks the address.

**Nothing goes through the proxy.**
Check `service magitrickle status` and `service hev-socks5-tunnel status`.
The tunnel device `Mihomo` has to exist (`ip link show Mihomo`).

**The ads are not blocked.**
The group "Anti-AD" has to be on and its interface has to be `blackhole`.
After a change of the lists MagiTrickle needs a moment: the addresses are
filled from the DNS answers.

**The DNS of the clients fails.**
The client has to use the DNS of the router. `dnsmasq` must listen on port
53 and MagiTrickle has to be able to remap it.

**MagiTrickle dies every minute and the lists are not updated.**
The daemon was killed by the oom-killer of the kernel: it keeps every
domain of every list in its RAM, and the lists are too big for the router.
`sh /etc/mihomo/scripts/mixomo-ram.sh --log` shows the messages of the
kernel, and the section "The memory of the router" says what to do.

**The traffic of a list does not go through the proxy.**
The list was switched off because it does not fit into the memory of the
router. The state file says which lists are off:

```shell
grep -B4 'enable: false' /etc/magitrickle/state/config.yaml
```

**The daemon dies right after an update in the web interface.**
The daemon downloads the list of a subscription when the update is asked
for - **even when the subscription is switched off**. A big list that way
kills the daemon and the core with it (measured on the router). The URL of
a switched-off list in the state file points to nothing, so the update
fails at once and the daemon stays alive - see "The memory of the router".

**Both OpenClash and the scheme are running.**
Stop OpenClash: `service openclash stop && service openclash disable`. The
settings are in `/etc/config/openclash.bak.<pid>` if you need them.

## Back to OpenClash

```shell
service openclash enable && service openclash restart
```

The files of this scheme stay on the disk; they do not fight with OpenClash
as long as the services of the scheme are stopped:

```shell
service magitrickle stop
service hev-socks5-tunnel stop
service mihomo stop
```
