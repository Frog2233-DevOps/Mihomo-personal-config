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

| | `RU-Mihomo.yaml` (OpenClash) | `RU-Mihomo-mixomo.yaml` |
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
| `scripts/update-mixomo.sh` | the daily refresh of the rule-sets |

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

## The lists of MagiTrickle

The subscriptions are downloaded and refreshed by MagiTrickle itself:

| List | Source | Interface | Meaning |
|---|---|---|---|
| 🚫 RKN Blocked | Re-filter `domains_all.lst` | Mihomo | 82 000 domains of the list of the registrar |
| 🚫 RKN Community | Re-filter `community.lst` | Mihomo | the community list |
| 🛑 RKN IP | Re-filter `ipsum.lst` | Mihomo | the addresses of the list |
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
| 🐙 GitHub | `ruleset/github.mrs` | no |
| 🎮 Steam | `ruleset/steam.mrs` | no |

GitHub and Steam are reachable from Russia without a proxy, so they are off:
the traffic of these sites then never touches the core. Turn them on in the
web interface if you want them through the proxy.

**The rule of the scheme**: a service that is not on a list of MagiTrickle
does not reach the core at all, so no rule of the core can change it. When
you want a service through the proxy, put it into a list.

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

## Checks

```shell
sh /etc/mihomo/scripts/check-groups.sh          # the groups of the core
ipset list -n | grep mt_                         # the address sets of MagiTrickle
ip route show table 1298229097                   # the route of the marked traffic
ip link show Mihomo                              # the tunnel device
```

The web interface of MagiTrickle is at `http://192.168.1.1:8080/`, the
dashboard of the core at `http://192.168.1.1:9090/ui`.

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
