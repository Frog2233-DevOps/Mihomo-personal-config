# Mihomo personal config — русская версия

Конфиг mihomo / OpenClash для роутера, который стоит в России: российский
трафик идёт напрямую, заблокированный и зарубежный — через прокси, а всё
остальное решается списками правил, которые ты собираешь сам.

Сделан и измерен на **Cudy WR3000S v1** (MT7981BA, 256 МБ RAM, 128 МБ NAND,
OpenWrt 25.12.x, OpenClash v0.48.002).

English version: [README.md](README.md).

## Что лежит в репозитории

| Путь | Что это |
|---|---|
| `RU-Mihomo.yaml` | Основной конфиг. Реклама блокируется. Это тот, который надо использовать. |
| `RU-Mihomo-lite.yaml` | Генерируется из основного без списка рекламы (~4 МБ меньше RAM). |
| `RU-Mihomo-smart.yaml` | Генерируется из основного для *smart*-ядра (vernesong/mihomo). |
| `RU-Mihomo.conf` | Файл перезаписи OpenClash: режим DNS, IPv6 выключен, пароль дашборда. |
| `lists/custom-domains.list` | **Твои** домены. Для них свой ruleset и своя группа. |
| `ruleset/` | Собранные rule-set'ы (`.mrs`), 28 файлов, 1,5 МБ. |
| `scripts/build-ruleset.sh` | Пересобирает `ruleset/` из внешних списков и твоего списка. |
| `scripts/make-lite.sh` | Пересобирает `RU-Mihomo-lite.yaml`. |
| `scripts/make-smart.sh` | Пересобирает `RU-Mihomo-smart.yaml`. |
| `scripts/deploy.sh` | Копирует конфиг и ruleset'ы на роутер по SSH. |
| `scripts/check-groups.sh` | Запускается на роутере: показывает, что попало в каждую группу. |
| `scripts/selftest.sh` | Проверяет всё: `mihomo -t`, фильтры, группы, файлы. |
| `docs/DESIGN.md` | Почему принято каждое решение. Каждое утверждение измерено. |
| `docs/INSTALL.md` | Установка на OpenWrt / OpenClash по шагам. |
| `docs/GROUPS.md` | Зачем нужна каждая группа прокси. |
| `docs/RULESETS.md` | Откуда берутся списки и как они собираются. |
| `AGENTS.md` | Файл контекста для ИИ-моделей, которые работают с репозиторием. |
| `.github/workflows/` | Два воркфлоу GitHub: `validate` (проверяет все конфиги при каждом пуше и пул-реквесте) и `rulesets` (ежедневно пересобирает ruleset'ы). |
| `automation/` | Те же два воркфлоу отдельными файлами — чтобы их можно было смотреть в PR. Меняешь один — меняй и второй: `cp automation/*.yml .github/workflows/` |
| `README-RU.md` | Эта же документация на русском. |

## Плейсхолдеры, которые надо заменить

Задать надо ровно две вещи: **ссылку на подписку** и **пароль дашборда**.
Всё остальное уже имеет рабочие значения по умолчанию.

| Файл | Плейсхолдер | Что вписать | Обязательно? |
|---|---|---|---|
| `RU-Mihomo.conf` → `SUB_INFO_URL` | `PASTE_SUBSCRIPTION_URL_HERE` | ссылка на подписку | **да** |
| `RU-Mihomo.conf` → строка `ruby_map_edit` | `PASTE_SUBSCRIPTION_URL_HERE` | та же ссылка на подписку | **да** |
| `RU-Mihomo.conf` → `DASHBOARD_PASSWORD` | `CHANGE_ME` | свой пароль | **да** |
| `RU-Mihomo.yaml` → `proxy-providers` → `Main` → `url` | `PASTE_SUBSCRIPTION_URL_HERE` | ссылка на подписку | только если не используешь `RU-Mihomo.conf` |
| `RU-Mihomo.yaml` → `secret` | `CHANGE_ME` | тот же пароль | нет, OpenClash перезаписывает |
| `RU-Mihomo.yaml` → `authentication` | `mihomo:CHANGE_ME` | свой пароль | нет, OpenClash подставляет случайный |
| `lists/custom-domains.list` | — | свои домены, по одному в строке | нет |

Почему пароль дашборда нельзя оставлять пустым: при пустом `secret` API
mihomo отдаёт `Access-Control-Allow-Origin: *`, то есть **любая** веб-страница,
открытая в твоей сети, может управлять прокси, читать список соединений и
менять настройки.

Если ты меняешь ссылку на подписку **в `RU-Mihomo.yaml`**, пересобери два
производных конфига, иначе в них останется старая ссылка:

```sh
./scripts/make-lite.sh
./scripts/make-smart.sh
```

`RU-Mihomo-lite.yaml` и `RU-Mihomo-smart.yaml` — генерируемые файлы. Руками их
не правь: следующая сборка перезапишет твои изменения.

## Установка

### 0. Сначала проверь разметку флеша

Ядро `mihomo` для arm64 занимает 57,5 МБ, а в UBIFS — 25-29 МБ. Вместе с
OpenClash, ruby и ruleset'ами оно **не влезает** в стандартную разметку
роутера с 128 МБ NAND.

| Разметка | Overlay |
|---|---|
| standard | 44 МБ — не влезает |
| ubootmod | 84,8 МБ — нужна эта |

Если у тебя стандартная разметка, сначала прошей образ `ubootmod`. Процедура
описана в исходниках OpenWrt:
`package/boot/uboot-mediatek/patches/468-add-cudy_wr3000s-v1.patch` и
коммиты [openwrt/openwrt#22625](https://github.com/openwrt/openwrt/pull/22625)
(вошли в 25.12.4). Официальный образ профиля `cudy_wr3000s-v1-ubootmod`
есть для 25.12.5 и 25.12.6.

Проверить:

```sh
df -h /overlay
```

### 1. Установи OpenClash

OpenClash v0.48.002 публикует и `.apk`, и `.ipk`. На OpenWrt 25.12.6 ставь
`.apk`:

```sh
cd /tmp
wget https://github.com/vernesong/OpenClash/releases/download/v0.48.002/luci-app-openclash-0.48.002.apk
apk add --allow-untrusted ./luci-app-openclash-0.48.002.apk
```

Зависимости `.apk` есть в репозиториях 25.12.6 для `aarch64_cortex-a53`:
`libc`, `dnsmasq-full`, `bash`, `curl`, `ca-bundle`, `ip-full`, `ruby`,
`ruby-yaml`, `kmod-tun`, `unzip`.

После установки плагин появляется в LuCI: *Сервисы -> OpenClash*. При первом
старте он генерирует случайный пароль дашборда и секцию `authentication`.

### 2. Скопируй конфиг и ruleset'ы на роутер

Со своего компьютера:

```sh
ssh root@192.168.1.1 'mkdir -p /etc/openclash/config /etc/openclash/ruleset /etc/openclash/backup'
scp RU-Mihomo.yaml root@192.168.1.1:/etc/openclash/config/
scp RU-Mihomo.conf root@192.168.1.1:/etc/openclash/
scp ruleset/*.mrs  root@192.168.1.1:/etc/openclash/ruleset/
```

Пути к ruleset'ам в конфиге относительные (`./ruleset/...`) — они
разрешаются относительно рабочего каталога ядра, а на роутере это
`/etc/openclash`.

### 3. Впиши подписку и пароль дашборда

Отредактируй `/etc/openclash/RU-Mihomo.conf` на роутере:

```ini
[General]
# единственная подписка
SUB_INFO_URL = https://your-provider/subscription-link

# пароль дашборда и API. НЕ пусто: при пустом секрете API отдаёт
# "Access-Control-Allow-Origin: *".
DASHBOARD_PASSWORD = your-own-password

# какой конфиг использовать: RU-Mihomo.yaml (с блокировкой рекламы) или
# RU-Mihomo-lite.yaml (примерно на 4 МБ меньше RAM, без рекламы)
CONFIG_FILE = /etc/openclash/config/RU-Mihomo.yaml
```

Потом импортируй файл перезаписи в LuCI: *OpenClash -> Управление
конфигурациями -> Скачать конфигурацию*, укажи raw-ссылку на
`RU-Mihomo.conf` — или положи файл в `/etc/openclash/backup/` и выбери его в
настройках перезаписи.

Если файл перезаписи не нужен, впиши подписку прямо в `RU-Mihomo.yaml`:

```yaml
proxy-providers:
  Main:
    url: 'https://your-provider/subscription-link'
```

и задай `secret` и `authentication` сам. Тогда за паролем API следишь ты.

### 4. Запусти и проверь

```sh
/etc/init.d/openclash restart
```

Дождись в логе готовности ядра и проверь, что попало в группы:

```sh
scp scripts/check-groups.sh root@192.168.1.1:/etc/openclash/
ssh root@192.168.1.1 'sh /etc/openclash/check-groups.sh'
```

Скрипт печатает каждую группу с её узлами и предупреждает, если в группу
просочился нод, которым нельзя пользоваться (LTE-сервер, служебный нод), или
если в автоматической группе оказался российский нод. Нормальный результат:

* `🚀 Auto`, `⚡ Turbo`, `🔁 Failover` — только зарубежные ноды;
* `🎯 Manual` — все ноды, включая российские, но без LTE и служебных;
* сервисные группы — `🚀 Auto`, `🎯 Manual`, `DIRECT`.

RAM и флеш:

```sh
ssh root@192.168.1.1 'ps | grep -i mihomo'      # RSS в последней колонке
ssh root@192.168.1.1 'df -h /overlay'           # свободный флеш
ssh root@192.168.1.1 'logread | grep -i mihomo | tail -30'
```

Ориентиры (154 ноды, zram 168 МБ): lite **52 МБ** RSS, полный **58 МБ** RSS,
голое ядро ~45 МБ.

### 5. Обновляй ruleset'ы

На роутере через cron (роутеру нужен доступ в интернет к GitHub):

```sh
crontab -e
# каждое утро в 5:31
31 5 * * * /usr/bin/mihomo convert-ruleset ... # см. scripts/build-ruleset.sh
```

Проще — воркфлоу GitHub Actions в этом репозитории:
`.github/workflows/rulesets.yml` пересобирает ruleset'ы каждый день и
коммитит их. Чтобы он ещё и заливал их на роутер, добавь секреты репозитория
`ROUTER_HOST`, `ROUTER_USER`, `ROUTER_PORT`, `ROUTER_PATH` и
`SSH_PRIVATE_KEY` — воркфлоу сам вызовет `scripts/deploy.sh`.

Локально:

```sh
./scripts/build-ruleset.sh
./scripts/selftest.sh
```

### 6. Smart-ядро (по желанию)

`RU-Mihomo-smart.yaml` требует форка
[vernesong/mihomo](https://github.com/vernesong/mihomo/releases): апстрим такой
тип группы не знает (`unsupported type: smart`).

В OpenClash выставь тип ядра *Smart* — `CORE_TYPE = Smart` в
`RU-Mihomo.conf` — и положи на роутер `RU-Mihomo-smart.yaml` вместо
`RU-Mihomo.yaml`.

Модель LightGBM — 9,3 МБ, а `prefer-asn: true` заставляет ядро качать
`ASN.mmdb` (8,7 МБ). На роутере с маленьким флешем оставь оба выключенными:
smart-группа ранжирует ноды по собственным замерам и без них.

## Если что-то пошло не так

**В группах нет нод.** Не загрузилась подписка. Смотри
`logread | grep -i openclash` и URL в `SUB_INFO_URL`. Адреса самих прокси
резолвятся напрямую (`77.88.8.8`), поэтому сломанный DNS делает недоступной
всю подписку.

**Правило не срабатывает.** `mihomo -t` не проверяет, существуют ли файлы
списков. Ищи в логе «rule set ... not found» и прогони
`./scripts/selftest.sh` — он проверяет файлы.

**Дашборд просит пароль, которого ты не знаешь.** Это `DASHBOARD_PASSWORD` из
`RU-Mihomo.conf` (или случайный, который OpenClash сгенерил при установке).

**После каждого старта конфиг выглядит иначе.** Это OpenClash: он
переписывает DNS, `fake-ip-filter`, `hosts`, sniffer и `authentication` при
каждом старте. Поэтому в `RU-Mihomo.conf` выключена его собственная обработка
DNS (`ENABLE_CUSTOM_DNS = 0`, `CUSTOM_FAKEIP_FILTER = 0`,
`CUSTOM_NAME_POLICY = 0`).

**Хочу свой фильтр нод.** Вешай его на *группы*, а не на провайдер:
OpenClash переписывает фильтры провайдера из своего интерфейса.

**Группы пропали после того, как я заглянул в интерфейс OpenClash.**
OpenClash пересобирает весь блок `proxy-groups:` из своего хранилища. Не
создавай группы прокси в интерфейсе, когда используешь этот конфиг.

## Три варианта

| Файл | Реклама | Ядро | RAM (измерено) |
|---|---|---|---|
| `RU-Mihomo.yaml` | да | Meta (апстрим) | 58 МБ |
| `RU-Mihomo-lite.yaml` | нет | Meta (апстрим) | 52 МБ |
| `RU-Mihomo-smart.yaml` | да | Smart (форк vernesong) | зависит от модели |

Lite-вариант существует потому, что список рекламы — это 102 005 доменов и
около 4 МБ RAM: на роутере с 128 МБ это важно. Smart-варианту нужен бинарник
`vernesong/mihomo`, апстрим такой тип группы не знает.

## Измеренные на роутере цифры

| | |
|---|---|
| RAM у lite-конфига | 52 МБ RSS (154 ноды) |
| RAM у полного конфига | 58 МБ RSS |
| Голое ядро, без конфига | 45 МБ RSS |
| Флеш под ruleset'ы | 1,5 МБ |
| Флеш под пакет OpenClash | 10,7 МБ |
| Время старта | 67 мс (без геобазы) |

Геобазы выключены намеренно: `GeoIP.dat` — 16,5 МБ, `GeoSite.dat` — 4,4 МБ, а
этот конфиг их никогда не читает.

## Откуда берутся списки

* [1andrevich/Re-filter-lists](https://github.com/1andrevich/Re-filter-lists) — списки РКН
* [privacy-protection-tools/anti-AD](https://github.com/privacy-protection-tools/anti-AD) — домены рекламы
* [MetaCubeX/meta-rules-dat](https://github.com/MetaCubeX/meta-rules-dat) — готовые списки

## Лицензия

MIT, см. [LICENSE](LICENSE).
