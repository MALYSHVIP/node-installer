# RemnaNode Installer

Установщик Remnawave Node 3.4.2 с проверенной схемой masked BBR:

- Hysteria 2 на `UDP/443`;
- TLS с ALPN `h3`;
- QUIC congestion `bbr`;
- `disablePathMTUDiscovery=true` для мобильных сетей;
- Salamander с индивидуальным случайным паролем;
- без `packetSize`/GECKO, потому что этот вариант не прошёл LTE-проверку;
- обычное HTTPS-прикрытие на `TCP/443` и автоматическое продление TLS;
- штатные offload/qdisc не отключаются.

## Установка ноды

DNS A-запись домена должна заранее указывать на IP ноды. Запускать на самой ноде под `root`:

```bash
curl -fsSL https://raw.githubusercontent.com/MALYSHVIP/node-installer/main/install.sh | \
sudo env PANEL_IP='<MASTER_PANEL_IP>' MASKED_BBR_DOMAIN='node.example.com' bash
```

Установщик запросит `SECRET_KEY`. Для полностью неинтерактивного запуска сохраните ключ в root-only файле и передайте `SECRET_FILE`:

```bash
install -m 600 /dev/null /root/remnanode-secret.txt
nano /root/remnanode-secret.txt
curl -fsSL https://raw.githubusercontent.com/MALYSHVIP/node-installer/main/install.sh | \
sudo env PANEL_IP='<MASTER_PANEL_IP>' MASKED_BBR_DOMAIN='node.example.com' \
SECRET_FILE='/root/remnanode-secret.txt' bash
```

Во время установки создаются:

- `/var/lib/remnanode-installer/masked-bbr-contract.json` — точный root-only contract для профиля мастер-панели;
- `/var/lib/remnanode-installer/masked-bbr-password` — индивидуальный пароль Salamander;
- `/etc/remnanode/tls/fullchain.pem` и `privkey.pem` — сертификат ноды;
- HTTPS-прикрытие с HTTP→HTTPS, TLS 1.2/1.3, HSTS и собственной страницей 404.

Пароль Salamander сохраняется при повторном запуске. Установщик не меняет его сам, поэтому уже выданные профили не ломаются.

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
curl -fsSL https://raw.githubusercontent.com/MALYSHVIP/node-installer/main/install.sh | \
sudo env PANEL_IP='<MASTER_PANEL_IP>' MASKED_BBR_DOMAIN='node.example.com' \
SECRET_FILE='/root/remnanode-secret.txt' bash -s -- update --require-profile-ready --yes
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

## Обычный xHTTP или legacy-режим

Masked BBR и managed xHTTP нельзя включать одновременно на одной ноде. Для xHTTP используйте прежний режим:

```bash
curl -fsSL https://raw.githubusercontent.com/MALYSHVIP/node-installer/main/install.sh | \
sudo env PANEL_IP='<MASTER_PANEL_IP>' XHTTP_DOMAIN='node.example.com' bash
```

Для установки без masked BBR:

```bash
curl -fsSL https://raw.githubusercontent.com/MALYSHVIP/node-installer/main/install.sh | \
sudo env PANEL_IP='<MASTER_PANEL_IP>' ENABLE_MASKED_BBR=0 bash
```

## Файлы репозитория

- `install.sh` — bootstrap для `curl | bash`;
- `setup-remnanode.sh` — полный установщик и проверяющий модуль;
- `bin/remnanode-masked-bbr-merge` — безопасная подготовка профиля панели;
- `bin/remnanode-ssh-peers` и `bin/remnanode-ssh-peers-pull` — подписанный список разрешённых SSH peers;
- `tests/test_masked_bbr_merge.py` — проверки merge, сохранения данных и запрета GECKO.

Все изменения ноды предваряются полным backup в `/var/backups/remnanode`. Установщик не обновляет мастер-панель, бота и клиентское приложение HAPP.
