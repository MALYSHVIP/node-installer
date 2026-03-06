#!/bin/bash

# =================================================================
# Скрипт автоматической настройки узла Remnawave
# Включает: BBR, FQ-PIE (200+ юзеров), Блокировку SMTP/Torrent, Speedtest
# =================================================================

# 1. Обновление системы с максимальной автоматизацией
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

# Обновление списков пакетов
apt update

# Глубокое обновление с игнорированием запросов на изменение конфигов и автоматическим подтверждением
apt -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" upgrade
apt -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" full-upgrade

# Очистка системы
apt autoremove --purge -y
apt autoclean

# Установка системных утилит (включая irqbalance для распределения нагрузки на CPU)
apt install -y curl nano ca-certificates gnupg1 apt-transport-https dirmngr ethtool iptables-persistent irqbalance

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
EOF
sysctl --system

# Лимиты файлов
echo "* soft nofile 65535" >> /etc/security/limits.conf
echo "* hard nofile 65535" >> /etc/security/limits.conf

# Настройка MTU и многопоточности интерфейса
IFACE="$(ip -o route show default | awk 'NR==1{print $5}')"
MTU=1200
sudo ip link set dev "$IFACE" mtu 1300
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

# 4. БЛОКИРОВКА ABUSE (SMTP и BitTorrent)
iptables -F FORWARD
iptables -F OUTPUT

# Блокировка почты (SMTP)
iptables -A OUTPUT -p tcp --dport 25 -j REJECT
iptables -A OUTPUT -p tcp --dport 465 -j REJECT
iptables -A OUTPUT -p tcp --dport 587 -j REJECT

# Блокировка торрентов по сигнатурам
SIGNATURES=("BitTorrent" "BitTorrent protocol" "peer_id=" ".torrent" "announce.php?passkey=" "info_hash" "get_peers" "find_node")
for sig in "${SIGNATURES[@]}"; do
    iptables -I FORWARD -m string --algo bm --string "$sig" -j DROP
    iptables -I OUTPUT -m string --algo bm --string "$sig" -j DROP
done

# Блокировка портов торрента
iptables -A FORWARD -p tcp --dport 6881:6889 -j DROP
iptables -A FORWARD -p udp --dport 6881:6889 -j DROP

# Сохранение правил (выбираем 'yes' автоматически)
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | sudo debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | sudo debconf-set-selections
netfilter-persistent save

# 5. Установка Docker
curl -fsSL https://get.docker.com | sh
systemctl enable --now docker

# 6. Развертывание Remnanode
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