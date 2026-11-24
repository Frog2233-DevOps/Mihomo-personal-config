# Установка

[English](INSTALL.md) | **Русский**

Цель: OpenWrt 25.12.x на роутере с SoC MediaTek MT798x, OpenClash v0.48.002.
Проверено на **Cudy WR3000S v1**.

Всё ниже сверено с исходниками OpenClash v0.48.002 и с работающим роутером.

Команды используют `192.168.1.1` — стандартный адрес OpenWrt. Подставьте свой
(или алиас из `~/.ssh/config`).

**Про `scp -O`.** OpenSSH 9 и новее копирует по SFTP, а в штатном dropbear
OpenWrt нет `sftp-server`. Поэтому во всех `scp` ниже есть `-O` (классический
протокол SCP).

---

## Быстрая установка

После установки OpenClash (раздел 1) всю конфигурацию можно положить на роутер
одним скриптом:

```sh
curl -fsSL -o /tmp/install.sh \
  https://raw.githubusercontent.com/Frog2233-DevOps/Mihomo-personal-config/main/scripts/install.sh
# прочитай /tmp/install.sh перед запуском — он пришёл из сети
SUB_URL='https://your-provider/subscription-link' \
DASHBOARD_PASSWORD='your-own-password' \
  sh /tmp/install.sh
```

Скрипт работает прямо на роутере под `sh` (не нужны bash, python или jq) и:

* скачивает `RU-Mihomo.yaml`, `RU-Mihomo.conf`, четыре вспомогательных
  скрипта, `lists/custom-domains.list` и все 28 собранных rule-set'ов;
* подставляет URL подписки и пароль дашборда в конфиг и в файл перезаписи
  (учётные данные никогда не выводятся на экран);
* раскладывает файлы по путям OpenClash, сохраняет существующий свой список
  доменов, а изменённый конфиг копирует в `.bak`;
* проверяет количество файлов и запускает `mihomo -t`, если ядро уже есть.

Ничего не ставится, пока все загрузки не завершатся успешно: при сбое сети
текущая конфигурация остаётся нетронутой.

Параметры: `VARIANT=lite|smart` (по умолчанию `full`), `BRANCH=dev` для
интеграционной ветки, `REPO=owner/repo` для форка, `ROOT=<dir>` для другого
каталога конфига. Например:

```sh
VARIANT=lite BRANCH=dev SUB_URL='...' DASHBOARD_PASSWORD='...' sh /tmp/install.sh
```

Скрипт **не** ставит OpenClash, не перепрошивает роутер, не меняет разметку
флеша (раздел 0) и не запускает OpenClash. После его работы импортируйте файл
перезаписи в LuCI и перезапустите плагин, как описано в разделе 4. Для ручной
установки следуйте разделам 2-5.

---

## 0. До старта: разметка флеша решает всё

Бинарник `mihomo` для arm64 — 57,5 МБ, в UBIFS занимает 25–29 МБ. Вместе с
OpenClash, ruby и rule-set'ами в стандартную разметку роутера с 128 МБ NAND
он не влезает.

| Разметка | Overlay |
|---|---|
| standard | 44 МБ — **не влезает** |
| ubootmod | 84,8 МБ — нужна эта |

