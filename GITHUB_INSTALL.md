# GitHub Installer (install.sh)

## 1) Push script to GitHub

```bash
cd /Users/vladimircernakov/Documents/New\ project
git init
git add install.sh GITHUB_INSTALL.md
git commit -m "Add auto installer"
git branch -M main
git remote add origin https://github.com/<USER>/<REPO>.git
git push -u origin main
```

## 2) Run installer on server (recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/<USER>/<REPO>/main/install.sh -o /tmp/install.sh
sudo bash /tmp/install.sh
```

## 3) One-line run (quick)

```bash
curl -fsSL https://raw.githubusercontent.com/<USER>/<REPO>/main/install.sh | sudo bash
```

## 4) Optional overrides

```bash
curl -fsSL https://raw.githubusercontent.com/<USER>/<REPO>/main/install.sh -o /tmp/install.sh
sudo TARGET_MTU=1200 AUTO_SET_MTU=1 bash /tmp/install.sh
```

```bash
curl -fsSL https://raw.githubusercontent.com/<USER>/<REPO>/main/install.sh -o /tmp/install.sh
sudo PANEL_IPS_CSV="144.31.1.170,46.17.45.67" ADMIN_IPS_CSV="144.31.2.170,5.35.115.66" bash /tmp/install.sh
```

## 5) Optional XHTTP preparation + my-remnawave sync

```bash
curl -fsSL https://raw.githubusercontent.com/<USER>/<REPO>/main/install.sh -o /tmp/install.sh
sudo ENABLE_XHTTP_PREP=1 ENABLE_MY_REMNAWAVE_REPO_SYNC=1 bash /tmp/install.sh
```

Generated files:

- `/opt/remnawave-xhttp/inbound-xhttp.json`
- `/opt/remnawave-xhttp/host-extra-xhttp.json`
- `/opt/remnawave-xhttp/remnanode-compose.yml`
- `/etc/nginx/snippets/remnawave-xhttp-location.conf`
- `/opt/my-remnawave` (repo mirror)

Optional auto-create nginx TLS site:

```bash
curl -fsSL https://raw.githubusercontent.com/<USER>/<REPO>/main/install.sh -o /tmp/install.sh
sudo ENABLE_XHTTP_PREP=1 \
  XHTTP_AUTO_CREATE_SITE=1 \
  XHTTP_SERVER_NAME="your.domain.com" \
  XHTTP_TLS_CERT="/etc/letsencrypt/live/your.domain.com/fullchain.pem" \
  XHTTP_TLS_KEY="/etc/letsencrypt/live/your.domain.com/privkey.pem" \
  bash /tmp/install.sh
```
