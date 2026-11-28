# Схема mixomo

[English version](MIXOMO.md)

## Что это такое

Схема mixomo отправляет через ядро **только выбранный** трафик:

```
клиент -> MagiTrickle (DNS, помечает адреса из своих списков)
       -> hev-socks5-tunnel (tun "Mihomo")
       -> mihomo (mixed-port 7890) -> узел
```

Всё, чего нет в списках, идёт к провайдеру на полной скорости линии и ядро
не видит вообще. Ядро перестаёт быть роутером для всей домашней сети - оно
стало прокси для выбранного трафика.

Схема не наша. Это
[Internet-Helper/mixomo-openwrt](https://github.com/Internet-Helper/mixomo-openwrt)
(Apache 2.0), где
[MagiTrickle](https://gitlab.com/magitrickle/magitrickle) решает, что попадёт
в ядро. В этом репозитории лежит **конфигурация под эту схему**: конфиг
ядра, списки MagiTrickle и скрипты, которые всё это ставят на роутер.

## Зачем

Две проблемы схемы «весь трафик через ядро» (вариант OpenClash в этом
репозитории):

1. **Падает скорость.** Каждый пакет клиентов обрабатывается ядром: сверяются
   правила, отслеживаются соединения, DNS отвечает ядром. На Cudy WR3000S
   (MT7981, 256 МБ) ядро занимает 52-58 МБ RAM с полными списками правил, а
   у роутера всего 239 МБ.
2. **Теряются UDP-пакеты.** UDP-конвейер ядра - узкое место: Rust-сервер,
   который шлёт много UDP, получает timeout, потому что пакеты копятся в
   очереди ядра.

Обе проблемы из одного места: трафик идёт через ядро независимо от того,
нужен ему прокси или нет. В схеме mixomo через ядро идёт только выбранный
трафик, а остальное - напрямую провайдеру.

## Что меняется в конфиге

Первый столбец - раскладка OpenClash. В `main` её больше нет, она лежит в
ветке `legacy/openclash`. Сравнение осталось здесь, чтобы было видно, что
схема поменяла и почему.

| | раскладка OpenClash (`legacy/openclash`) | `RU-Mihomo-mixomo.yaml` |
|---|---|---|
| `mixed-port` | 7893 | **7890** - socks5-порт туннеля и значение, которое проверяет mixomo |
| `redir-port` | - | 5001 - прозрачный порт ядра |
| `routing-mark` | - | 2 - метка на соединениях ядра |
| `dns.listen` | 0.0.0.0:1053 | **0.0.0.0:7880** - DNS-порт схемы |
| `dns.enhanced-mode` | fake-ip | **redir-host** - см. ниже |
| `tun` | выключен | выключен - туннель принадлежит hev-socks5-tunnel |
| правила | `./ruleset/` | `./rule-files/` - каталог mixomo |
| провайдер | `./proxy_provider/` | `./proxy-providers/` - каталог mixomo |
| анти-ад | в ядре (`REJECT`) | **не в ядре** - роняет MagiTrickle |

### Почему redir-host, а не fake-ip

В fake-ip ядро отвечает адресом из 198.18.0.0/16. Клиент отправляет **весь**
свой трафик на эти адреса. Но в ядро попадают только те адреса, которые
пометил MagiTrickle, - остальные ушли бы с роутера на поддельный адрес и не
дошли бы никуда. То есть fake-ip принудительно возвращает схему «весь
трафик через ядро», а это ровно то, чего схема должна избегать.

При redir-host клиент получает настоящий адрес, MagiTrickle помечает тот же
настоящий адрес, а ядро восстанавливает домен из TLS-handshake (sniffer).
Цена - ещё один разбор handshake, выгода - ядро видит только выбранный
трафик.

### Почему анти-ада нет в ядре

В списке анти-ада 110 000 доменов. В ядре это стоит около 20 МБ его RAM и
время каждой сверки правил. MagiTrickle умеет ронять трафик сам (у группы
интерфейс `blackhole`), поэтому ядро его не видит и не держит в памяти.

Разница в поведении: ядро отвечает на рекламу сразу RST, роутер роняет
пакет и клиент ждёт таймаута. Если нужен быстрый ответ, раскомментируйте
rule-provider `antiad` в `RU-Mihomo-mixomo.yaml` **и** поменяйте интерфейс
группы "Anti-AD" в MagiTrickle с `blackhole` на `Mihomo`.

## Файлы

| Файл | Что это |
|---|---|
| `RU-Mihomo-mixomo.yaml` | конфигурация ядра для этой схемы |
| `magitrickle/magitrickle.yaml` | состояние MagiTrickle: группы и подписки |
| `magitrickle/magitrickle.mtrickle` | те же группы в JSON-формате веб-интерфейса |
| `scripts/setup-mixomo.sh` | ставит схему на роутер |
| `scripts/gen-mtrickle.sh` | пишет состояние MagiTrickle по rule-set'ам |
| `scripts/mixomo-ipv6.sh`, `scripts/mixomo-ipv6.init` | держат IPv6 туннельного устройства живым (без них демон умирает) |
| `scripts/update-mixomo.sh` | ежедневное обновление rule-set'ов |
| `scripts/apply-rulesets.sh` | говорит работающему ядру перечитать новые файлы |
| `scripts/check-groups.sh` | что попало в каждую группу ядра |
| `scripts/bypass-ports.sh`, `scripts/mixomo-bypass.init` | держат трафик перечисленных портов вне ядра |
| `scripts/build-ruleset.sh` | собирает rule-set'ы из исходных списков |
| `scripts/mixomo-ram.sh` | отчёт: память роутера, RSS обеих программ |
| `scripts/mixomo-memlimit.sh` | мягкий предел памяти (`GOMEMLIMIT`) ядра и демона |
| `scripts/selftest.sh`, `scripts/selftest.py` | `mihomo -t`, `shellcheck` и проверки консистентности |
| `docs/MIXOMO.md`, `docs/MIXOMO-RU.md` | этот документ, по-английски и по-русски |
| `docs/UPSTREAM-ISSUES.md` | тексты issues для апстрим-проектов (MagiTrickle) |
| `AGENTS.md` | правила, которые нельзя ломать |

## Установка

### 1. mixomo

```shell
curl -fsSL https://github.com/Internet-Helper/mixomo-openwrt/raw/main/install.sh | sh
```

Это ставит ядро, hev-socks5-tunnel, MagiTrickle и веб-интерфейс. Установщик
спрашивает, какая сборка MagiTrickle нужна: `Original` или `Mod`. Работают
обе - mod добавляет режим TPROXY и интерфейс `direct`, схема их не требует.

### 2. схема

```shell
curl -fsSL -o /tmp/setup-mixomo.sh \
  https://raw.githubusercontent.com/Frog2233-DevOps/Mihomo-personal-config/main/scripts/setup-mixomo.sh
SUB_URL='https://provider/subscribe' DASHBOARD_PASSWORD='your-password' \
  sh /tmp/setup-mixomo.sh
```

Скрипт:

* останавливает и отключает OpenClash (две схемы дерутся за таблицу
  маршрутизации; настройки сохраняются в `/etc/config/openclash.bak.<pid>`);
* ставит конфиг в `/etc/mihomo/config.yaml` (старый остаётся как
  `config.yaml.bak`);
* ставит 28 rule-set'ов в `/etc/mihomo/rule-files/`;
* пишет состояние MagiTrickle в `/etc/magitrickle/state/config.yaml`;
* ставит ежедневное обновление в crontab (05:30);
* запускает сервисы и проверяет результат.

Полезные переменные: `STOP_OPENCLASH=0` не трогает OpenClash,
`INSTALL_MIXOMO=1` доустанавливает mixomo, если его нет, `ENABLE_CRON=0`
не ставит crontab.

### 3. свои домены

```shell
vi /etc/mihomo/lists/custom-domains.list
sh /etc/mihomo/scripts/gen-mtrickle.sh
```

Список принадлежит вам: скрипт его никогда не перезаписывает.

## IPv6 туннельного устройства

Устройство `Mihomo` создаёт `hev-socks5-tunnel` при каждом старте туннеля.
Новое устройство наследует `net.ipv6.conf.default.disable_ipv6` от ядра,
поэтому на роутере с выключенным IPv6 устройство поднимается с выключенным
IPv6:

```
sysctl net.ipv6.conf.Mihomo.disable_ipv6   ->  1
```

MagiTrickle привязывает свои адресные сеты к этому устройству и добавляет
для него маршрут по умолчанию. Ядро отказывает в IPv6-маршруте устройства с
выключенным IPv6 и отвечает `-EACCES`, демон сдаётся:

```
failed to enable group: failed to link ipset to interface:
error adding iface route: permission denied
```

Замерено на роутере (Cudy WR3000S, OpenWrt 25.12.6):

```
all.disable_ipv6    = 1
default.disable_ipv6 = 1
br-lan.disable_ipv6 = 1
Mihomo.disable_ipv6 = 1   <- после /etc/init.d/hev-socks5-tunnel restart
```

**Что замерено на роутере сейчас** (Mod-сборка MagiTrickle, демон
0.5.2-badigit.18): демон **не умирает** при выключенном устройстве - он
пишет

```
no addresses on interface for current IP family, skipping route family=10 iface=Mihomo
```

и продолжает работать (замерено: демон жив, 11,8 МБ RSS). При
`disableIPv6: true` в состоянии демон вообще не пытается добавить маршрут и
этой строки нет (замерено: демон жив, 11,9 МБ RSS). Смерть с "permission
denied" была в исходном issue для этого роутера; на этой сборке она **не
воспроизвелась** - какая сборка её вызывала, здесь не проверялось.

Фикс схемы работает в обоих случаях: IPv6 включается на этом одном
устройстве (никогда глобально, никогда на `br-lan`), и у демона есть
адрес, с которым можно работать.

Это делают `scripts/mixomo-ipv6.sh` и init-скрипт `scripts/mixomo-ipv6.init`
(ставится как `/etc/init.d/mixomo-ipv6`):

* ждёт появления устройства (до `MIXOMO_IPV6_WAIT` секунд, по умолчанию
  60);
* включает IPv6 на этом одном устройстве и запускает MagiTrickle заново;
* устройство создаётся заново при каждом старте туннеля и снова
  поднимается с выключенным IPv6, поэтому состояние проверяется каждые
  `MIXOMO_IPV6_INTERVAL` секунд (30) и чинится, когда нужно.

Настройки лежат в `/etc/mihomo/mixomo.conf`:

```
FIX_IPV6=1              0 выключает фикс
MIXOMO_IPV6_WAIT=60     сколько ждать устройство
MIXOMO_IPV6_INTERVAL=30 как часто проверять состояние
```

Отчёт:

```shell
sh /etc/mihomo/scripts/mixomo-ipv6.sh status

device Mihomo: exists
  net.ipv6.conf.Mihomo.disable_ipv6 = 0
magitrickle: running
fix: on
```

Порядок старта: туннель (`START=99`) -> guard IPv6 (`START=99`) ->
MagiTrickle (`START=99`). Guard ждёт устройство, поэтому гонка на старте
роутера не страшна.

Второй слой защиты - сам файл состояния: `scripts/gen-mtrickle.sh` пишет
`app.netfilter.disableIPv6` из значения `IPV6` (`auto` по умолчанию: демон
не трогает IPv6, если на роутере IPv6 выключен).

## Списки MagiTrickle

Подписки MagiTrickle скачивает и обновляет сам:

| Список | Источник | Интерфейс | Что это |
|---|---|---|---|
| 🚫 RKN Blocked | Re-filter `domains_all.lst` | Mihomo | 81 460 доменов списка регистратора |
| 🚫 RKN Community | Re-filter `community.lst` | Mihomo | список сообщества (715 доменов) |
| 🛑 RKN IP | Re-filter `ipsum.lst` | Mihomo | 27 546 подсетей списка |
| 🛡 Anti-AD | anti-AD | **blackhole** | 110 000 рекламных доменов, роутер роняет сам |
| 💬 Telegram | itdoginfo | Mihomo | |
| 🎮 Discord | itdoginfo | Mihomo | |
| 📱 Meta | itdoginfo | Mihomo | Instagram, Facebook |
| 🧱 Roblox | itdoginfo | Mihomo | |
| 🤖 Google AI | itdoginfo | Mihomo | |
| ▶️ YouTube | itdoginfo | Mihomo | выключен по умолчанию |
| 🐦 Twitter | itdoginfo | Mihomo | выключен по умолчанию |

Локальные группы собирает `scripts/gen-mtrickle.sh` из rule-set'ов ядра:

| Группа | Источник | Включена по умолчанию |
|---|---|---|
| ⭐ Custom | `lists/custom-domains.list` | да |
| 🎬 Streaming | `ruleset/netflix.mrs` | да |
| 🤖 AI | `ruleset/{openai,anthropic,xai}.mrs` | да |
| 🐙 GitHub | `ruleset/github.mrs` | да |
| 🎮 Steam | `ruleset/steam.mrs` | нет |

Steam по умолчанию выключен: он из России доступен без прокси, и трафик этих
игр вообще не заходит в ядро. Каждую группу можно выключить при генерации
состояния (`GROUP_CUSTOM`, `GROUP_STREAMING`, `GROUP_AI`, `GROUP_GITHUB`,
`GROUP_STEAM`):

```shell
GROUP_STEAM=1 GROUP_GITHUB=0 sh /etc/mihomo/scripts/gen-mtrickle.sh
```

**Правило схемы**: сервис, которого нет в списках MagiTrickle, до ядра вообще
не доходит, и ни одно правило ядра на него не подействует. Хотите сервис
через прокси - занесите его в список.

## Источники списков

Подписки демон скачивает сам, по одному адресу на подписку:

| Список | Адрес |
|---|---|
| 🚫 RKN Blocked | `https://raw.githubusercontent.com/1andrevich/Re-filter-lists/main/domains_all.lst` |
| 🚫 RKN Community | `https://raw.githubusercontent.com/1andrevich/Re-filter-lists/main/community.lst` |
| 🛑 RKN IP | `https://raw.githubusercontent.com/1andrevich/Re-filter-lists/main/ipsum.lst` |
| 🛡 Anti-AD | `https://raw.githubusercontent.com/privacy-protection-tools/anti-AD/master/anti-ad-domains.txt` |
| остальные | itdoginfo |

Именно **ветка** репозитория, а не ассеты релиза: ассеты публикуются не
всегда (ассета `community.lst` вообще нет - замерено с роутера: 404, а
демон отвечал "failed to fetch subscription rules: unexpected status 404"), а
файл ветки - тот же самый файл (замерено: одинаковый md5 через оба адреса).

Проверка **с роутера** - у роутера свой путь в интернет, у компьютера
администратора может быть другой:

```shell
for u in \
  https://raw.githubusercontent.com/1andrevich/Re-filter-lists/main/domains_all.lst \
  https://raw.githubusercontent.com/1andrevich/Re-filter-lists/main/community.lst \
  https://raw.githubusercontent.com/1andrevich/Re-filter-lists/main/ipsum.lst ; do
  curl -sS -L --max-time 60 -o /dev/null -w '%{http_code} %{size_download}\n' "$u"
done
```

Замерено на роутере (Cudy WR3000S, OpenWrt 25.12.6):

| Адрес | Код | Строк | md5 |
|---|---|---|---|
| `releases/.../domains_all.lst` | 200 | 81 460 | c9b79dc0fde5829b2690450781a1ec2e |
| `main/domains_all.lst` | 200 | 81 460 | c9b79dc0fde5829b2690450781a1ec2e |
| `releases/.../ipsum.lst` | 200 | 27 546 | 0d1e2a41bb65888dc41a20e5191d75a2 |
| `main/ipsum.lst` | 200 | 27 546 | 0d1e2a41bb65888dc41a20e5191d75a2 |
| `releases/.../community.lst` | 404 | 1 | - |
| `main/community.lst` | 200 | 715 | c0b15a5af0a31a083addcace1251f8ec |

**Если адрес не отвечает:**

1. Проверьте его с роутера той командой выше. Таймаут на компьютере
   ничего не говорит о роутере.
2. На rule-set'ы ядра это не влияет: `scripts/build-ruleset.sh` пробует
   адреса по очереди (ветка, jsdelivr, прокси, релиз - релиз последним
   зеркалом).
3. У подписки MagiTrickle адрес **один** - список адресов демон не
   понимает. Если `raw.githubusercontent.com` с роутера не работает, выход -
   отдавать список с самого роутера:

   ```shell
   curl -fsSL -o /www/rkn.lst 'https://raw.githubusercontent.com/1andrevich/Re-filter-lists/main/domains_all.lst'
   # и в файле состояния:  url: http://127.0.0.1/rkn.lst
   ```

   Для этого надо выключить редирект на https у `uhttpd` (демон пойдёт по
   редиректу, а сертификат роутера не подходит к адресу - замерено:
   "tls: failed to verify certificate for 127.0.0.1 because it doesn't
   contain any IP SANs"):

   ```shell
   uci set uhttpd.main.redirect_https='0'
   uci commit uhttpd
   /etc/init.d/uhttpd restart
   ```

## Память роутера

MagiTrickle держит **каждый домен каждого списка в памяти демона** - а
роутеру нужно держать демона, ядро и систему одновременно. Списки схемы
большие: в `domains_all.lst` 81 460 строк, в `ipsum.lst` 27 546 подсетей, в
ad-листе 110 218.

Замерено на роутере (Cudy WR3000S, OpenWrt 25.12.6, 239 МБ RAM, MagiTrickle
0.8.2-r1, демон 0.5.2-badigit.18). Список грузился через API демона
(`PATCH /api/v1/subscription?id=...`), пик RSS читался из `/proc`:

| Список | Строк | Пик RSS | Итог |
|---|---|---|---|
| нет (только приложение) | - | 14,8 МБ | стабильно |
| 1 000 доменов | 1 000 | 27,0 МБ | ok |
| 2 000 доменов | 2 000 | 40,2 МБ | ok |
| 5 000 доменов | 5 000 | 77,4 МБ | ok |
| 5 000 доменов, `GOMEMLIMIT=64MiB` | 5 000 | 64,0 МБ | ok |
| 10 000 доменов | 10 000 | - | убит oom-killer'ом |
| 27 546 IP-подсетей | 27 546 | - | убит oom-killer'ом |
| 81 460 доменов | 81 460 | - | убит oom-killer'ом |
| 110 218 рекламных доменов | 110 218 | - | убит, вместе с ядром |

Это примерно **13 КБ RAM на каждый домен списка**. Ядро убивало демон при
94-111 МБ RSS (своп в этот момент был заполнен), а с ad-листом убивало и
ядро. Мёртвый демон ничего не скачивает: списки подписок остаются в том
состоянии, в котором были.

Что делает с этим схема:

* `scripts/gen-mtrickle.sh` считает домены локальных групп и строки
  списков **до** записи состояния. Каждый список, который не влезает в
  `MAX_DOMAINS` (по умолчанию 5 000), выключается, и скрипт говорит какой
  и почему:

  ```
  WARNING: the list "🚫 RKN Blocked" has 81460 lines, only 4800 are left: it is switched off
  ```

  Размер читается через `curl` (или `uclient-fetch`, или `wget` - что есть
  на роутере). При `PROBE=0` список не качается. Список, размер которого
  **не удалось** измерить, выключается: демон держит каждый домен списка в
  своей RAM, так что цена неверного предположения - это oom-killer (он
  забирает демона и ядро с собой), а цена выключенного списка - один
  неработающий список, пока его не включат руками.
* Группы схемы тоже выключаются, и каждый домен группы - это тоже RAM
  демона: `GROUP_CUSTOM`, `GROUP_STREAMING`, `GROUP_AI`, `GROUP_GITHUB`,
  `GROUP_STEAM`.
* Ad-лист следует за памятью роутера: `ANTI_AD=auto` (по умолчанию)
  выключает его на роутере с RAM меньше `MIN_RAM_MB` (384).
* `scripts/mixomo-memlimit.sh` задаёт `GOMEMLIMIT` ядру (96MiB) и демону
  (64MiB). Предел мягкий: сборщик мусора работает усерднее, вместо того
  чтобы ядро убивало процесс. С 5 000 доменов пик был 64,0 МБ с пределом и
  77,4 МБ без него.

**Выключенный список - это потеря**: трафик этих доменов больше не идёт
через прокси. Что делать:

| Ситуация | Что сделать |
|---|---|
| RKN-список не влезает | список меньшего размера, или роутер с большим объёмом RAM, или `MAX_DOMAINS` (и роутер, который это переживёт) |
| ad-лист не влезает | `ANTI_AD=0` и ad-лист в ядре: раскомментируйте `antiad` в `RU-Mihomo-mixomo.yaml` и поставьте группе "Anti-AD" интерфейс `Mihomo` |
| группы слишком большие | `GROUP_GITHUB=0`, `GROUP_STEAM=0`, ... |

**Выключенный список нельзя обновить руками.** Демон скачивает список
подписки, когда в веб-интерфейсе нажимают "обновить" - **даже если
подписка выключена**. С настоящим адресом большого списка такое обновление
убивает демона и ядро (замерено на роутере). Поэтому адрес выключенного
списка в файле состояния указывает в никуда
(`http://127.0.0.1:1/switched-off.lst`), а настоящий адрес и причина
остаются в комментарии рядом:

```yaml
  - id: 701cde4f
    name: "🚫 RKN Blocked"
    interface: Mihomo
    enable: false
    # the list has 81460 lines, only 4860 are left for the subscriptions - it is switched off
    # the original url: https://raw.githubusercontent.com/1andrevich/Re-filter-lists/main/domains_all.lst
    url: http://127.0.0.1:1/switched-off.lst
```

Замерено на роутере: ручное обновление выключенного списка отваливается с
разу ("connection refused"), демон остаётся жив (15,3 МБ RSS), событий
oom-killer'а нет.

Отчёт по памяти:

```shell
sh /etc/mihomo/scripts/mixomo-ram.sh          # цифры
sh /etc/mihomo/scripts/mixomo-ram.sh --log    # вместе с сообщениями oom-killer'а
```

Замеры выше - основа issue для апстрим-проекта (MagiTrickle): его текст
в [UPSTREAM-ISSUES.md](UPSTREAM-ISSUES.md).

## Порты, которые обходят ядро

Часть трафика вообще не должна заходить в ядро. Rust-сервер, который шлёт
много UDP, - пример из жизни: UDP-конвейер ядра - узкое место, и пакеты
игрового сервера теряются по дороге, соединение отваливается по таймауту.

В этой схеме трафик клиентов доходит до ядра только тогда, когда MagiTrickle
пометил его адрес. Трафик порта из списка ниже не доходит туда вообще:

```shell
vi /etc/mihomo/bypass-ports.txt     # по одному порту в строке
/etc/init.d/mixomo-bypass restart
```

Файл принадлежит вам - установщик его никогда не перезаписывает.
Установщик также принимает порты из командной строки:

```shell
BYPASS_PORTS='25565 28015' sh /tmp/setup-mixomo.sh
```

### Как это работает

`scripts/bypass-ports.sh` делает собственную цепочку и подключает её к
`PREROUTING` таблиц `mangle` и `nat` на первую позицию - перед цепочками
MagiTrickle:

```
-A MIXOMO_BYPASS ! -i lo -p udp --dport 25565 -m comment --comment mixomo-bypass -j ACCEPT
-I PREROUTING 1 -j MIXOMO_BYPASS
```

Две детали здесь не для красоты:

* **ACCEPT, а не RETURN.** `RETURN` из цепочки таблицы mangle означает лишь
  «вернуться в PREROUTING и смотреть дальше» - пакет, который MagiTrickle
  уже пометил, остался бы помеченным и всё равно ушёл бы в ядро. `ACCEPT`
  завершает обход таблицы, пакет идёт обычным маршрутом к провайдеру.
* **Первая позиция.** Цепочки MagiTrickle вставляются в `PREROUTING` тоже.
  Наше правило, стоящее перед ними, остаётся перед ними: MagiTrickle
  восстанавливает позицию своих цепочек после рестарта по правилам вокруг
  них (это «якоря»), и наш jump входит в этот якорь.

Init-скрипт `/etc/init.d/mixomo-bypass` сначала поднимает MagiTrickle и
только потом подключает правило; при установке он включается.

### Чего это не делает

Трафик этих портов ядро не видит, а значит, его не видят и правила ядра:
он не проксируется, не фильтруется и не блокируется списком РКН. В этом и
смысл - порт для сервера, к которому надо идти напрямую.

## Роутер

Адрес роутера не всегда `192.168.1.1` - он зависит от настроек LAN. На
роутере замеров этого документа это `192.168.25.1`. Установщик его не
угадывает - он берёт адрес `br-lan`:

```shell
ip -4 addr show br-lan | awk '/inet /{print $2}' | cut -d/ -f1
```

| Что | Где |
|---|---|
| веб-интерфейс MagiTrickle | `http://<адрес роутера>:8080/` |
| дашборд ядра | `http://<адрес роутера>:9090/ui` |

В OpenWrt 25.12 пакетный менеджер - **apk** (`opkg` там нет - замерено на
роутере: `/usr/bin/apk`, `opkg` отсутствует). Скрипты этого репозитория не
ставят ни одного пакета: им нужны ядро, `curl` и файлы схемы - а сам
mixomo знает оба пакетных менеджера.

## Сборка MagiTrickle: Original или Mod

Установщик mixomo спрашивает, какую сборку MagiTrickle ставить. С этой
схемой работают обе: Mod-сборка добавляет режим TPROXY и интерфейс
`direct`, схеме они не нужны.

Что лежит на роутере (замерено):

| Файл | Что это |
|---|---|
| `/etc/mixomo/templates/magitrickle-package-default.yaml` | состояние пакета |
| `/etc/mixomo/templates/magitrickle-groups-mod.yaml` | группы Mod-сборки |
| `/etc/mixomo/templates/magitrickle-groups-original.yaml` | группы Original-сборки |
| `/etc/mixomo/templates/magitrickle-template.active` | имя активного шаблона (`from-mixomo`) |
| `/etc/magitrickle/state/config.yaml.bak` | состояние до последней записи |

Правила, которые верны для обеих сборок:

* формат файла состояния одинаковый, `configVersion` начинается с `0.1.`
  (Mod-сборка не принимает ничего другого, Original берёт любой `0.*`);
* поля `dnsProxy.timeout` и `netfilter.ipset.additionalTTL` скриптом не
  пишутся: сборки читают их по-разному (длительность против числа секунд);
* файл `.mtrickle` (группы в JSON-формате веб-интерфейса) несёт
  **только группы**. Подписки в него не входят - после импорта файла
  списки подписок пустые, их надо создать заново (`scripts/setup-mixomo.sh`
  или руками в интерфейсе);
* состояние групп (какие из них включены) в веб-интерфейсе не хранится -
  оно в файле состояния, и его пишет `scripts/gen-mtrickle.sh`
  (`GROUP_CUSTOM`, `GROUP_STREAMING`, `GROUP_AI`, `GROUP_GITHUB`,
  `GROUP_STEAM`).
* состояние **подписок** (какие списки включены) живёт в шаблоне
  `magitrickle/magitrickle.yaml` - скрипт читает его и записывает в файл
  состояния. Правки, сделанные в веб-интерфейсе демона, **не переживают**
  ежедневный запуск скрипта (05:30): скрипт читает шаблон. Список, который
  в шаблоне выключен, остаётся выключенным, какого бы размера он ни был.

## Ручная подмена конфига вместо установщика

Файл состояния MagiTrickle держит две вещи: **группы** и **подписки**.
Группы `scripts/gen-mtrickle.sh` собирает из rule-set'ов ядра и вашего
списка, а подписки - это списки, которые скачивает демон.

Если файл состояния заменить руками (или шаблоном mixomo), подписок там
**не будет** - и схема работает «наполовину»: группы работают, списков
подписок нет, сервисы этих списков не проксируются. В веб-интерфейсе это
видно: списков нет, а их статус "Never updated".

Проверка:

```shell
grep -c 'url:' /etc/magitrickle/state/config.yaml    # сколько подписок
```

Выход:

```shell
sh /etc/mihomo/scripts/gen-mtrickle.sh
```

Шаблон - `/etc/mihomo/magitrickle.yaml`, файл состояния -
`/etc/magitrickle/state/config.yaml`; скрипт пишет оба (и группы, и
подписки) и хранит старое состояние в `.bak`.

## Проверки

```shell
sh /etc/mihomo/scripts/check-groups.sh          # группы ядра
sh /etc/mihomo/scripts/mixomo-ipv6.sh status    # устройство, его IPv6, демон
sh /etc/mihomo/scripts/mixomo-ram.sh            # память роутера
ipset list -n | grep mt_                         # наборы адресов MagiTrickle
ip route show table 1298229097                   # маршрут помеченного трафика
ip link show Mihomo                              # устройство туннеля
grep -c 'url:' /etc/magitrickle/state/config.yaml # сколько подписок
```

Веб-интерфейс MagiTrickle - `http://<адрес роутера>:8080/`, дашборд ядра -
`http://<адрес роутера>:9090/ui`. Адрес роутера зависит от настроек LAN -
см. раздел "Роутер".

## Проблемы

**Трафик сайта не идёт через прокси.**
Сайта нет в списках MagiTrickle. Проверьте DNS: клиент должен использовать
DNS роутера, иначе MagiTrickle не видит запрос и не помечает адрес.

**Через прокси не идёт вообще ничего.**
Проверьте `service magitrickle status` и `service hev-socks5-tunnel status`.
Устройство `Mihomo` должно существовать (`ip link show Mihomo`).

**Реклама не блокируется.**
Группа "Anti-AD" должна быть включена, а её интерфейс - `blackhole`.
После смены списков MagiTrickle нужно время: адреса наполняются из
DNS-ответов.

**DNS клиентов не работает.**
Клиент должен использовать DNS роутера. `dnsmasq` должен слушать порт 53,
и MagiTrickle должен уметь его перехватить.

**MagiTrickle умирает каждую минуту, списки не обновляются.**
Демона убивает oom-killer ядра: он держит каждый домен каждого списка в своей
памяти, а списки слишком большие для роутера.
`sh /etc/mihomo/scripts/mixomo-ram.sh --log` покажет сообщения ядра, а
раздел "Память роутера" - что делать.

**Трафик списка не идёт через прокси.**
Список выключен, потому что не влезает в память роутера. В файле состояния
видно, какие списки выключены:

```shell
grep -B4 'enable: false' /etc/magitrickle/state/config.yaml
```

**Демон умирает сразу после обновления в веб-интерфейсе.**
Демон скачивает список подписки, когда запрошено обновление - **даже если
подписка выключена**. Большой список таким способом убивает демона и ядро
(замерено на роутере). Адрес выключенного списка в файле состояния
указывает в никуда, поэтому обновление отваливается сразу, а демон остаётся
жив - см. раздел "Память роутера".

**Работают и OpenClash, и схема.**
Остановите OpenClash: `service openclash stop && service openclash disable`.
Настройки лежат в `/etc/config/openclash.bak.<pid>`.

## Назад на OpenClash

```shell
service openclash enable && service openclash restart
```

Файлы схемы остаются на диске; они не мешают OpenClash, пока сервисы схемы
остановлены:

```shell
service magitrickle stop
service hev-socks5-tunnel stop
service mihomo stop
```
