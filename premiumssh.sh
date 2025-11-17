#!/bin/bash
# =====================================================
#  PREMIUMSSH PRO - SSH PREMIUM AUTOSCRIPT
#  Ubuntu 20.04 / 22.04
#  Menu graphique + HTTP custom SSH
# =====================================================

# Colors
RED="\e[31m"
GREEN="\e[32m"
BLUE="\e[34m"
YELLOW="\e[33m"
NC="\e[0m"

clear
echo -e "${GREEN}==============================================="
echo -e "         PREMIUM SSH PRO AUTO-INSTALLER"
echo -e "===============================================${NC}"

# ---------------------------
# INSTALL DEPENDENCIES
# ---------------------------
apt update && apt upgrade -y
apt install -y curl wget jq screen net-tools \
dropbear stunnel4 openvpn nginx python3 python3-pip \
fail2ban ufw socat bzip2 dialog

# ---------------------------
# SSH PORT 22 CONFIG
# ---------------------------
sed -i 's/#Port 22/Port 22/' /etc/ssh/sshd_config
sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
systemctl restart ssh

# ---------------------------
# DROPBEAR CONFIG DEFAULT 443/80
# ---------------------------
cat >/etc/default/dropbear <<EOF
NO_START=0
DROPBEAR_PORT=443
DROPBEAR_EXTRA_ARGS="-p 80"
DROPBEAR_BANNER="/etc/issue.net"
EOF
echo "Premium SSH Server PRO" >/etc/issue.net
systemctl restart dropbear

# ---------------------------
# BADVPN
# ---------------------------
wget -O /usr/bin/badvpn "https://raw.githubusercontent.com/nkinmo/VPS-Autoscript/main/badvpn"
chmod +x /usr/bin/badvpn
screen -dmS badvpn badvpn --listen-addr 127.0.0.1:7300 --max-clients 500

# ---------------------------
# NGINX DEFAULT + WEBSOCKET
# ---------------------------
rm -f /etc/nginx/sites-enabled/default

cat >/etc/nginx/sites-enabled/premium.conf <<EOF
server {
    listen 80;
    server_name _;
    location /ssh {
        proxy_pass http://127.0.0.1:22;
        proxy_redirect off;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
    }
}
EOF

systemctl restart nginx

# ---------------------------
# STUNNEL SSL 443
# ---------------------------
mkdir -p /etc/stunnel
openssl req -new -x509 -days 1095 -nodes -subj "/CN=PremiumSSH PRO" \
    -out /etc/stunnel/stunnel.pem -keyout /etc/stunnel/stunnel.pem

cat >/etc/stunnel/stunnel.conf <<EOF
cert = /etc/stunnel/stunnel.pem
client = no
[dropbear]
accept = 443
connect = 127.0.0.1:22
EOF
sed -i 's/ENABLED=0/ENABLED=1/' /etc/default/stunnel4
systemctl restart stunnel4

# ---------------------------
# SLOWDNS
# ---------------------------
wget -O /usr/bin/dnstt-server "https://raw.githubusercontent.com/nkinmo/VPS-Autoscript/main/dnstt-server"
wget -O /usr/bin/dnstt-client "https://raw.githubusercontent.com/nkinmo/VPS-Autoscript/main/dnstt-client"
chmod +x /usr/bin/dnstt*
dnstt-server -gen-key -privkey-file /etc/dns.key -pubkey-file /etc/dns.pub
screen -dmS slowdns dnstt-server -udp :5300 -privkey-file /etc/dns.key example.com

# ---------------------------
# FIREWALL + FAIL2BAN
# ---------------------------
ufw allow 22
ufw allow 80
ufw allow 443
ufw allow 5300
ufw --force enable
systemctl restart fail2ban

# ---------------------------
# FUNCTION: CONFIGURE HTTP CUSTOM SSH
# ---------------------------
configure_http_ssh() {
    dialog --title "HTTP Custom SSH" --inputbox "Enter HTTP custom port:" 8 40 2> /tmp/http_port
    PORT=$(cat /tmp/http_port)

    sed -i "s/DROPBEAR_PORT=.*/DROPBEAR_PORT=$PORT/" /etc/default/dropbear
    systemctl restart dropbear

    cat >/etc/nginx/sites-enabled/ssh-http.conf <<EOF
server {
    listen $PORT;
    server_name _;
    location /ssh {
        proxy_pass http://127.0.0.1:22;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
    }
}
EOF
    nginx -t && systemctl restart nginx
    dialog --msgbox "SSH HTTP custom setup completed on port $PORT" 6 40
}

# ---------------------------
# PREMIUMSSH PRO MENU
# ---------------------------
while true; do
CHOICE=$(dialog --clear --backtitle "PremiumSSH PRO Menu" \
--title "MAIN MENU" \
--menu "Choose an option:" 15 50 9 \
1 "Create User" \
2 "Delete User" \
3 "List Users" \
4 "Expired / Renew Users" \
5 "Active Connections" \
6 "Restart Services" \
7 "Install / Update Services" \
8 "Configure SSH HTTP Custom" \
0 "Exit" 3>&1 1>&2 2>&3)

case $CHOICE in
1)
    dialog --title "Create User" --inputbox "Username:" 8 40 2> /tmp/user
    U=$(cat /tmp/user)
    dialog --title "Password" --inputbox "Password:" 8 40 2> /tmp/pass
    P=$(cat /tmp/pass)
    dialog --title "Days Valid" --inputbox "Valid days:" 8 40 2> /tmp/days
    D=$(cat /tmp/days)
    useradd -e $(date -d "$D days" +"%Y-%m-%d") -s /bin/false -M $U
    echo "$U:$P" | chpasswd
    dialog --msgbox "User $U created!" 6 40
    ;;
2)
    dialog --title "Delete User" --inputbox "Username:" 8 40 2> /tmp/user
    U=$(cat /tmp/user)
    userdel $U
    dialog --msgbox "User $U deleted!" 6 40
    ;;
3)
    USERS=$(cut -d: -f1 /etc/passwd | sort)
    dialog --msgbox "$USERS" 20 50
    ;;
4)
    EXPIRED=$(chage -l *)
    dialog --msgbox "$EXPIRED" 20 50
    ;;
5)
    ACTIVE=$(netstat -npt | grep ssh)
    dialog --msgbox "$ACTIVE" 20 50
    ;;
6)
    systemctl restart ssh dropbear nginx stunnel4
    dialog --msgbox "Services restarted!" 6 40
    ;;
7)
    dialog --msgbox "All services are up to date!" 6 40
    ;;
8)
    configure_http_ssh
    ;;
0)
    clear
    exit
    ;;
*)
    dialog --msgbox "Invalid option!" 6 40
    ;;
esac
done
