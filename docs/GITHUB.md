# Публикация в GitHub

## 1. Репозиторий

Создайте или используйте репозиторий:

- `MALYSHVIP/node-installer`

## 2. Что загрузить

В репозитории должны быть:

- `install.sh`
- `setup-remnanode.sh`
- вся папка `cake_soft_panel/`
- `README.md`
- `docs/GITHUB.md`

## 3. Команда установки

После публикации установка будет такой:

```bash
curl -fsSL https://raw.githubusercontent.com/MALYSHVIP/node-installer/main/install.sh | sudo bash
```

## 4. Что изменилось

- IP мастер-панели больше не зашит в код;
- если `PANEL_IP` не передан, скрипт спросит его при установке;
- bootstrap скачивает весь репозиторий архивом и только потом запускает установку.

## 5. Если хотите передать IP панели сразу

```bash
curl -fsSL https://raw.githubusercontent.com/MALYSHVIP/node-installer/main/install.sh | sudo PANEL_IP=1.2.3.4 bash
```
