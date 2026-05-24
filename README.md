# node-installer

GitHub-ready установщик RemnaNode для репозитория [MALYSHVIP/node-installer](https://github.com/MALYSHVIP/node-installer).

Главный сценарий запуска:

```bash
curl -fsSL https://raw.githubusercontent.com/MALYSHVIP/node-installer/main/install.sh | sudo bash
```

Что делает `install.sh`:

- скачивает весь репозиторий архивом;
- распаковывает его во временную папку;
- запускает `setup-remnanode.sh` уже локально;
- благодаря этому основной скрипт видит рядом `cake_soft_panel` и все нужные файлы.

## Что изменено относительно исходника

- захардкоженный IP мастер-панели убран;
- если `PANEL_IP` не передан, установщик спрашивает его во время установки;
- `PANEL_IP` по-прежнему нужен, потому что control-порт ноды открывается только для панели через firewall;
- проект подготовлен для установки по GitHub-ссылке.

## Что нужно ввести руками

Во время установки обычно понадобятся:

- `PANEL_IP` — IPv4 мастер-панели;
- `SECRET_KEY` — секрет ноды;
- опционально домен для `xHTTP`, если он нужен.

## Как передать `PANEL_IP` заранее

Если не хотите вводить IP руками:

```bash
curl -fsSL https://raw.githubusercontent.com/MALYSHVIP/node-installer/main/install.sh | sudo PANEL_IP=1.2.3.4 bash
```

Если нужна обычная интерактивная установка, просто запускайте без переменных.

## Структура репозитория

- `install.sh` — bootstrap для GitHub-установки;
- `setup-remnanode.sh` — основной установочный сценарий;
- `cake_soft_panel/` — локальные зависимости, на которые опирается основной сценарий;
- `docs/GITHUB.md` — краткая инструкция по публикации.

## Проверка bootstrap-установщика

```bash
bash install.sh --help
```

## Примечание

`install.sh` специально скачивает весь репозиторий архивом, а не один файл, потому что `setup-remnanode.sh` использует соседнюю папку `cake_soft_panel`.
