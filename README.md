# RemnaNode Installer 4.1.8

Установщик Remnawave Node 3.4.2 с проверенной схемой masked BBR:

- Hysteria 2 на `UDP/443`;
- TLS с ALPN `h3`;
- QUIC congestion `bbr`;
- `disablePathMTUDiscovery=true` для мобильных сетей;
- Salamander с индивидуальным случайным паролем;
- без `packetSize`/GECKO, потому что этот вариант не прошёл LTE-проверку;
- одновременный xHTTP через Nginx на `TCP/443` либо обычное HTTPS-прикрытие;
- автоматическое продление TLS;
- штатные offload/qdisc не отключаются.

## Установка ноды

DNS A-запись домена должна заранее указывать на IP ноды. Bootstrap 1.2.7 поддерживает однострочный запуск через `curl | sudo bash`, включая системы, где `sudo` использует собственный PTY: установщик сам находит исходный SSH-терминал для ответов. При запуске из потока он скачивает новую версию, а не подхватывает старый файл из текущей папки. Пустая секретка и ошибочный домен запрашиваются повторно.

```bash
curl -fsSL https://raw.githubusercontent.com/MALYSHVIP/node-installer/main/install.sh | \
sudo env PANEL_IP='<MASTER_PANEL_IP>' bash
```

Установщик по очереди спросит, включать ли masked BBR, домен, включать ли одновременно xHTTP, а затем `SECRET_KEY`. Для совместного режима используется один домен: Hysteria занимает `UDP/443`, Nginx/xHTTP - `TCP/443`.

Для полностью неинтерактивного запуска сохраните ключ в root-only файле и передайте `SECRET_FILE`. Здесь оба транспорта включаются на одном домене:

```bash
install -m 600 /dev/null /root/remnanode-secret.txt
nano /root/remnanode-secret.txt
curl -fsSL "https://raw.githubusercontent.com/MALYSHVIP/node-installer/main/install.sh?ts=$(date +%s)" | \
sudo env PANEL_IP='<MASTER_PANEL_IP>' MASKED_BBR_DOMAIN='node.example.com' \
XHTTP_DOMAIN='node.example.com' SECRET_FILE='/root/remnanode-secret.txt' \
bash -s -- install --yes
```

Во время установки создаются:

- `/var/lib/remnanode-installer/masked-bbr-contract.json` - точный root-only contract для профиля мастер-панели;
- `/var/lib/remnanode-installer/masked-bbr-password` - индивидуальный пароль Salamander;
- `/etc/remnanode/tls/fullchain.pem` и `privkey.pem` - сертификат ноды;
- HTTPS-прикрытие с HTTP→HTTPS, TLS 1.2/1.3, HSTS и собственной страницей 404.

Пароль Salamander сохраняется при повторном запуске. Установщик не меняет его сам, поэтому уже выданные профили не ломаются.

## Защита и подключение мониторинга

На новой установке автоматически включаются:

- порт управления нодой, доступный только с `PANEL_IP/PANEL_IPS`;
- блокировка SMTP TCP/25,465,587,2525 в OUTPUT/FORWARD;
- блокировка BitTorrent TCP/UDP 6881-6999,2710,6969,16881,51413,53442 и доступных ядру сигнатур;
- Spamhaus DROP IPv4/IPv6 с проверенным локальным кешем;
- защита исходящего SSH/22 и DNS/53 от злоупотреблений;
- подписанный список разрешённых SSH-IP из мониторинга через HTTPS;
- адаптивные UDP-буферы без уменьшения уже увеличенных значений.

При обновлении сохраняются ранее выбранные политики SSH/DNS/Spamhaus и явные отключения. Чтобы включить все модули на ранее установленной ноде, добавьте `--antiabuse-guards` после `bash -s -- update`. Для BitTorrent предусмотрены отдельные `--bittorrent-guard` и `--no-bittorrent-guard`.

Для автоматического подключения мониторинга IP ноды должен быть внесён в его список, а актуальный список опубликован кнопкой «передать разрешенные IP». Установщик подтверждает владение сертификатом этой мастер-панели и автоматически получает индивидуальный токен. SECRET_KEY и приватный ключ остаются на ноде. Новые ноды не добавляются в инвентарь сами; серверы-исключения не получают ограничений.

Мониторинг не входит на ноды по SSH: ноды сами скачивают подписанный список и подтверждают применение. Проверяются подпись Ed25519, срок действия и номер поколения. Возврат к старому списку запрещён. После перезагрузки или обновления утраченные правила восстанавливаются. Недоступность мониторинга сохраняет действующие разрешения и запускает повторные попытки, не открывая SSH всем адресам. Входящий SSH этим модулем не ограничивается.

Модули, скачанные установщиком из GitHub, проверяются по SHA256, закреплённому в его версии. Старый torrent-модуль удаляется только после проверки новой защиты. Изменения offload, MTU, IRQ и замена сетевых очередей по умолчанию не выполняются; существующие исправления очередей сохраняются. Увеличение буферов не гарантирует отсутствие потерь у провайдера.

Серверная часть регистрации расположена в `monitor/enroll.php`. Для этой мастер-панели она уже установлена. При переносе мониторинга файл размещается рядом с `manifest.php`; доверенный публичный CA-сертификат панели хранится вне web-root в `/etc/monitor-ssh-peers/panel-ca.pem`. Приватный CA-ключ там не нужен.

## Применение contract в мастер-панели

