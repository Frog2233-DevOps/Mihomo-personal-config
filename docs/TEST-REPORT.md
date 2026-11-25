# Integration test report (2026-11-23)

[Русская версия](TEST-REPORT-RU.md)

## Environment

The target hardware was not available, so the tests ran on a **real QEMU
emulation of the Cudy WR3000S v1 board**, not on a simulated config parser:

| | |
|---|---|
| Emulator | `github.com/stavultras/router-emulator` v4.1, machine `mt7981-router` |
| Source of the emulator | 4pda topic 1087457, post #10376; flash folder `nand-wr3000s` from the Yandex Disk archive linked there |
| Guest | OpenWrt 25.12.5, kernel 6.12.94, aarch64, 256 MB RAM, 84.8 MB overlay |
| Host | aarch64, mihomo Meta v1.19.33 (same version as the project target) |
| Test subscription | local HTTP server with five nodes: two foreign, one Russian, one LTE, one "Traffic remaining" info node |

The official Cudy web emulator (`support.cudy.com/emulator/WR3000S`) was
checked and rejected: it only simulates the stock firmware web UI and cannot
run OpenWrt, OpenClash or mihomo.

To run headless on this host the emulator's bundled dynamic loader had to be
bypassed (it failed to bind the QEMU monitor Unix socket); the machine itself
booted normally.

## Findings, all reproduced before fixing

| # | Problem | Fact that proved it | Severity |
|---|---|---|---|
| 1 | `normalize()` in `build-ruleset.sh` used `^[A-Za-z0-9_.]+$`, dropping every domain with a hyphen and all punycode | 20 833 of 82 146 RKN lines, 66 of 714 community lines, 8 373 of 110 923 anti-AD lines lost on the 2026-11-23 lists. A rebuild with the old regex produced a **byte-identical** `rkn-blocked.mrs` (SHA256 `3145bf8d…`) to the committed one | high: blocked sites were not blocked |
| 2 | `fix-exec.sh` / `.ps1` copied stale `automation/*.yml` over `.github/workflows/*.yml` | Running the documented "fix" reverted the `MIHOMO` env vars and `bash ./scripts/deploy.sh` | medium: CI silently lost fixes |
| 3 | `deploy.sh` passed ssh's `-p <port>` to `scp`, where `-p` means "preserve times" | `scp: stat local "8022": No such file or directory` with `ROUTER_PORT=8022` | high: deploy impossible on a non-default port |
| 4 | The `scp -O` detection (`scp -h | grep -- '-O'`) never matched | `ash: /usr/libexec/sftp-server: not found` on the router | high: deploy impossible from OpenSSH 9+ |
| 5 | `build-ruleset.sh` counted bytes with GNU `stat -c%s` | The router build printed `Bytes: 0` for a 1.8 MB directory | low: misleading output |
| 6 | `check-groups.sh` accepted a 401 body as a valid answer | Every group printed `NOT FOUND`, then both warnings printed a false `OK` | high: false "everything fine" |
| 7 | `check-groups.sh`'s `uclient-fetch` fallback used `-o` instead of `-O` and sent no Authorization header | No authenticated answer without curl | medium: broken fallback |
| 8 | `apply-rulesets.sh` searched the process list for the first line containing "clash" or "mihomo" | On the router its own path is `/etc/openclash/scripts/apply-rulesets.sh` - the script found ITSELF, found no `-f` in it and gave up ("the running config was not found") | high: the rule-sets were never applied, only the restart fallback ran |
| 9 | `build-ruleset.sh` could only download with `curl` | A plain OpenWrt has no curl; the daily cron would fail with "curl: not found" | medium: the daily refresh dies without a package |

Findings 1 and 2 were already fixed on `dev` by PR #4 before this round;
findings 3-7 were found during the emulator run and are fixed in this change.

## Fixes

* `scripts/deploy.sh`: `-p` for `ssh`, `-P` for `scp`; `do_scp()` tries `-O`
  first and falls back to plain `scp` for older clients.
* `scripts/build-ruleset.sh`: byte counts use POSIX `wc -c`.
* `scripts/check-groups.sh`: rejects any answer without `"proxies"`; the
  `uclient-fetch` fallback uses `-O` and passes the Bearer token.
* `scripts/apply-rulesets.sh`: the process search takes the first command line
  that contains `-f ` **and** whose file exists - the script can no longer find
  itself (its path contains "openclash").
* `scripts/build-ruleset.sh`: the downloader is chosen at runtime - `curl`,
  `uclient-fetch` (busybox) or `wget`.
* `tests/`: new regression suite, wired into `.github/workflows/validate.yml`
  (and its `automation/` copy) so CI runs it on every pull request.
* Docs: EN/RU installation, design and README updated; troubleshooting got
  entries for all new findings; `AGENTS.md` got rules 13-15 and the test
  commands.

