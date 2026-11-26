# The upstream issues

The texts below are prepared for the upstream projects. **They are not sent
from this repository** - the author sends them under their own name, so that
the measurements stay connected with the person who made them.

Two issues are prepared:

| # | Project | About |
|---|---|---|
| 1 | [MagiTrickle](https://gitlab.com/magitrickle/magitrickle) | the daemon dies when the tunnel device has IPv6 switched off |
| 2 | [MagiTrickle](https://gitlab.com/magitrickle/magitrickle) | the daemon keeps every domain of every list in RAM, is killed by the oom-killer and downloads the lists that are switched off |

---

## Issue 1: the daemon dies when the tunnel device has IPv6 switched off

**To:** <https://gitlab.com/magitrickle/magitrickle>
**Title:** the daemon dies with "error adding iface route: permission denied" when the interface has IPv6 disabled

The daemon does not survive a router with IPv6 switched off. It adds a
default IPv6 route to the interface it is given, and the kernel refuses the
route of a device with IPv6 disabled - the daemon gives up and exits.

The message of the log:

```
failed to enable group: failed to link ipset to interface: error adding iface route: permission denied
```

### Where it comes from

The interface is not a real device of the router - it is the tun device of
`hev-socks5-tunnel`, and it is created at the start of the tunnel, every
time. A new device inherits `net.ipv6.conf.default.disable_ipv6`, so on a
router with IPv6 switched off the device comes up with IPv6 disabled:

```
/proc/sys/net/ipv6/conf/default/disable_ipv6 = 1
/proc/sys/net/ipv6/conf/Mihomo/disable_ipv6   = 1   (after the tunnel starts)
```

The daemon tries to add the IPv6 route of that device and dies.

### What is expected

The daemon should not manage IPv6 at all when the router has IPv6 switched
off. There is a setting for that - `app.netfilter.disableIPv6` in the state
file - and with `disableIPv6: true` the daemon starts and stays alive on
such a router.

### What was measured

Router: Cudy WR3000S, OpenWrt 25.12.6, aarch64, 239 MB of RAM.
MagiTrickle 0.8.2-r1, daemon 0.5.2-badigit.18 (the Mod build).

```
all.disable_ipv6    = 1
default.disable_ipv6 = 1
br-lan.disable_ipv6 = 1
Mihomo.disable_ipv6 = 1   <- after /etc/init.d/hev-socks5-tunnel restart
```

**The death was not reproduced with this build.** With the device disabled
the daemon does not die - it writes

```
no addresses on interface for current IP family, skipping route family=10 iface=Mihomo
```

and keeps working (measured: the daemon is running, 11.8 MB of RSS). The
same happens with `disableIPv6: true` in `app.netfilter` - and there the
message is not there at all, because the daemon does not even try the
route.

So the report of the death ("permission denied") belongs to a build that
was not identified here. The question below is therefore still open:
which build dies, and how does the daemon have to treat a device with
IPv6 disabled - by skipping the route (what the Mod build does), or by
dying (what the report says)?

The setting `app.netfilter.disableIPv6` is not the answer for everybody:
the daemon of the original build is started by the package of the router
only when it is enabled in the settings of the router, and the setting is
read differently by the two builds (it is checked here, not measured in
every combination).

The workaround that is used now: a guard script that waits for
`/sys/class/net/Mihomo`, switches IPv6 on for this one device and restarts
the daemon (it is in the mixomo repository, not here).

### The question

Is the setting `app.netfilter.disableIPv6` read the same way in the original
build (0.8.2) and in the Mod build? And could the daemon itself skip the
IPv6 route when the device has IPv6 disabled, instead of dying?

---

## Issue 2: the daemon keeps every domain of every list in RAM

**To:** <https://gitlab.com/magitrickle/magitrickle>
**Title:** the daemon is killed by the oom-killer of the kernel when the subscriptions are updated (about 13 kB of RAM for every domain)

The daemon downloads the list of every subscription and keeps every domain
of it in its RAM. On a small router the kernel kills it - and a dead daemon
updates nothing at all, so the lists of the subscriptions stay at the state
they had.

### Where it comes from

The lists of a subscription are big. The lists of the mixomo scheme:

| List | Lines |
|---|---|
| `domains_all.lst` (the RKN list) | 81 460 |
| `ipsum.lst` (the addresses of the RKN list) | 27 546 subnets |
| the ad list | 110 218 |

### What was measured

Router: Cudy WR3000S, OpenWrt 25.12.6, aarch64, 239 MB of RAM (131 MB of
swap). MagiTrickle 0.8.2-r1, daemon 0.5.2-badigit.18.

The list was loaded through the API of the daemon
(`PATCH /api/v1/subscription?id=...`), the peak of the RSS was read from
`/proc/<pid>/status`:

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
the daemon at 94-111 MB of RSS (the swap was full at the same time):

```
kern.err kernel: Out of memory: Killed process 17183 (magitrickled)
  total-vm:1301580kB, anon-rss:95548kB, oom_score_adj:0
```

With the ad list the kernel took the core of the proxy with it:

```
kern.err kernel: Out of memory: Killed process 5863 (mihomo)
  total-vm:1458200kB, anon-rss:27132kB, oom_score_adj:0
kern.err kernel: Out of memory: Killed process 18644 (magitrickled)
  total-vm:1433940kB, anon-rss:111104kB, oom_score_adj:0
```

### A list that is switched off is still downloaded

The daemon downloads the list of a subscription when the user asks for an
update in the web interface - **even when the subscription is switched
off**. Measured on the router: the subscription `🚫 RKN Blocked`
(`enable: false`) was updated by hand through the API of the daemon, the
daemon loaded the 81 460 domains of it, and the oom-killer took the daemon
and the core of the proxy with it.

So "switched off" is not a protection in the daemon: the address of the
list is still there and still works. It would be much safer if the daemon
did not download a list of a subscription that is switched off (or if it
refused the list with a warning about its size).

`GOMEMLIMIT=64MiB` for the daemon lowers the peak (77.4 MB -> 64.0 MB with
5 000 domains), but it does not make a big list fit: the limit is soft, the
garbage collector works harder, and the data of the list is live.

### What is expected

Some way to keep the daemon inside the memory of the router. Ideas (any of
them would help, the order is not important):

* a limit for the number of the domains of one subscription, with a warning
  when the list is bigger (the size of the list is known before it is
  loaded - it is the number of the lines of the answer);
* the domains of a list are not needed in full: the daemon could keep the
  list on the disk and look the domains up there, or keep a compressed
  representation (a prefix tree, a hash of the domain);
* the rules of a subscription could be handed over to the core as a
  rule-set (a `.mrs` file), and the daemon would keep only the domains that
  it has to answer for;
* a warning in the log of the daemon, when the memory of the process grows
  over a limit that the user can set.

The workaround that is used now: the size of every list is measured with
`curl` before the state file is written, and every list that does not fit
into the limit is switched off (`MAX_DOMAINS`, 5 000 by default). It is in
the mixomo repository, not here.
