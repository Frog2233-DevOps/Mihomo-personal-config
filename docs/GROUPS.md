# Proxy groups

18 groups. The emoji is part of the name - the names are the same in the
config, in the rules and in the dashboard.

## Entry

| Group | Type | Content | What it is for |
|---|---|---|---|
| `🎯 Final` | select | `🚀 Auto`, `⚡ Turbo`, `🔁 Failover`, `🎯 Manual`, `DIRECT` | The group the last rule (`MATCH`) points to. This is the switch you use every day. |

## Automatic

All three exclude the Russian nodes and the LTE / info nodes.

| Group | Type | Settings | What it is for |
|---|---|---|---|
| `🚀 Auto` | url-test | tolerance 50 ms, 300 s | The usual choice: the fastest node that stays stable. |
| `⚡ Turbo` | url-test | tolerance 0, 120 s | Switches faster and sticks to the fastest node even when the difference is small. For games and video calls. |
| `🔁 Failover` | fallback | 300 s | Keeps the first node that answers and only moves when it dies. The most stable, the least flexible. |

In the smart variant `🚀 Auto` is a `smart` group: it weighs the nodes by
its own measurements instead of only the latency.

## Manual

| Group | Type | Content | What it is for |
|---|---|---|---|
| `🎯 Manual` | select | every node of the subscription, the Russian ones included, without the LTE / info nodes | Pick one specific node. This group replaced the old `RU Nodes` group: a Russian exit is still one click away. |

## Services

Each of them is a `select` with the same three choices: `🚀 Auto`,
`🎯 Manual`, `DIRECT`. Pick `DIRECT` for a service that works without a
proxy, `🎯 Manual` for a service that needs a specific node.

| Group | Rule-set | Note |
|---|---|---|
| `💬 Telegram` | `telegram` | Telegram only cares about the exit IP, a Russian one is fine. |
| `🎮 Discord` | `discord` | Discord blocks Russian IPs, keep it on a foreign node. |
| `🤖 AI` | `openai`, `anthropic`, `google-gemini`, `xai` | The foreign AI services. The Russian ones (`category-ai-ru`) go direct. |
| `▶️ YouTube` | `youtube` | |
| `🎬 Streaming` | `netflix` | |
| `🐙 GitHub` | `github` | |
| `📱 Social` | `instagram`, `facebook`, `twitter` | |
| `🎮 Steam` | `steam` | |
| `🧱 Roblox` | `roblox` | |
| `🕹️ Games` | `category-games` | The games that have no list of their own. |

These groups come **before** the RKN list on purpose: Telegram, Discord and
the AI services are on the RKN list as well (13, 22 and 15 overlapping
domains). With the RKN rule first, choosing a node for them would be
unreachable.

## Special

| Group | Type | Content | What it is for |
|---|---|---|---|
| `🌐 CDN` | select | `🚀 Auto`, `🎯 Manual`, `DIRECT` | The CDN hostnames of the big providers. Switch it to `DIRECT` to save the traffic, or to a specific node. |
| `⭐ Custom` | select | `🚀 Auto`, `🎯 Manual`, `DIRECT` | The domains from `lists/custom-domains.list`. The rule for this list sits **above** the ad list and above the RKN list: your decision wins over every list. |
| `🚫 RKN Blocked` | select | `🚀 Auto`, `🎯 Manual`, `REJECT`, `DIRECT` | The domains that the RKN blocks and that have no service group of their own. `REJECT` cuts them off completely, `DIRECT` lets them through unblocked. |

## How a group is filled

The groups with `use: [Main]` take the nodes of the subscription and apply
their filters:

* `🎯 Manual` uses `noise-filter`: it drops the LTE servers and the
  subscription info nodes (traffic counters, expiry, tariffs).
* `🚀 Auto`, `⚡ Turbo` and `🔁 Failover` use `foreign-filter`: the same,
  plus the Russian nodes. A Russian exit IP does not unblock anything, so it
  would break exactly the sites this config exists to open.

The filters live on the groups and never on the provider: OpenClash
rewrites the provider filters from its own UI.

Check the result on the router with `scripts/check-groups.sh`.
