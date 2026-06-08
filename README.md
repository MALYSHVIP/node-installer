# RemnaNode Installer

Установщик ноды Remnawave с запуском одной командой через GitHub.

Основная команда:

```bash
curl -fsSL https://raw.githubusercontent.com/MALYSHVIP/node-installer/main/install.sh | sudo bash
```

Что спросит установщик:

1. `PANEL_IP` мастер-панели
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

Рекомендуется ставить на чистый Ubuntu VPS под `root`.
