# Mihomo personal config — русская версия

Конфиг mihomo / OpenClash для роутера в России: российский трафик идёт
напрямую, заблокированный и зарубежный — через прокси, всё остальное
решается списками правил, которые ты собираешь сам.

Никаких моих подписок, никаких моих списков нод, никаких «премиумных»
endpoint'ов. Одна подписка, один конфиг, 28 ruleset'ов.

Сделан и измерен на **Cudy WR3000S v1** (MT7981BA, 256 МБ RAM, 128 МБ NAND,
OpenWrt 25.12.x, OpenClash v0.48.002, mihomo v1.19.33). Все цифры ниже
измерены, а не взяты из чужого README.

English version: [README.md](README.md).

## Чем этот конфиг отличается

**DNS-политика использует локальный rule-set, а не `geosite`.**
Очевидный способ отправить российские домены к российскому резолверу —
`nameserver-policy: "geosite:category-ru"`. Но тогда ядро скачивает
`GeoSite.dat` (4,3 МБ) и держит geosite-матчер в памяти:

| | RSS | Старт |
|---|---|---|
| `geosite:category-ru` | 86,4 МБ | 4598 мс |
| `rule-set:ru-domains` (как здесь) | **52,2 МБ** | **67 мс** |

Поведение то же, RAM меньше на 34 МБ. Проверено поломкой policy-резолвера:
российский домен отдаёт SERVFAIL, зарубежный отвечает — в обоих вариантах.

**Списки правил собираются, а не скачиваются.** Списки РКН приходят
«голыми» доменами (`instagram.com`), а в mihomo голый домен с
`behavior: domain` матчит **только сам этот домен** — `www.instagram.com`
проскакивает. Измерено: с голым списком 0 из 12 поддоменов совпало, с
префиксом `+.` — 12 из 12. Скрипт сборки добавляет префикс перед
конвертацией в `.mrs`; дефис остаётся допустимым символом домена, поэтому
такие записи, как `01-klinika-21.ru`, не теряются.

**Порядок правил выведен из пересечений, а не из вкуса.**

| # | Правило | Почему именно тут |
|---|---|---|
| 1 | `private`, `fake-ip-filter` -> DIRECT | сначала локалка |
| 2 | `custom-domains` -> `⭐ Custom` | **твоё** решение важнее любого списка |
| 3 | `antiad` -> REJECT | |
| 4 | сервисные группы | Telegram, Discord и AI-сервисы есть и в списке РКН (13, 22 и 15 пересекающихся доменов) — если правило РКН стоит раньше, выбрать им нод уже нельзя |
| 5 | `rkn-blocked` -> `🚫 RKN Blocked` | **перед** российскими доменами: `007dom.ru` российский по TLD, но в списке РКН — в обратном порядке он уйдёт напрямую в обход блокировки |
| 6 | `category-ai-ru` -> DIRECT | это российский AI (Алиса), а не OpenAI |
| 7 | `ru-domains`, `ru-ips` -> DIRECT | |
| 8 | `microsoft`, `apple` -> DIRECT | |
| 9 | `cdn` -> `🌐 CDN` | после российских доменов, чтобы CDN российских сервисов остались напрямую |
| 10 | QUIC -> REJECT | UDP-туннели нестабильны, TCP надёжнее |
| 11 | MATCH -> `🎯 Final` | |

**Российские ноды не попадают в автоматические группы.** РКН блокирует
трафик по российским сетям, поэтому российский exit-IP ничего не
разблокирует — он ломает ровно те сайты, ради которых этот конфиг и
существует. В `🎯 Manual` они остаются в один клик.

**Никаких тяжёлых регулярок.** В прошлой версии российские ноды
исключались lookahead-ом (`^(?!.*(?:...)).*$`) — это backtracking-регулярка
на каждом имени ноды. `exclude-filter` ядро вычитает из `filter`, так что
обычная альтернатива делает ту же работу.

**YAML-якоря.** Общие куски групп лежат в одном блоке `x-fragments`.
Проверено на настоящем `YAML.rb` из OpenClash: он раскрывает якоря при
чтении, сохраняет их при дампе, и результат по-прежнему проходит `mihomo -t`.