Разметка `ubootmod` двигает раздел UBI с 64 MiB на 122,25 MiB и даёт ~50 МБ
свободного места. Процедура описана в исходниках OpenWrt:
`package/boot/uboot-mediatek/patches/468-add-cudy_wr3000s-v1.patch` и в
сообщениях коммитов [openwrt/openwrt#22625](https://github.com/openwrt/openwrt/pull/22625)
(вошло в 25.12.4). Официальный образ для профиля
`cudy_wr3000s-v1-ubootmod` есть для 25.12.5 и 25.12.6.

---

## 1. Установить OpenClash

OpenClash v0.48.002 публикует и `.apk`, и `.ipk`. На OpenWrt 25.12.6 ставьте
`.apk`:

```sh
cd /tmp
wget https://github.com/vernesong/OpenClash/releases/download/v0.48.002/luci-app-openclash-0.48.002.apk
apk add --allow-untrusted ./luci-app-openclash-0.48.002.apk
```

Зависимости `.apk` (все есть в репозиториях 25.12.6 для
`aarch64_cortex-a53`): `libc`, `dnsmasq-full`, `bash`, `curl`, `ca-bundle`,
`ip-full`, `ruby`, `ruby-yaml`, `kmod-tun`, `unzip`.

После установки плагин лежит в LuCI: *Services -> OpenClash*. При первом
старте он генерирует случайный пароль дашборда и секцию `authentication`.

---

## 2. Положить конфиг на роутер

С вашего компьютера:

```sh
ssh root@192.168.1.1 'mkdir -p /etc/openclash/config /etc/openclash/ruleset /etc/openclash/backup'
scp -O RU-Mihomo.yaml root@192.168.1.1:/etc/openclash/config/
scp -O RU-Mihomo.conf root@192.168.1.1:/etc/openclash/
scp -O ruleset/*.mrs root@192.168.1.1:/etc/openclash/ruleset/
```

Пути rule-set'ов в конфиге относительные (`./ruleset/...`), поэтому они
отсчитываются от рабочего каталога ядра, на роутере это `/etc/openclash`.

Скопированные здесь `.mrs` — из репозитория. Раздел 5 научит роутер
собирать свежие самому.

---

## 3. Подписка и пароль дашборда

Отредактируйте `/etc/openclash/RU-Mihomo.conf` на роутере:

```ini
[General]
# единственная подписка
SUB_INFO_URL = https://your-provider/subscription-link

# пароль дашборда и API. НЕ пустой: с пустым секретом API отвечает
# "Access-Control-Allow-Origin: *".
DASHBOARD_PASSWORD = your-own-password

# какой конфиг использовать: RU-Mihomo.yaml (с блокировкой рекламы) или
# RU-Mihomo-lite.yaml (примерно на 4 МБ меньше RAM, без блокировки рекламы)
CONFIG_FILE = /etc/openclash/config/RU-Mihomo.yaml
```

Потом импортируйте файл overwrite в LuCI: *OpenClash -> Config Manage -> Config
Subscribe*, указав raw-URL `RU-Mihomo.conf` (или скопировав файл в
`/etc/openclash/backup/` и выбрав его в настройках overwrite).

URL подписки можно подставить прямо в YAML строкой в конце `RU-Mihomo.conf`:

```ini
[Overwrite]
ruby_map_edit "$CONFIG_FILE" "['proxy-providers']" "Main" "['url']" "PASTE_SUBSCRIPTION_URL_HERE"
```

Репозиторий публичный. Не коммитьте URL подписки и пароль: правьте копию на
роутере или держите приватную копию `RU-Mihomo.conf` вне репозитория.

---

## 4. Запуск и проверка

```sh
/etc/init.d/openclash restart
```

Дождитесь в логе готовности ядра, потом посмотрите, что попало в группы:

```sh
scp -O scripts/check-groups.sh root@192.168.1.1:/etc/openclash/
ssh root@192.168.1.1 'sh /etc/openclash/check-groups.sh'
```

Скрипт печатает каждую группу с её нодами и предупреждает, если куда-то
просочилась нода, которой там быть не должно (LTE-сервер, info-нода), или если
российская нода оказалась в одной из автоматических групп.

RAM и флеш:

```sh
ssh root@192.168.1.1 'ps | grep -i mihomo'          # RSS в последней колонке
ssh root@192.168.1.1 'df -h /overlay'               # свободный флеш
ssh root@192.168.1.1 'logread | grep -i mihomo | tail -30'
```

Ориентиры (154 ноды, zram 168 МБ): lite — **52 МБ** RSS, полный — **58 МБ**
RSS, голое ядро ~45 МБ.

---

## 5. Держать rule-set'ы свежими

Rule-set'ы — это **локальные файлы** (`type: file`, `./ruleset/*.mrs`). Это
сделано намеренно: ядро ничего не качает при старте, и именно из-за этого
сходятся цифры по RAM. Следствие: кто-то должен их обновлять — и этот «кто-то»
не обязательно вы.

### 5.1 На роутере (рекомендуется, без секретов)

На роутере уже есть ядро, которое делает конвертацию. Скопируйте скрипты и
пусть роутер освежает списки сам.

**Раскладка важна.** `build-ruleset.sh` берёт корнем репозитория папку над
собой и читает оттуда `lists/custom-domains.list`. Поэтому `scripts/` и
`lists/` должны лежать рядом, как в репозитории:

```text
/etc/openclash/
  scripts/build-ruleset.sh
  scripts/update-rulesets.sh
  scripts/apply-rulesets.sh
  lists/custom-domains.list
  ruleset/                      <- результат, файлы .mrs
```

**Не** копируйте скрипты прямо в `/etc/openclash/`: корнем станет `/etc`, и
сборка остановится с
`ERROR: /etc/lists/custom-domains.list not found`.

Установка из корня репозитория на вашем компьютере:

```sh
ssh root@192.168.1.1 'mkdir -p /etc/openclash/scripts /etc/openclash/lists'
scp -O scripts/build-ruleset.sh scripts/update-rulesets.sh scripts/apply-rulesets.sh root@192.168.1.1:/etc/openclash/scripts/
scp -O lists/custom-domains.list root@192.168.1.1:/etc/openclash/lists/
ssh root@192.168.1.1 'chmod +x /etc/openclash/scripts/*.sh'
```

Запустите один раз руками и посмотрите на результат:

```sh
ssh root@192.168.1.1 '/etc/openclash/scripts/update-rulesets.sh; echo exit=$?'
ssh root@192.168.1.1 'ls /etc/openclash/ruleset/*.mrs | wc -l'     # 28
```

Первый прогон собирает все rule-set'ы, ставит их в `/etc/openclash/ruleset/`
и применяет. Лог прогона — `/tmp/update-rulesets.log`, если запускать из cron.

**Последний шаг — применение.** Ядро читает rule-set'ы, когда грузит конфиг,
поэтому кто-то должен сказать ему, чтобы он прочитал их заново. Способов
два, и `scripts/apply-rulesets.sh` умеет оба:

| `APPLY=` | Что происходит |
|---|---|
| `reload` (по умолчанию) | Ядро просят перечитать конфиг через его собственный API (`PUT /configs?force=true`). Процесс ядра остаётся живым, прокси не прерывается, новые списки работают через секунду. |
| `restart` | OpenClash перезапускается. Проще, но прокси лежит полминуты. |
| `none` | Ничего. Новые списки заработают после следующего перезапуска. |
| `check` | Только смотрит: сколько rule-provider'ов у работающего ядра и сколько в них правил. |

Если перечитывание не получилось, скрипт сам перезапустит OpenClash — новые
списки применяются в любом случае. Посмотреть, что ядро держит прямо сейчас:

```sh
ssh root@192.168.1.1 'APPLY=check sh /etc/openclash/scripts/apply-rulesets.sh'
```

**Файлы из Windows.** `.gitattributes` в репозитории держит скрипты в LF. Если
вы скопировали их из старой выкатки, а роутер отвечает `not found` или `sh\r`,
уберите carriage returns:

```sh
ssh root@192.168.1.1 "sed -i 's/\r$//' /etc/openclash/scripts/*.sh /etc/openclash/lists/custom-domains.list"
```

**Переход со старого конфига.** Rule-set'ы, которые новый конфиг больше не
использует, остаются на флеше. Ничего не удаляйте **до первого успешного
прогона**: пока сборка падает, работают именно старые файлы, а пустой
`ruleset/` вообще не даст OpenClash стартовать. После успешного прогона
`ls -lt /etc/openclash/ruleset/` покажет новые файлы сверху — удалите старые,
которые ниже (или все и запустите скрипт ещё раз).

#### Cron

В OpenWrt нет `/etc/cron.d`; cron роутера — это crontab root'а, и OpenClash
держит в нём же свои задачи. Строку надо **добавить**, а не перезаписать файл:

```sh
ssh root@192.168.1.1 "(crontab -l 2>/dev/null | grep -v update-rulesets; echo '30 5 * * * /etc/openclash/scripts/update-rulesets.sh >/tmp/update-rulesets.log 2>&1') | crontab - && /etc/init.d/cron enable && /etc/init.d/cron restart"
ssh root@192.168.1.1 'crontab -l'                                   # строка на месте
```

Каждое утро роутер пересобирает списки своим ядром, ставит их и применяет. Если
сборка падает — нет сети, список недоступен — **старые списки остаются на
месте**, и в логе так и написано. Ничего не ломается.

Скрипт сначала пробует прямую ссылку, потом зеркала
(`cdn.jsdelivr.net`, `gh-proxy.com`, `ghfast.top`), потому что из России
`raw.githubusercontent.com` не всегда быстрый.

### 5.2 Через GitHub Actions

`.github/workflows/rulesets.yml` пересобирает rule-set'ы каждый день и
коммитит их в репозиторий. Чтобы они ещё и доезжали до роутера, добавьте
секреты репозитория `ROUTER_HOST`, `ROUTER_USER`, `ROUTER_PORT`,
`ROUTER_PATH` и `SSH_PRIVATE_KEY` — тогда workflow вызывает
`scripts/deploy.sh`, который копирует файлы, применяет их и печатает, что
теперь на роутере.

Workflow нужен раннер, который видит роутер: раннер на GitHub где-то в
интернете и вашу локалку не видит. Берите self-hosted раннер на своей машине
или раннер за VPN.

**Оба способа сразу?** Выберите один. Cron на роутере работает без
каких-либо секретов и переживает упавший workflow; путь через Actions
работает, даже если роутер ночью выключен. Если включены оба — выигрывает cron
роутера: он срабатывает в 5:30, а workflow коммитит раз в сутки.

### 5.3 На своём компьютере

```sh
./scripts/build-ruleset.sh
./scripts/selftest.sh
```

---

## 6. Smart-ядро (по желанию)

`RU-Mihomo-smart.yaml` требует форка
[vernesong/mihomo](https://github.com/vernesong/mihomo/releases) — апстрим
ядро не знает типа `smart`.

В OpenClash поставьте тип ядра *Smart* (или `SMART_ENABLE = 1` в файле
overwrite) и положите на роутер `RU-Mihomo-smart.yaml` вместо
`RU-Mihomo.yaml`.

Модель LightGBM — 9,3 МБ. На роутере с малым флешем оставьте
`uselightgbm: false` и `lgbm-auto-update: false` — smart-группа ранжирует ноды
по своим собственным замерам и без модели.

---

## 7. Если что-то пошло не так

**В группах нет нод.** Не загрузилась подписка. Смотрите
`logread | grep -i openclash` и URL в `SUB_INFO_URL`. Прокси-серверы
резолвятся напрямую (`77.88.8.8`), поэтому сломанный DNS делает недоступной
всю подписку.

**Rule-set не совпадает.** `mihomo -t` не проверяет, существуют ли файлы.
Ищите «rule set ... not found» в логе и запустите `./scripts/selftest.sh`.

**`ERROR: .../lists/custom-domains.list not found`.** Скрипты лежат не там.
`scripts/` и `lists/` должны быть рядом (раздел 5.1), например
`/etc/openclash/scripts` и `/etc/openclash/lists`.

**`scp` падает с `sftp-server: not found` или `subsystem request failed`.**
`deploy.sh` сам пробует `-O` и откатывается, если флага нет. Если вызываете
`scp` вручную, добавьте `-O`: в dropbear нет SFTP-сервера.

**`scp: stat local "8022": No such file or directory`.** Нестандартный SSH-порт
передали через `-p`. У `scp` порт задаётся заглавным `-P`; `deploy.sh`
использует оба вида (`-p` для `ssh`, `-P` для `scp`).

**`check-groups.sh` пишет `NOT FOUND` для всех групп, а потом «OK».** API вернул
401 вместо списка прокси: пароль дашборда не задан или неверен. Передайте
`SECRET=<пароль>` или проверьте `/etc/openclash/secret`. Теперь скрипт
отвергает такой ответ вместо ложных «OK».

**Сборка пишет `Bytes: 0`.** Использовался GNU `stat -c%s`, которого нет в
busybox. Скрипт считает байты через `wc -c`.

**`can't create /etc/cron.d/...: nonexistent directory`.** В OpenWrt нет
`/etc/cron.d`. Пользуйтесь crontab, см. раздел 5.1.

**Скрипт пишет `not found` или `sh\r`, хотя файл на месте.** У него
Windows-переводы строк. Уберите их `sed`-командой из раздела 5.1.

**Дашборд просит пароль, которого вы не знаете.** Это `DASHBOARD_PASSWORD` из
`RU-Mihomo.conf` (или случайный, который OpenClash сгенерировал при установке).

**После каждого старта конфиг выглядит иначе.** Это OpenClash: он
переписывает DNS, `fake-ip-filter`, `hosts`, sniffer и `authentication` при
каждом старте. Поэтому `RU-Mihomo.conf` выключает его собственную работу с
DNS (`ENABLE_CUSTOM_DNS = 0`, `CUSTOM_FAKEIP_FILTER = 0`,
`CUSTOM_NAME_POLICY = 0`).

**Хочу свой фильтр нод.** Вешайте его на *группы*, а не на провайдера:
OpenClash переписывает фильтры провайдера из своего интерфейса.

## 8. Проверка

Перед pull request из корня репозитория:

```sh
./scripts/selftest.sh          # mihomo -t всех трёх конфигов + согласованность
bash tests/run-all.sh          # регрессионные тесты (CI запускает их на каждом PR)
```

`tests/run-all.sh` покрывает конфиги, нормализатор доменов (включая дефисы и
punycode), флаги деплоя, сборку под busybox, проверки API, пары доков EN/RU и
копии воркфлоу. Роутер для него не нужен.

Чтобы проверить **полный цикл** — сборка, доставка, применение, проверка — на
реальном роутере или на QEMU-эмуляторе Cudy WR3000S (тема 4pda 1087457, пост
#10376):

```sh
ROUTER_HOST=192.168.1.1 ROUTER_PORT=22 SECRET=<пароль-дашборда> \
  bash tests/04_cycle.sh
```

Скрипт деплоит на нестандартном порту, проверяет раскладку на роутере и все 28
rule-set'ов, запрашивает у живого ядра список провайдеров и убеждается, что
неверный пароль дашборда отвергается. Что именно эмулятор воспроизводить не
может — см. `docs/DESIGN-RU.md`, раздел 9.