## Tests

`bash tests/run-all.sh` (all green):

| Suite | Checks | What it covers |
|---|---|---|
| `01_config.sh` | 19 | `mihomo -t`, consistency, forbidden patterns, rule order, rule-set files, generated variants |
| `02_normalize.sh` | 14 | real `normalize()` function: hyphens, punycode, wildcards, `+.` prefixes, junk, CRLF, sort/uniqueness, shipped `.mrs` size |
| `03_scripts.sh` | 20 | shell syntax; **functional** deploy test with stub `scp`/`ssh` proving `-P`, `-p`, `-O`; busybox counter; API validation; no secret in logs |
| `04_cycle.sh` | 13 (on the emulator) | deploy to a non-default port, layout, 28 rule-sets, live rule providers, bad-secret rejection, fixed router scripts |
| `05_docs.sh` | 28 | EN/RU pairs, section parity, full lifecycle, troubleshooting, AI-agent notes |
| `06_workflows.sh` | 8 | workflow copies byte-identical, guard, apply step, CI entry point |
| `07_install.sh` | 35 | installer syntax/POSIX, rule-set list sync, a real local HTTP install, placeholder escaping with special characters, no credentials in the log, reinstall safety, all variants, atomic failure |
| `08_rehearsal.sh` | 27 | the whole router cycle on this machine: `install.sh` into a router-like layout, the ruby rewrite OpenClash does, the core starts, `check-groups.sh`, `update-rulesets.sh` rebuilding with the router's own core, the apply through the API without a restart, the rules still matching |

`scripts/selftest.sh` also passes with the real core. The CI (non-router)
part of `tests/run-all.sh` is now 157 checks; the optional router cycle adds
13 more.

`08_rehearsal.sh` is the suite that found findings 8 and 9: it runs the
scripts of the router in the layout of the router, against a real core and a
real ruby rewrite. It needs `MIHOMO`, `python3` and (optionally) `ruby`:

```sh
MIHOMO=/path/to/mihomo bash tests/08_rehearsal.sh
```

The ports are chosen per run, so a leftover core of an earlier run cannot
steal the API of this one.

The installer also wires the daily refresh into the router's crontab when
`ROOT=/etc/openclash` (or `ENABLE_CRON=1`). The GitHub workflow only commits
new rule-sets to the repository - there are no router secrets configured here,
so without the router cron the device would keep stale lists forever.
Verified with a stub `crontab` (other entries kept, no duplicate on reinstall)
and on the live emulator: one `update-rulesets.sh` line after two installs.

## One-command installer

`scripts/install.sh` was added because the installation guide described every
step but there was no single command to perform them. It runs on the router
under POSIX `sh`, downloads the config, the overwrite file, four helper
scripts, the custom list and all 28 `.mrs` files into a temporary directory,
substitutes the URL and the password, then installs them into the OpenClash
layout. It keeps the user's custom list, backs up a modified config as `.bak`,
never prints credentials and leaves the existing setup untouched if any
download fails.

It was also verified as an unprivileged user with a custom ROOT.

It was verified twice: by `tests/07_install.sh` against a local HTTP server
(35 checks, including `|`, `&` and `\` in the credentials and the three
variants), and on the live emulated router with `BASE_URL` pointing at the
host. The router run installed all 28 rule-sets, wrote `secret: testpass`
and the subscription URL verbatim, marked the scripts executable and skipped
`mihomo -t` because no core was installed in the test root.

### What was verified on the live emulated router

* 28 rule providers / 252 793 rules loaded by mihomo v1.19.33; RSS 37 MB with
  five nodes.
* A request to `01-klinika-21.ru` was logged as
  `match RuleSet/rkn-blocked` — the hyphenated domain is really blocked now.
* `check-groups.sh`: foreign nodes in `🚀 Auto` / `⚡ Turbo` / `🔁 Failover`,
  the Russian node only in `🎯 Manual`, no LTE or "Traffic remaining" node
  anywhere.
* `update-rulesets.sh APPLY=reload`: rebuilt all 28 rule sets with the
  router's own core, installed them and reloaded the running core through
  `PUT /configs?force=true` without a restart.
* Wrong dashboard password: `check-groups.sh` now exits 1 with an explicit
  error instead of reporting false `OK`.

## Documentation status

`README.md` / `README-RU.md`, `docs/DESIGN.md` / `DESIGN-RU.md`,
`docs/INSTALL.md` / `INSTALL-RU.md`, `docs/GROUPS.md` / `GROUPS-RU.md`,
`docs/RULESETS.md` / `RULESETS-RU.md` and this report are complete EN/RU
pairs with matching section counts. The installation guide covers the whole
cycle (install, config, subscription, start, rule-set refresh, apply, check),
troubleshooting and verification. `AGENTS.md` contains 15 rules, the DNS
scheme, the node filters and instructions for AI agents.
