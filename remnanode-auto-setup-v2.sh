#!/bin/bash

# =================================================================
# Скрипт автоматической настройки узла Remnawave
# Включает: BBR, FQ-PIE (200+ юзеров), Блокировку SMTP/Torrent/Botnet, Speedtest
# =================================================================

# 1. Обновление системы с максимальной автоматизацией
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
F2B_TRUSTED_IPS="${F2B_TRUSTED_IPS:-}"

# Обновление списков пакетов
apt update

# Глубокое обновление с игнорированием запросов на изменение конфигов и автоматическим подтверждением
apt -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" upgrade
apt -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" full-upgrade

# Очистка системы
apt autoremove --purge -y
apt autoclean

# Установка системных утилит (включая fail2ban/ipset для anti-botnet)
apt install -y curl nano ca-certificates gnupg1 apt-transport-https dirmngr ethtool iptables-persistent irqbalance fail2ban ipset

# 2. Установка SPEEDTEST (Ookla)
curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh | sudo bash
apt install speedtest -y

# 3. Сетевая оптимизация (Тюнинг под нагрузку и 200+ клиентов)
cat <<EOF > /etc/sysctl.d/99-remnanode-optimized.conf
net.core.default_qdisc = fq_pie
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_max_syn_backlog = 8192
net.core.somaxconn = 4096
net.core.netdev_max_backlog = 10000
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
EOF
sysctl --system

# Лимиты файлов
grep -qF "* soft nofile 65535" /etc/security/limits.conf || echo "* soft nofile 65535" >> /etc/security/limits.conf
grep -qF "* hard nofile 65535" /etc/security/limits.conf || echo "* hard nofile 65535" >> /etc/security/limits.conf

# Настройка MTU и многопоточности интерфейса
IFACE="$(ip -o route show default | awk 'NR==1{print $5}')"
MTU=1300
sudo ip link set dev "$IFACE" mtu "$MTU"
ethtool -L "$IFACE" combined $(nproc) 2>/dev/null || true

sudo tee /etc/systemd/system/node-mtu.service >/dev/null <<EOF
[Unit]
Description=Set MTU and Queues for primary interface
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/ip link set dev $IFACE mtu $MTU
ExecStartPost=/usr/sbin/tc qdisc replace dev $IFACE root fq_pie
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now node-mtu.service
sudo systemctl enable --now irqbalance

# 4. Защита SSH от перебора (fail2ban)
# Чтобы не банить панель/jump:
# F2B_TRUSTED_IPS="x.x.x.x y.y.y.y" curl ... | sudo bash
F2B_IGNOREIP="127.0.0.1/8 ::1"
if [ -n "${SSH_CLIENT:-}" ]; then
    F2B_IGNOREIP="$F2B_IGNOREIP $(echo "$SSH_CLIENT" | awk '{print $1}')"
fi
if [ -n "$F2B_TRUSTED_IPS" ]; then
    F2B_IGNOREIP="$F2B_IGNOREIP $F2B_TRUSTED_IPS"
fi

cat <<EOF > /etc/fail2ban/jail.d/sshd-remnanode.local
[DEFAULT]
banaction = iptables-multiport
findtime = 10m
bantime = 24h
maxretry = 5
ignoreip = $F2B_IGNOREIP

[sshd]
enabled = true
port = 22,2222
mode = aggressive
EOF
systemctl enable --now fail2ban
systemctl restart fail2ban
for ip in $F2B_TRUSTED_IPS; do
    fail2ban-client set sshd unbanip "$ip" >/dev/null 2>&1 || true
done

# Если UFW уже включен, явно оставляем доступ к SSH/API
if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
    ufw allow 22/tcp || true
    ufw allow 2222/tcp || true
fi

# 5. БЛОКИРОВКА ABUSE/BOTNET (SMTP, BitTorrent, C2)
CHAIN="REMNAWAVE_EGRESS_GUARD"
iptables -N "$CHAIN" 2>/dev/null || true
iptables -F "$CHAIN"

# Уже установленные соединения и локальные сети не трогаем
iptables -A "$CHAIN" -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN
iptables -A "$CHAIN" -d 127.0.0.0/8 -j RETURN
iptables -A "$CHAIN" -d 10.0.0.0/8 -j RETURN
iptables -A "$CHAIN" -d 172.16.0.0/12 -j RETURN
iptables -A "$CHAIN" -d 192.168.0.0/16 -j RETURN

