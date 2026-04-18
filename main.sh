#!/bin/bash

set -e

echo "=== Automatic SETUP ==="

# --- Проверка root ---
if [ "$EUID" -ne 0 ]; then
  echo "Запусти от root"
  exit 1
fi

# --- SSH ключ ---
if [ ! -f ~/.ssh/authorized_keys ]; then
  echo "[!] Нет SSH ключа"
  exit 1
fi

# --- Пользователь ---
read -p "Имя нового пользователя: " USERNAME
USER_PASSWORD="$(head -c 24 /dev/urandom | base64 | tr -d '\n')"
adduser --disabled-password --gecos "" "$USERNAME"
echo "$USERNAME:$USER_PASSWORD" | chpasswd
mkdir -p /home/$USERNAME/.ssh
cp ~/.ssh/authorized_keys /home/$USERNAME/.ssh/
chown -R $USERNAME:$USERNAME /home/$USERNAME/.ssh
usermod -aG sudo $USERNAME

# --- SSH порт ---
SSH_PORT=$(shuf -i 2000-65000 -n 1)
echo "[*] SSH порт: $SSH_PORT"

# --- Режим ---
echo "1) Panel"
echo "2) Node"
echo "3) Только настройка сервера"
read -p "Выбор: " MODE

INSTALL_DOCKER=false
if [ "$MODE" == "1" ] || [ "$MODE" == "2" ]; then
  INSTALL_DOCKER=true
elif [ "$MODE" != "3" ]; then
  echo "Ошибка"
  exit 1
fi

# --- Обновление ---
apt update && apt upgrade -y
apt install -y curl wget git ufw fail2ban

# --- Docker ---
if [ "$INSTALL_DOCKER" = true ]; then
  curl -fsSL https://get.docker.com | sh
  apt install -y docker-compose
  usermod -aG docker $USERNAME
fi

# --- SSH hardening ---
sed -i "s/#Port 22/Port $SSH_PORT/" /etc/ssh/sshd_config
sed -i "s/^#\?PermitRootLogin.*/PermitRootLogin no/" /etc/ssh/sshd_config
sed -i "s/^#\?PasswordAuthentication.*/PasswordAuthentication no/" /etc/ssh/sshd_config
sed -i "s/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/" /etc/ssh/sshd_config
sed -i "s/^#\?MaxAuthTries.*/MaxAuthTries 3/" /etc/ssh/sshd_config

systemctl restart ssh

# --- Firewall (всё закрыто кроме нужного) ---
ufw default deny incoming
ufw default allow outgoing
ufw allow $SSH_PORT

# --- PANEL ---
if [ "$MODE" == "1" ]; then
    echo "[*] Установка PANEL"

    # VPN порт (пример)
    VPN_PORT=443
    ufw allow $VPN_PORT

    mkdir -p /opt/remnawave && cd /opt/remnawave

    cat > docker-compose.yml <<EOF
version: "3"
services:
  panel:
    image: remnawave/panel:latest
    restart: always
    network_mode: host
    volumes:
      - ./data:/data
EOF

    docker compose up -d

# --- NODE ---
elif [ "$MODE" == "2" ]; then
    echo "[*] Установка NODE"

    read -p "IP панели: " PANEL_IP
    read -p "TOKEN: " TOKEN

    VPN_PORT=443
    ufw allow $VPN_PORT

    mkdir -p /opt/remnawave-node && cd /opt/remnawave-node

    cat > docker-compose.yml <<EOF
version: "3"
services:
  node:
    image: remnawave/node:latest
    restart: always
    network_mode: host
    environment:
      - PANEL_URL=http://$PANEL_IP
      - TOKEN=$TOKEN
EOF

    docker compose up -d

# --- ONLY SETUP ---
elif [ "$MODE" == "3" ]; then
    echo "[*] Только базовая настройка"
else
    echo "Ошибка"
    exit 1
fi

# --- Включение firewall ---
ufw --force enable

echo ""
echo "=== ГОТОВО ==="
echo "SSH: ssh -p $SSH_PORT $USERNAME@IP"
echo "Пароль пользователя для sudo: $USER_PASSWORD"
echo "Root вход отключён"
