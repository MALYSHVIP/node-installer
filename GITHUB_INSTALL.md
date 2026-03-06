# GitHub Install (remnanode-auto-setup-v2.sh)

## 1) Push to GitHub

```bash
cd /Users/vladimircernakov/Documents/New\ project
git add remnanode-auto-setup-v2.sh GITHUB_INSTALL.md
git commit -m "Update install docs for remnanode-auto-setup-v2.sh"
git branch -M main
git remote add origin https://github.com/MALYSHVIP/node-installer.git
git push -u origin main
```

## 2) Run on server

```bash
curl -fsSL https://raw.githubusercontent.com/MALYSHVIP/node-installer/main/remnanode-auto-setup-v2.sh -o /tmp/remnanode-auto-setup-v2.sh
sudo bash /tmp/remnanode-auto-setup-v2.sh
```

## 3) One line

```bash
curl -fsSL https://raw.githubusercontent.com/MALYSHVIP/node-installer/main/remnanode-auto-setup-v2.sh | sudo bash
```

## 4) Links

- Repo: https://github.com/MALYSHVIP/node-installer
- Script page: https://github.com/MALYSHVIP/node-installer/blob/main/remnanode-auto-setup-v2.sh
- Raw script: https://raw.githubusercontent.com/MALYSHVIP/node-installer/main/remnanode-auto-setup-v2.sh
