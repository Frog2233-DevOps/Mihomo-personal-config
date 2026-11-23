# Rule-set'ы

[English](RULESETS.md) | **Русский**

28 файлов в `ruleset/`, 1,5 МБ суммарно. Они собираются из списков ниже
скриптом `scripts/build-ruleset.sh`.

## Собираются скриптом

| Файл | Источник | Behaviour |
|---|---|---|
| `rkn-blocked.mrs` | [1andrevich/Re-filter-lists](https://github.com/1andrevich/Re-filter-lists) — `domains_all.lst` | domain |
| `rkn-blocked-ip.mrs` | то же — `ipsum.lst` | ipcidr |
| `rkn-community.mrs` | то же — `community.lst` | domain |
| `anti-ad.mrs` | [privacy-protection-tools/anti-AD](https://github.com/privacy-protection-tools/anti-AD) — `anti-ad-domains.txt` | domain |
| `custom-domains.mrs` | `lists/custom-domains.list` из этого репозитория | domain |

Первые три и список рекламы используются **не как есть**: перед конвертацией
каждому «голому» домену добавляется префикс `+.` (DOMAIN-SUFFIX), иначе
совпадал бы только сам домен, а `www.instagram.com` проскакивал бы мимо.
Проверено замерами: с голым списком совпало 0 поддоменов из 12, с префиксом —
12 из 12.

Список рекламы лежит в ветке `master`, а не `main`.

## Берутся из MetaCubeX

Из [MetaCubeX/meta-rules-dat](https://github.com/MetaCubeX/meta-rules-dat),
ветка `meta`, путь `geo/<category>/<name>.mrs`:

| Файл | Категория |
|---|---|
| `category-ru.mrs` | geosite |
| `ru.mrs` | geoip |
| `private.mrs` | geoip |
| `telegram.mrs`, `discord.mrs`, `instagram.mrs`, `facebook.mrs`, `twitter.mrs` | geosite |
| `openai.mrs`, `anthropic.mrs`, `google-gemini.mrs`, `xai.mrs`, `category-ai-ru.mrs` | geosite |
| `youtube.mrs`, `netflix.mrs`, `github.mrs`, `microsoft.mrs`, `apple.mrs` | geosite |
| `category-games.mrs`, `steam.mrs`, `roblox.mrs` | geosite |
| `cdn.mrs` | geosite `category-cdn-!cn` (CDN-провайдеры без китайских) |

`fake-ip-filter.mrs` берётся из
[HenryChiao/mihomo_yamls](https://github.com/HenryChiao/mihomo_yamls).

## Правило для rule-set'а в конфиге

```yaml
rule-providers:
  rkn-blocked:
    type: file
    behavior: domain       # никогда "classical" вместе с format: mrs
    format: mrs
    path: ./ruleset/rkn-blocked.mrs
```

* `behavior: classical` вместе с `format: mrs` не совпадает **ни с чем** и
  молча ломается — 0 доменов из 12 вместо 12 из 12.
* `behavior` и содержимое должны совпадать: список доменов с
  `behavior: ipcidr` не работает, а IP-rule-set в `fake-ip-filter` заставляет
  ядро отказываться стартовать.
* Пути относительные — отсчитываются от рабочего каталога ядра, на роутере
  это `/etc/openclash`.

## Пересборка

```sh
./scripts/build-ruleset.sh          # -> ruleset/
./scripts/selftest.sh               # проверяет, что все файлы на месте
```

Скрипту нужны `mihomo` (для `convert-ruleset`) и интернет.

Workflow GitHub Actions `.github/workflows/rulesets.yml` делает то же самое
каждый день и коммитит результат, поэтому rule-set'ы в репозитории никогда не
старше суток.

## Свой список

`lists/custom-domains.list` — ваш. По одному домену в строке, `#` начинает
комментарий. Домены идут через группу `⭐ Custom`, и это правило стоит выше
списка рекламы и выше списка РКН.

Если список пустой, скрипт записывает заглушку
(`custom-domains.invalid` — зарезервированный домен, который не может
резолвиться), потому что `mihomo` отказывается конвертировать пустой список:
он падает с «empty rule» и оставляет файл в 0 байт.
