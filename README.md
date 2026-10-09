# RemnaNode Installer

Установщик ноды Remnawave с запуском одной командой через GitHub.

Основная команда:

```bash
curl -fsSL https://raw.githubusercontent.com/MALYSHVIP/node-installer/main/install.sh | sudo bash
```

Если IP мастер-панели уже известен, поддерживается ровно такой однострочный запуск; остальные значения установщик запросит в терминале:

```bash
curl -fsSL https://raw.githubusercontent.com/MALYSHVIP/node-installer/main/install.sh | sudo env PANEL_IP=144.31.1.170 bash
```

Что спросит установщик:

1. `PANEL_IP` мастер-панели, если он не передан в команде
2. `Enable xHTTP? (y/n)`
3. домен для `xHTTP`, если выбрано `y`
4. `SECRET_KEY`

Что делает скрипт:

- сам определяет IPv4 ноды;
- сам определяет MTU;
- ставит Docker и системные зависимости;
- поднимает `remnanode`;
- настраивает firewall так, чтобы control-порт `2222/tcp` был открыт только для `PANEL_IP`;
- настраивает `xHTTP` и TLS, если включён домен;
- ставит watchdog, cleanup и сервисы автоподдержки.

Если хочешь сразу передать значения без ручного ввода:

```bash
curl -fsSL https://raw.githubusercontent.com/MALYSHVIP/node-installer/main/install.sh | \
sudo env PANEL_IP='<MASTER_PANEL_IP>' SECRET_KEY='<NODE_SECRET_KEY>' bash
```

Если нужен `xHTTP`:

```bash
curl -fsSL https://raw.githubusercontent.com/MALYSHVIP/node-installer/main/install.sh | \
sudo env PANEL_IP='<MASTER_PANEL_IP>' XHTTP_DOMAIN='node.example.com' SECRET_KEY='<NODE_SECRET_KEY>' bash
```

Файлы репозитория:

- `install.sh` — bootstrap для `curl | bash`
- `setup-remnanode.sh` — основной установщик ноды

Установщик **не содержит списка IP и не включает SSH-ограничение
автоматически**. Он устанавливает модуль получения подписанного списка по
HTTPS. После безопасной выдачи индивидуального токена ноде модуль начинает
сам получать список, проверять подпись и применять только IP-адреса. Ни
пароли SSH, ни другие данные мониторинг нодам не передаёт. Кнопка
«Передать разрешённые IP» публикует новый список и показывает
подтверждение каждой ноды; исключённые боты и панели не меняются.

- `bin/remnanode-ssh-peers` — управляемый список исходящих SSH-адресов.
- `bin/remnanode-ssh-peers-pull` — HTTPS-получатель с проверкой подписи.

Рекомендуется ставить на чистый Ubuntu VPS под `root`.
