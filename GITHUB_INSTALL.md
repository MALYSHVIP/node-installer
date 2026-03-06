# GitHub Install (remnanode-auto-setup-v2.sh)

## 1) Push script to GitHub

```bash
cd /Users/vladimircernakov/Documents/New\ project
git add remnanode-auto-setup-v2.sh GITHUB_INSTALL.md
git commit -m "Add remnanode auto setup v2"
git branch -M main
git remote add origin https://github.com/<USER>/<REPO>.git
git push -u origin main
```

## 2) Run on server (recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/<USER>/<REPO>/main/remnanode-auto-setup-v2.sh -o /tmp/remnanode-auto-setup-v2.sh
sudo bash /tmp/remnanode-auto-setup-v2.sh
```

## 3) One-line run (quick)

```bash
curl -fsSL https://raw.githubusercontent.com/<USER>/<REPO>/main/remnanode-auto-setup-v2.sh | sudo bash
```

## 4) Optional overrides

Custom node port + MTU:

```bash
curl -fsSL https://raw.githubusercontent.com/<USER>/<REPO>/main/remnanode-auto-setup-v2.sh -o /tmp/remnanode-auto-setup-v2.sh
sudo NODE_PORT=2222 MTU=1300 bash /tmp/remnanode-auto-setup-v2.sh
```

Set custom SECRET_KEY manually:

```bash
curl -fsSL https://raw.githubusercontent.com/<USER>/<REPO>/main/remnanode-auto-setup-v2.sh -o /tmp/remnanode-auto-setup-v2.sh
sudo SECRET_KEY="put_your_secret_here" bash /tmp/remnanode-auto-setup-v2.sh
```

Disable speedtest install:

```bash
curl -fsSL https://raw.githubusercontent.com/<USER>/<REPO>/main/remnanode-auto-setup-v2.sh -o /tmp/remnanode-auto-setup-v2.sh
sudo ENABLE_SPEEDTEST=0 bash /tmp/remnanode-auto-setup-v2.sh
```

Disable SMTP/torrent firewall blocking:

```bash
curl -fsSL https://raw.githubusercontent.com/<USER>/<REPO>/main/remnanode-auto-setup-v2.sh -o /tmp/remnanode-auto-setup-v2.sh
sudo BLOCK_SMTP=0 BLOCK_TORRENT=0 bash /tmp/remnanode-auto-setup-v2.sh
```

## 5) Checks after install

```bash
cd /opt/remnanode && docker compose ps
docker logs --tail 80 remnanode
systemctl status remnanode-net-tune.service --no-pager
iptables -S REMNANODE_OUT
iptables -S REMNANODE_FWD
speedtest
```
