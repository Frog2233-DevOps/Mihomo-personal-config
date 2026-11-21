# Rule-sets

28 files in `ruleset/`, 1.5 MB in total. They are compiled from the lists
below by `scripts/build-ruleset.sh`.

## Built by the script

| File | Source | Behaviour |
|---|---|---|
| `rkn-blocked.mrs` | [1andrevich/Re-filter-lists](https://github.com/1andrevich/Re-filter-lists) - `domains_all.lst` | domain |
| `rkn-blocked-ip.mrs` | the same - `ipsum.lst` | ipcidr |
| `rkn-community.mrs` | the same - `community.lst` | domain |
| `anti-ad.mrs` | [privacy-protection-tools/anti-AD](https://github.com/privacy-protection-tools/anti-AD) - `anti-ad-domains.txt` | domain |
| `custom-domains.mrs` | `lists/custom-domains.list` in this repository | domain |

The first three and the ad list are **not** used as they are: every bare
domain gets the `+.` prefix (DOMAIN-SUFFIX) before the conversion, otherwise
only the exact domain would match and `www.instagram.com` would slip
through. Measured: with a bare list 0 of 12 subdomains matched, with the
prefix 12 of 12.

The ad list is the branch `master`, not `main`.

## Taken from MetaCubeX

From [MetaCubeX/meta-rules-dat](https://github.com/MetaCubeX/meta-rules-dat),
branch `meta`, path `geo/<category>/<name>.mrs`:

| File | Category |
|---|---|
| `category-ru.mrs` | geosite |
| `ru.mrs` | geoip |
| `private.mrs` | geoip |
| `telegram.mrs`, `discord.mrs`, `instagram.mrs`, `facebook.mrs`, `twitter.mrs` | geosite |
| `openai.mrs`, `anthropic.mrs`, `google-gemini.mrs`, `xai.mrs`, `category-ai-ru.mrs` | geosite |
| `youtube.mrs`, `netflix.mrs`, `github.mrs`, `microsoft.mrs`, `apple.mrs` | geosite |
| `category-games.mrs`, `steam.mrs`, `roblox.mrs` | geosite |
| `cdn.mrs` | geosite `category-cdn-!cn` (the CDN providers without the Chinese ones) |

`fake-ip-filter.mrs` comes from
[HenryChiao/mihomo_yamls](https://github.com/HenryChiao/mihomo_yamls).

## Rules for a rule-set in the config

```yaml
rule-providers:
  rkn-blocked:
    type: file
    behavior: domain       # never "classical" with format: mrs
    format: mrs
    path: ./ruleset/rkn-blocked.mrs
```

* `behavior: classical` together with `format: mrs` matches **nothing** and
  fails silently - 0 of 12 domains instead of 12 of 12.
* `behavior` and the content have to agree: a domain list with
  `behavior: ipcidr` does not work, and an IP rule-set in `fake-ip-filter`
  makes the core refuse to start.
* The paths are relative to the working directory of the core, which is
  `/etc/openclash` on the router.

## Rebuilding

```sh
./scripts/build-ruleset.sh          # -> ruleset/
./scripts/selftest.sh               # checks that every file exists
```

The script needs `mihomo` (for `convert-ruleset`) and internet access.

The GitHub Actions workflow `.github/workflows/rulesets.yml` does the same
every day and commits the result, so the rule-sets in the repository are
never older than a day.

## The custom list

`lists/custom-domains.list` is yours. One domain per line, `#` starts a
comment. The domains are routed through the `⭐ Custom` group, and that rule
is placed above the ad list and above the RKN list.

If the list is empty, the script writes a placeholder rule
(`custom-domains.invalid`, a reserved domain that can never resolve), because
`mihomo` refuses to convert an empty list - it panics with "empty rule" and
leaves a 0 byte file behind.