# Блокировка почты (SMTP)
for p in 25 465 587 2525; do
    iptables -A "$CHAIN" -p tcp --dport "$p" -j REJECT --reject-with tcp-reset
    iptables -A "$CHAIN" -p udp --dport "$p" -j DROP
done

# Блокировка C2-порта из абуза (lingyunnet)
iptables -A "$CHAIN" -p tcp --dport 9166 -j REJECT --reject-with tcp-reset
iptables -A "$CHAIN" -p udp --dport 9166 -j DROP

# IOC из abuse-логов (C2/зловредные IP)
ipset create remna_ioc hash:ip -exist
for ioc in \
    85.17.155.52 85.17.155.53 \
    85.17.70.16 85.17.70.38 \
    46.165.199.9 46.165.199.7 \
    178.162.202.96 178.162.202.97
do
    ipset add remna_ioc "$ioc" -exist
done

iptables -A "$CHAIN" -m set --match-set remna_ioc dst -j REJECT --reject-with icmp-host-prohibited

# Блокировка торрентов по сигнатурам
SIGNATURES=("BitTorrent" "BitTorrent protocol" "peer_id=" ".torrent" "announce.php?passkey=" "info_hash" "get_peers" "find_node")
for sig in "${SIGNATURES[@]}"; do
    iptables -A "$CHAIN" -m conntrack --ctstate NEW -m string --algo bm --string "$sig" -j DROP
done

# Блокировка портов торрента
iptables -A "$CHAIN" -p tcp --dport 6881:6999 -j DROP
iptables -A "$CHAIN" -p udp --dport 6881:6999 -j DROP
iptables -A "$CHAIN" -p tcp --dport 51413 -j DROP
iptables -A "$CHAIN" -p udp --dport 51413 -j DROP

# Подключаем цепочку к OUTPUT/FORWARD один раз
iptables -C OUTPUT -j "$CHAIN" 2>/dev/null || iptables -I OUTPUT 1 -j "$CHAIN"
iptables -C FORWARD -j "$CHAIN" 2>/dev/null || iptables -I FORWARD 1 -j "$CHAIN"

# Сохранение ipset и автоподнятие после перезагрузки
mkdir -p /etc/iptables
ipset save remna_ioc > /etc/iptables/remna_ioc.set
cat <<'EOF' > /etc/systemd/system/remna-ioc-restore.service
[Unit]
Description=Restore IOC ipset list for Remnanode
Before=netfilter-persistent.service

[Service]
Type=oneshot
ExecStart=/sbin/ipset restore -exist -f /etc/iptables/remna_ioc.set

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now remna-ioc-restore.service

# Сохранение правил (выбираем 'yes' автоматически)
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | sudo debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | sudo debconf-set-selections
netfilter-persistent save
systemctl enable netfilter-persistent >/dev/null 2>&1 || true

# 6. Установка Docker
curl -fsSL https://get.docker.com | sh
systemctl enable --now docker

# 7. Развертывание Remnanode
mkdir -p /opt/remnanode
cd /opt/remnanode

# Остановка на ввод данных
echo "Сейчас откроется редактор. Вставь свой docker-compose.yml, сохрани (Ctrl+O, Enter) и выйди (Ctrl+X)"
sleep 3
nano docker-compose.yml </dev/tty

if [ ! -f docker-compose.yml ]; then
    echo "ОШИБКА: Файл docker-compose.yml не найден!"
    exit 1
else
    # Применяем правки образа
    sed -i -E 's#^([[:space:]]*)image:.*#\1image: ghcr.io/remnawave/node:latest#' docker-compose.yml
    
    echo "Проверка настроек:"
    grep -n 'image:' docker-compose.yml
    grep -E 'NODE_PORT|SECRET_KEY' docker-compose.yml
    
    # Попытка скачать образ
    for i in {1..5}; do
        docker compose pull remnanode && break
        echo "Попытка $i не удалась, ждем..."
        sleep 5
    done

    docker compose up -d remnanode
    docker compose ps
fi

echo "===================================================="
echo "Установка завершена!"
echo "Проверьте скорость: speedtest"
echo "Справедливые очереди FQ-PIE активны."
echo "===================================================="