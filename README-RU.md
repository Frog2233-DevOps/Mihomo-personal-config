# Mihomo personal config

Конфигурация mihomo для схемы **mixomo** на роутере в России: через ядро
идёт только выбранный трафик, всё остальное уходит провайдеру на полной
скорости линии.

```
клиент -> MagiTrickle (DNS, метит адреса своих списков)
        -> hev-socks5-tunnel (tun "Mihomo")
        -> mihomo (mixed-port 7890) -> нода
```

Никаких подписок и списков нод в репозитории нет. Одна подписка, один
конфиг, 28 rule-set'ов.

Собрано и измерено на **Cudy WR3000S v1** (MT7981BA, 239 МБ RAM + 131 МБ
swap, OpenWrt 25.12.6, mixomo v0.3.4, MagiTrickle 0.8.2, hev-socks5-tunnel
2.20.0, mihomo v1.19.34). Все цифры ниже измерены, а не взяты из чужого
README.

Схема не наша: это
[Internet-Helper/mixomo-openwrt](https://github.com/Internet-Helper/mixomo-openwrt)
(Apache 2.0) и
[MagiTrickle](https://gitlab.com/magitrickle/magitrickle) - часть, которая
решает, что попадёт в ядро. В этом репозитории лежит **конфигурация для этой
схемы**: конфиг ядра, списки MagiTrickle и скрипты, которые всё это
устанавливают на роутер.

## Установка

```sh
# 1. сама схема
curl -fsSL https://github.com/Internet-Helper/mixomo-openwrt/raw/main/install.sh | sh

# 2. конфигурация из этого репозитория
curl -fsSL -o /tmp/setup-mixomo.sh \
  https://raw.githubusercontent.com/Frog2233-DevOps/Mihomo-personal-config/main/scripts/setup-mixomo.sh
SUB_URL='https://your-provider/subscribe' DASHBOARD_PASSWORD='your-password' \
  sh /tmp/setup-mixomo.sh
```

Скрипт скачивает конфиг, скрипты и все 28 rule-set'ов, подставляет
заглушки, пишет состояние MagiTrickle, ставит ежедневное обновление и
проверяет результат. Он никогда не печатает адрес подписки и никогда не
печатает пароль.

Адрес роутера не фиксирован: он зависит от настроек LAN (`192.168.1.1` -
это только дефолт). Установщик берёт его из `br-lan`.

Подробности: [docs/MIXOMO-RU.md](docs/MIXOMO-RU.md).

## Что здесь особенного

**Через ядро идёт только выбранный трафик.** Раскладка, где через ядро идёт
*всё* (OpenClash, она лежит в ветке `legacy/openclash`), сопоставляет правила
для каждого пакета в домохозяйстве и отслеживает каждое соединение. Именно
поэтому падает скорость и теряются UDP-пакеты. Здесь MagiTrickle отвечает на
DNS, метит адреса своих списков, и в ядро попадает только помеченное.

**DNS-политика использует локальный rule-set, а не `geosite`.** Очевидный
способ отправить российские домены к российскому резолверу -
`nameserver-policy: "geosite:category-ru"`. Тогда ядро скачивает
`GeoSite.dat` (4.3 МБ) и держит в RAM матчер geosite:

| | RSS | старт |
|---|---|---|
| `geosite:category-ru` | 86.4 МБ | 4598 мс |
| `rule-set:ru-domains` (этот конфиг) | **52.2 МБ** | **67 мс** |

Поведение то же, RAM меньше на 34 МБ. Проверено поломкой резолвера: российский
домен отдаёт SERVFAIL, зарубежный резолвится - в обоих вариантах.

**Рекламы в ядре нет.** MagiTrickle режет её интерфейсом `blackhole`, так что
~110 000 доменов не попадают ни в RAM ядра, ни в его правила. Ядро вообще не
загружает `anti-ad.mrs`.

**Списки правил собираются, а не скачиваются.** Списки РКН отдают голые
домены (`instagram.com`), а в mihomo голый домен с `behavior: domain`
совпадает **только** с этим точным доменом - `www.instagram.com` проходит
мимо. Измерено: с голым списком совпало 0 из 12 поддоменов, с префиксом
`+.` - 12 из 12. Скрипт сборки добавляет префикс перед конвертацией в
`.mrs`; дефисы остаются в наборе символов домена, поэтому записи вроде
`01-klinika-21.ru` не теряются.

**Порядок правил выведен из пересечений, а не из вкуса.**

| # | Правило | Почему здесь |
|---|---|---|
| 1 | `private` -> DIRECT | сначала LAN |
| 2 | `custom-domains` -> `⭐ Custom` | **ваше** решение важнее любого списка |
| 3 | сервисные группы | Telegram, Discord и ИИ-сервисы тоже в списке РКН (13, 22 и 15 пересекающихся доменов) - если правило РКН стоит раньше, выбор ноды для них недостижим |
| 4 | `rkn-blocked` -> `🚫 RKN Blocked` | **перед** российскими доменами: `007dom.ru` российский по TLD, но в списке РКН - в обратном порядке он ушёл бы мимо блокировки |
| 5 | `category-ai-ru` -> DIRECT | это российский ИИ (Алиса), а не OpenAI |
| 6 | `ru-domains`, `ru-ips` -> DIRECT | |
| 7 | `microsoft`, `apple` -> DIRECT | |
| 8 | `cdn` -> `🌐 CDN` | после российских доменов, чтобы CDN российских сервисов остались напрямую |
| 9 | QUIC -> REJECT | UDP-туннели нестабильны, TCP надёжнее |
| 10 | MATCH -> `🎯 Final` | |

Правило `games` стоит **выше** списка РКН: 121 его домен есть и в списке
РКН, и 51 - в списке Roblox. Без него эти 172 домена поменяли бы группу.

**Российские ноды не в автоматических группах.** РКН блокирует трафик по
российским сетям, поэтому российский exit IP ничего не разблокирует - он
сломал бы ровно те сайты, ради которых конфиг и нужен. Они на один клик
дальше, в `🎯 Manual`.

**Никаких тяжёлых регулярных выражений.** В старой версии российские ноды
исключались lookahead'ом (`^(?!.*(?:...)).*$`) - это backtracking-регулярка
на каждом имени ноды. `exclude-filter` вычитается из `filter` ядром, поэтому
обычная альтернатива делает ту же работу.

**Значения по умолчанию не декоративные.** Пустой секрет дашборда заставляет
API отвечать с `Access-Control-Allow-Origin: *` - любая страница в LAN может
управлять прокси. Гео-базы (16.5 + 4.4 МБ) выключены, потому что этот конфиг
их не читает.

## Группы прокси

18 групп, с эмодзи в названиях.

| Группа | Тип | Для чего |
|---|---|---|
| `🎯 Final` | select | входная группа, цель последнего правила |
| `🚀 Auto` | url-test | самая стабильная быстрая зарубежная нода |
| `⚡ Turbo` | url-test | tolerance 0, переключается быстрее - игры и звонки |
| `🔁 Failover` | fallback | держит первую ответившую ноду |
| `🎯 Manual` | select | одна конкретная нода, включая российские |
| `💬 Telegram` `🎮 Discord` `🤖 AI` | select | выбор ноды по сервису |
| `▶️ YouTube` `🎬 Streaming` `🐙 GitHub` `📱 Social` | select | выбор ноды по сервису |
| `🎮 Steam` `🧱 Roblox` `🕹️ Games` | select | выбор ноды по сервису |
| `🌐 CDN` | select | CDN-имена больших провайдеров |
| `⭐ Custom` | select | **ваши** домены, `lists/custom-domains.list` |
| `🚫 RKN Blocked` | select | заблокированные домены без своего сервиса |

Сервис, которого нет ни в одном списке MagiTrickle, в ядро не попадает:
правила ядра решают только судьбу уже выбранного трафика. Локальные группы
(Custom, Streaming, AI, GitHub, Steam) собираются из rule-set'ов скриптом
`scripts/gen-mtrickle.sh`.

## Заглушки

Задать нужно две вещи, у остального рабочие значения по умолчанию:

| Где | Заглушка | Что подставить |
|---|---|---|
| `RU-Mihomo-mixomo.yaml` -> `proxy-providers` -> `Main` -> `url` | `PASTE_SUBSCRIPTION_URL_HERE` | адрес вашей подписки |
| `RU-Mihomo-mixomo.yaml` -> `secret` | `CHANGE_ME` | пароль вашего дашборда |

`scripts/setup-mixomo.sh` подставляет оба значения из `SUB_URL` и
`DASHBOARD_PASSWORD`.

## Файлы

| Путь | |
|---|---|
| `RU-Mihomo-mixomo.yaml` | конфиг ядра для схемы - единственный файл, который правят руками |
| `magitrickle/magitrickle.yaml` | шаблон состояния MagiTrickle: группы и подписки |
| `magitrickle/magitrickle.mtrickle` | те же группы в JSON-формате веб-интерфейса |
| `lists/custom-domains.list` | ваши домены -> `ruleset/custom-domains.mrs` -> `⭐ Custom` |
| `lists/bypass-ports.list` | порты, которые не доходят до ядра |
| `ruleset/` | 28 собранных rule-set'ов, 1.7 МБ |
| `scripts/setup-mixomo.sh` | ставит схему на роутер: конфиг, rule-set'ы, состояние MagiTrickle, cron и проверки |
| `scripts/gen-mtrickle.sh` | пишет состояние MagiTrickle из rule-set'ов и вашего списка |
| `scripts/update-mixomo.sh` | работает на роутере: пересобирает rule-set'ы и состояние MagiTrickle и перезагружает ядро |
| `scripts/build-ruleset.sh` | пересобирает rule-set'ы из исходных списков |
| `scripts/apply-rulesets.sh` | работает на роутере: говорит работающему ядру перечитать конфиг через его же API, без перезапуска |
| `scripts/check-groups.sh` | работает на роутере: что попало в каждую группу |
| `scripts/bypass-ports.sh`, `scripts/mixomo-bypass.init` | держат трафик перечисленных портов вне ядра |
| `scripts/selftest.sh`, `scripts/selftest.py` | `mihomo -t`, проверки конфига и `shellcheck` для скриптов роутера |
| `tests/run-all.sh` | полный регрессионный набор схемы |
| `docs/MIXOMO.md`, `docs/MIXOMO-RU.md` | схема, установка, замеры, troubleshooting |
| `AGENTS.md` | правила, которые нельзя ломать, для ИИ-моделей и для людей |

Раскладка OpenClash (конфиг для схемы «всё через ядро») лежит в ветке
`legacy/openclash`.

## Цифры

Измерено на роутере (Cudy WR3000S v1, 239 МБ RAM, mihomo v1.19.34):

| | |
|---|---|
| RAM, ядро с конфигом схемы | 60.7 МБ RSS (среднее трёх прогонов) |
| RAM, ядро с «lite»-вариантом | 60.8 МБ RSS - экономии нет, вариант удалён |
| RAM, rule-set'ы на флеше | 1.7 МБ в 28 файлах |
| Rule-set'ы пересобираются | ежедневно, workflow `rulesets.yml` |

Цифры по демону, по oom-killer'у и замеры списков - в
[docs/MIXOMO-RU.md](docs/MIXOMO-RU.md).

## Contribution

Скрипты закоммичены с битом исполнения. Shell-скрипты и списки хранятся с
LF (`.gitattributes`) - CRLF в них ломает их на роутере.

```sh
bash scripts/selftest.sh    # mihomo -t, shellcheck, проверки консистентности
bash tests/run-all.sh       # полный набор - это же гоняет CI
```

## Источники списков правил

* [1andrevich/Re-filter-lists](https://github.com/1andrevich/Re-filter-lists) - списки РКН
* [privacy-protection-tools/anti-AD](https://github.com/privacy-protection-tools/anti-AD) - домены рекламы
* [MetaCubeX/meta-rules-dat](https://github.com/MetaCubeX/meta-rules-dat) - готовые списки

## License

MIT, см. [LICENSE](LICENSE).