**Настройки безопасности не декоративные.** Пустой секрет дашборда
заставляет API отдавать `Access-Control-Allow-Origin: *` — любая веб-страница
в локалке может управлять прокси. Геобазы (16,5 + 4,4 МБ) выключены,
потому что этот конфиг их никогда не читает. Дашборд не качается, потому что
ядро распаковывает zip без проверки целостности.

Подробности и замеры: [docs/DESIGN-RU.md](docs/DESIGN-RU.md).

## Группы прокси

18 групп, в именах эмодзи. Полное описание — в
[docs/GROUPS-RU.md](docs/GROUPS-RU.md).

| Группа | Тип | Зачем |
|---|---|---|
| `🎯 Final` | select | входная точка, цель последнего правила |
| `🚀 Auto` | url-test | самый быстрый стабильный зарубежный нод |
| `⚡ Turbo` | url-test | tolerance 0, переключается быстрее — игры и звонки |
| `🔁 Failover` | fallback | держит первый ответивший нод |
| `🎯 Manual` | select | один конкретный нод, включая российские |
| `💬 Telegram` `🎮 Discord` `🤖 AI` | select | выбор нода под сервис |
| `▶️ YouTube` `🎬 Streaming` `🐙 GitHub` `📱 Social` | select | выбор нода под сервис |
| `🎮 Steam` `🧱 Roblox` `🕹️ Games` | select | выбор нода под сервис |
| `🌐 CDN` | select | CDN-хосты крупных провайдеров |
| `⭐ Custom` | select | **твои** домены, `lists/custom-domains.list` |
| `🚫 RKN Blocked` | select | заблокированные домены без своего сервиса |

## Три варианта

| Файл | Реклама | Ядро | RAM (измерено) |
|---|---|---|---|
| `RU-Mihomo.yaml` | да | Meta (апстрим) | 58 МБ |
| `RU-Mihomo-lite.yaml` | нет | Meta (апстрим) | **52 МБ** |
| `RU-Mihomo-smart.yaml` | да | Smart (форк vernesong) | зависит от модели |

Lite-вариант существует потому, что список рекламы — 102 005 доменов и
около 4 МБ RAM. Smart-варианту нужен бинарник `vernesong/mihomo`: апстрим
такой тип группы не знает.

`RU-Mihomo-lite.yaml` и `RU-Mihomo-smart.yaml` **генерируются**. Правь
`RU-Mihomo.yaml`, потом:

```sh
./scripts/make-lite.sh && ./scripts/make-smart.sh
```

## Плейсхолдеры

Задать надо две вещи, всё остальное уже имеет рабочие значения:

| Файл | Плейсхолдер | Что вписать |
|---|---|---|
| `RU-Mihomo.conf` -> `SUB_INFO_URL` | `PASTE_SUBSCRIPTION_URL_HERE` | ссылка на подписку |
| `RU-Mihomo.conf` -> строка `ruby_map_edit` | `PASTE_SUBSCRIPTION_URL_HERE` | та же ссылка |
| `RU-Mihomo.conf` -> `DASHBOARD_PASSWORD` | `CHANGE_ME` | свой пароль |
| `RU-Mihomo.yaml` -> `proxy-providers` -> `Main` -> `url` | `PASTE_SUBSCRIPTION_URL_HERE` | только если не используешь `RU-Mihomo.conf` |

Если меняешь URL в `RU-Mihomo.yaml`, пересобери два производных конфига —
иначе в них останется старая ссылка.

## Файлы

