# node-installer

GitHub-ready установщик RemnaNode для репозитория [MALYSHVIP/node-installer](https://github.com/MALYSHVIP/node-installer).

Главная команда:

```bash
curl -fsSL https://raw.githubusercontent.com/MALYSHVIP/node-installer/main/install.sh | sudo bash
```

`install.sh` скачивает `setup-remnanode.sh` и запускает основной установщик.

## Как работает интерактивная установка

Обычный сценарий такой:

1. Скрипт спрашивает `PANEL_IP`.
2. Скрипт спрашивает, нужен ли `xHTTP`.
3. Если ответил `y`, скрипт спрашивает домен для ноды.
4. Скрипт спрашивает `SECRET_KEY`.

`PANEL_IP` всегда можно вводить руками. Никакого авто-поиска IP мастер-панели тут нет.

## Что вводить руками

Минимум для твоего сценария:

- `PANEL_IP` — IP мастер-панели;
- `y` или `n` для `xHTTP`;
- домен ноды, если включаешь `xHTTP`;
- `SECRET_KEY`.

## Команды запуска

Полностью интерактивно:

```bash
curl -fsSL https://raw.githubusercontent.com/MALYSHVIP/node-installer/main/install.sh | sudo bash
```

С заранее переданным IP панели:

```bash
curl -fsSL https://raw.githubusercontent.com/MALYSHVIP/node-installer/main/install.sh | sudo env PANEL_IP=1.2.3.4 bash
```

Если хочешь сразу передать секрет ноды:

```bash
curl -fsSL https://raw.githubusercontent.com/MALYSHVIP/node-installer/main/install.sh | sudo env PANEL_IP=1.2.3.4 SECRET_KEY='eyJ...' bash
```

## Что нужно сделать после установки

После завершения установки нужно зайти в Remnawave Panel и создать или настроить Node:

1. Открой `Nodes` -> `Management`.
2. Добавь ноду с адресом этого сервера или доменом ноды.
3. Укажи порт `2222`, если ты его не менял.
4. Выбери `Config Profile`.
5. Сохрани ноду.

После этого панель должна подключиться к ноде и запустить рабочую конфигурацию.

## Файлы репозитория

- `install.sh` — bootstrap для установки по GitHub-ссылке.
- `setup-remnanode.sh` — основной установщик.
- `docs/GITHUB.md` — краткая инструкция по публикации.
- `docs/INSTALL-RU.md` — полная инструкция по публикации и установке.

## Проверка локально

```bash
bash install.sh --help
bash -n setup-remnanode.sh
```

## Примечание

Если рядом с локальной копией есть `cake_soft_panel`, скрипт сможет использовать его для baseline CAKE stack. Если папки нет, установка ноды всё равно продолжается.
