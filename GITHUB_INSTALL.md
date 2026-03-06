# GitHub Install (install.sh)

## 1) Push to GitHub

```bash
cd /Users/vladimircernakov/Documents/New\ project
git add install.sh GITHUB_INSTALL.md
git commit -m "Use exact user flow"
git branch -M main
git remote add origin https://github.com/MALYSHVIP/node-installer.git
git push -u origin main
```

## 2) Run on server

```bash
curl -fsSL https://raw.githubusercontent.com/MALYSHVIP/node-installer/main/install.sh -o /tmp/install.sh
sudo bash /tmp/install.sh
```

## 3) One line

```bash
curl -fsSL https://raw.githubusercontent.com/MALYSHVIP/node-installer/main/install.sh | sudo bash
```
