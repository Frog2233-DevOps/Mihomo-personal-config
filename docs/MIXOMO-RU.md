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

| | `RU-Mihomo.yaml` (OpenClash) | `RU-Mihomo-mixomo.yaml` |
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
| `scripts/update-mixomo.sh` | ежедневное обновление rule-set'ов |

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

## Списки MagiTrickle

Подписки MagiTrickle скачивает и обновляет сам:

| Список | Источник | Интерфейс | Что это |
|---|---|---|---|
| 🚫 RKN Blocked | Re-filter `domains_all.lst` | Mihomo | 82 000 доменов списка регистратора |
| 🚫 RKN Community | Re-filter `community.lst` | Mihomo | список сообщества |
| 🛑 RKN IP | Re-filter `ipsum.lst` | Mihomo | адреса списка |
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
| 🐙 GitHub | `ruleset/github.mrs` | нет |
| 🎮 Steam | `ruleset/steam.mrs` | нет |

GitHub и Steam из России доступны без прокси, поэтому они выключены: трафик
этих сайтов вообще не заходит в ядро. Включите их в веб-интерфейсе, если
хотите их через прокси.

**Правило схемы**: сервис, которого нет в списках MagiTrickle, до ядра вообще
не доходит, и ни одно правило ядра на него не подействует. Хотите сервис
через прокси - занесите его в список.

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

## Проверки

```shell
sh /etc/mihomo/scripts/check-groups.sh          # группы ядра
ipset list -n | grep mt_                         # наборы адресов MagiTrickle
ip route show table 1298229097                   # маршрут помеченного трафика
ip link show Mihomo                              # устройство туннеля
```

Веб-интерфейс MagiTrickle - `http://192.168.1.1:8080/`, дашборд ядра -
`http://192.168.1.1:9090/ui`.

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
