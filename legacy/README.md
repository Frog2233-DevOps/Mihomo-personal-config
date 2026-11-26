# The OpenClash layout (archived)

This branch keeps the layout that the repository had before the cleanup: the
configuration for **OpenClash**, where everything goes through the core
("the whole household behind the core").

It is not used on the router any more. The router runs the **mixomo** scheme
(MagiTrickle -> hev-socks5-tunnel -> mihomo), where only the selected traffic
goes into the core. The mixomo layout lives in `main`.

## Why it is kept

The two layouts share the rule-sets, the lists and the build script, so the
OpenClash part was not thrown away - it was moved here. The rollback is one
command:

```sh
git checkout legacy/openclash
```

## What is on this branch

| Path | What it is |
|---|---|
| `RU-Mihomo.yaml` | the config of the core for OpenClash (the source of truth) |
| `RU-Mihomo-lite.yaml`, `RU-Mihomo-smart.yaml` | the generated variants of it |
| `RU-Mihomo.conf` | the settings of the OpenClash installer (`DASHBOARD_PASSWORD`, the subscription URL) |
| `scripts/install.sh`, `scripts/deploy.sh`, `scripts/update-rulesets.sh` | the installer and the daily refresh of the OpenClash layout |
| `scripts/make-lite.sh`, `scripts/make-smart.sh` | the generators of the two variants |
| `scripts/selftest.sh`, `scripts/selftest.py` | the checks of the OpenClash config |
| `scripts/apply-rulesets.sh`, `scripts/check-groups.sh` | the OpenClash versions of the two scripts (the mixomo ones are in `main`) |
| `scripts/fix-exec.sh`, `scripts/fix-exec.ps1` | the copier that kept `automation/` and `.github/workflows/` in sync - the source of the silent rollbacks of CI |
| `automation/*.yml` | a byte copy of `.github/workflows/*.yml` |
| `tests/01_config.sh` ... `tests/08_rehearsal.sh` | the tests of the OpenClash layout |
| `docs/DESIGN*.md`, `docs/GROUPS*.md`, `docs/INSTALL*.md`, `docs/RULESETS*.md`, `docs/TEST-REPORT*.md` | the documentation of the OpenClash layout |

The rule-sets in `ruleset/` and the lists in `lists/` are shared by both
layouts and are still in `main`.

## The measurements of this layout

They are in `docs/TEST-REPORT.md` of this branch and in the history of
`main` before the cleanup:

* the core of the OpenClash layout keeps **52 MB** of RSS with the DNS policy
  on `rule-set:ru-domains` and **86 MB** with `geosite:category-ru`;
* the whole traffic of the household goes through the core, so the speed of
  the line and the UDP timeouts of the games are the problems that the mixomo
  scheme solves.

Do not merge this branch back into `main`: the two layouts are different
schemes, not two variants of one.