| Путь | |
|---|---|
| `RU-Mihomo.yaml` | основной конфиг, источник истины |
| `RU-Mihomo-lite.yaml` | генерируется, без списка рекламы |
| `RU-Mihomo-smart.yaml` | генерируется, под smart-ядро |
| `RU-Mihomo.conf` | файл перезаписи OpenClash: режим DNS, IPv6 выкл., пароль дашборда |
| `lists/custom-domains.list` | твои домены -> `ruleset/custom-domains.mrs` -> `⭐ Custom` |
| `ruleset/` | 28 собранных ruleset'ов, 1,5 МБ |
| `scripts/build-ruleset.sh` | пересобирает ruleset'ы из внешних списков |
| `scripts/make-lite.sh`, `scripts/make-smart.sh` | пересборка вариантов |
| `scripts/install.sh` | установка на роутер одной командой: скачивает конфиг, скрипты и все 28 rule-set'ов, подставляет плейсхолдеры и проверяет результат |
| `scripts/deploy.sh` | копирует конфиг и ruleset'ы на роутер по SSH |
| `scripts/check-groups.sh` | запуск на роутере: что попало в каждую группу |
| `scripts/update-rulesets.sh` | запуск на роутере: пересобирает ruleset'ы своим же ядром, ставит их и применяет - списки обновляются сами |
| `scripts/apply-rulesets.sh` | запуск на роутере: говорит работающему ядру перечитать конфиг (через API, без перезапуска) |
| `scripts/fix-exec.sh`, `scripts/fix-exec.ps1` | mark the scripts as executable (bash and PowerShell) |
| `scripts/selftest.sh` | `mihomo -t` каждого конфига + проверки фильтров, групп и файлов |
| `tests/run-all.sh` | полный набор регрессионных тестов (конфиги, нормализатор, скрипты, доки, воркфлоу); `tests/04_cycle.sh` проверяет цикл доставки на реальном роутере |
| `docs/DESIGN-RU.md` | почему принято каждое решение, с замерами |
| `docs/INSTALL-RU.md` | установка на OpenWrt / OpenClash |
| `docs/GROUPS-RU.md` | зачем нужна каждая группа |
| `docs/RULESETS-RU.md` | откуда списки и как они собираются |
| `docs/TEST-REPORT-RU.md` | отчёт о тестировании |
| `docs/DESIGN.md`, `docs/INSTALL.md`, `docs/GROUPS.md`, `docs/RULESETS.md`, `docs/TEST-REPORT.md` | то же самое на английском |
| `AGENTS.md` | правила, которые нельзя ломать — для ИИ-моделей и для людей |

## Цифры

| | |
|---|---|
| RAM, lite-конфиг | 52 МБ RSS (154 ноды) |
| RAM, полный конфиг | 58 МБ RSS |
| Голое ядро, без конфига | 45 МБ RSS |
| Ruleset'ы на флеше | 1,5 МБ |
| Время старта | 67 мс |
| Пересборка ruleset'ов | ежедневно, воркфлоу `rulesets.yml` |
| Флеш, всё вместе | ~46 МБ (OpenClash 10,7 + ядро 25-29 + ruleset'ы 1,5 + дашборд 3-5) |

## Как участвовать

Скрипты в репозитории лежат с исполняемым битом. Если после свежего клона его
нет (часть инструментов его теряет) — почини один раз:

```sh
bash scripts/fix-exec.sh          # Git Bash, Linux, macOS
```

На Windows — PowerShell, в корне репозитория:

```powershell
.\scripts\fix-exec.ps1
```

Сами скрипты написаны на bash, запускай их из Git Bash или WSL:

```sh
bash scripts/build-ruleset.sh
bash scripts/selftest.sh
bash tests/run-all.sh
```

Последнюю команду запускает и CI на каждом PR. С роутером (или с QEMU-эмулятором
WR3000S) можно проверить весь цикл доставки:

```sh
ROUTER_HOST=192.168.1.1 ROUTER_PORT=22 SECRET=<пароль> bash tests/04_cycle.sh
```

## Откуда берутся списки

* [1andrevich/Re-filter-lists](https://github.com/1andrevich/Re-filter-lists) — списки РКН
* [privacy-protection-tools/anti-AD](https://github.com/privacy-protection-tools/anti-AD) — домены рекламы
* [MetaCubeX/meta-rules-dat](https://github.com/MetaCubeX/meta-rules-dat) — готовые списки

## Лицензия

MIT, см. [LICENSE](LICENSE).