Нода не имеет административного токена мастер-панели. Поэтому безопасно менять профиль панели из node-installer невозможно: `SECRET_KEY` ноды для этого не предназначен. Contract нужно применить к одному выбранному Hysteria-inbound, сохранив его `id`, `tag`, `listen`, `port`, `settings/clients`, маршруты, пользователей и привязки сквадов.

Для подготовки полного кандидата без изменения исходного JSON:

```bash
./bin/remnanode-masked-bbr-merge \
  --profile ./exported-profile.json \
  --contract ./masked-bbr-contract.json \
  --inbound-tag 'BBR-IN-443' \
  --output ./profile.masked-bbr.candidate.json
```

Инструмент меняет только `streamSettings` одного точно указанного Hysteria-inbound и отказывается работать, если:

- найдено ноль или больше одного совпадения;
- inbound не Hysteria или не на порту 443;
- отсутствуют TLS/h3, BBR, PMTUD-off или Salamander;
- присутствует `packetSize`, то есть включён GECKO;
- выходной файл совпадает с исходником.

В Host мастер-панели должны совпадать:

- Address: домен ноды;
- Port: `443`;
- Security layer: `TLS`;
- ALPN: `h3`;
- Fingerprint: `firefox`;
- Inbound: именно тот, в который применён contract.

## Финальная строгая проверка

После применения профиля в панели повторите установщик со строгой проверкой живого runtime:

```bash
curl -fsSL "https://raw.githubusercontent.com/MALYSHVIP/node-installer/main/install.sh?ts=$(date +%s)" | \
sudo env PANEL_IP='<MASTER_PANEL_IP>' MASKED_BBR_DOMAIN='node.example.com' \
XHTTP_DOMAIN='node.example.com' SECRET_FILE='/root/remnanode-secret.txt' \
bash -s -- update --require-profile-ready --yes
```

Проверка читает только обезличенные признаки активного runtime-профиля и подтверждает:

- Hysteria действительно слушает UDP/443;
- TLS использует ALPN h3;
- congestion равен bbr;
- `disablePathMTUDiscovery=true`;
- задан один plain Salamander с непустым паролем;
- `packetSize` отсутствует;
- masquerade настроен;
- контейнер стабилен и не перезапускается.

После этого всё равно нужен внешний тест из HAPP по Wi‑Fi и LTE: сайты, видео, скачивание и отправка файла. Локальная проверка сервера не может доказать работу конкретной мобильной сети.

## Совместный xHTTP и masked BBR

Рабочий совместный режим использует разные сетевые протоколы на одном номере порта:

- masked BBR/Hysteria 2 - `UDP/443`;
- xHTTP/Nginx - `TCP/443`;
- сертификат, SNI и домен у них общие;
- Nginx не включает QUIC/HTTP/3 и не перехватывает Hysteria UDP.

В мастер-панели профиль ноды должен содержать оба соответствующих inbound. Установщик готовит ноду и проверяет runtime, но не добавляет inbound в мастер-панель самостоятельно.

Для установки только xHTTP без masked BBR используйте интерактивный запуск из скачанного файла либо полностью передайте параметры:

```bash
curl -fsSL "https://raw.githubusercontent.com/MALYSHVIP/node-installer/main/install.sh?ts=$(date +%s)" | \
sudo env PANEL_IP='<MASTER_PANEL_IP>' ENABLE_MASKED_BBR=0 \
XHTTP_DOMAIN='node.example.com' SECRET_FILE='/root/remnanode-secret.txt' \
bash -s -- install --yes
```

Для установки без masked BBR и xHTTP:

```bash
curl -fsSL "https://raw.githubusercontent.com/MALYSHVIP/node-installer/main/install.sh?ts=$(date +%s)" | \
sudo env PANEL_IP='<MASTER_PANEL_IP>' ENABLE_MASKED_BBR=0 ENABLE_XHTTP=0 \
SECRET_FILE='/root/remnanode-secret.txt' bash -s -- install --yes
```

## Файлы репозитория

- `install.sh` - bootstrap для `curl | bash`;
- `setup-remnanode.sh` - полный установщик и проверяющий модуль;
- `bin/remnanode-masked-bbr-merge` - безопасная подготовка профиля панели;
- `bin/remnanode-ssh-peers` и `bin/remnanode-ssh-peers-pull` - подписанный список разрешённых SSH peers;
- `tests/test_masked_bbr_merge.py` - проверки merge, сохранения данных и запрета GECKO.

Все изменения ноды предваряются полным backup в `/var/backups/remnanode`. Установщик не обновляет мастер-панель, бота и клиентское приложение HAPP.

## Проверки перед публикацией

```bash
sudo bash tests/run_checks.sh
```

Нужны Bash 4.4+, Python 3, PHP CLI/OpenSSL и Linux с nftables, iptables, iproute2, util-linux. Сетевые проверки запускаются в отдельном network namespace и не меняют firewall рабочей ноды. Проверяются обычный терминал и sudo PTY, остановленный предыдущий установщик, PKI, повторные запуски, rollback, подписанный список IP, защита SMTP/BitTorrent и обычный трафик. GitHub Actions повторяет эти проверки при изменениях.

DNS-запись должна указывать на сервер, а SECRET_KEY должен быть действующим ключом именно этой ноды. Установщик не может исправить блокировку IP провайдером или заменить отсутствующий профиль в мастер-панели. Если назначенный профиль не совпадает с выбранными транспортами, итоговая проверка сообщает об этом отдельно; готовность VPN не подменяется состоянием контейнера.
