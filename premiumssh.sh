#!/bin/bash
# =====================================================
#  PREMIUMSSH - SSH PREMIUM AUTOSCRIPT
#  Ubuntu 20.04 / 22.04
#  By: Mourad (version spéciale)
# =====================================================

clear
echo "==============================================="
echo "         PREMIUM SSH AUTO-INSTALLER"
echo "==============================================="

# ---------------------------
#   UPDATE & INSTALL BASICS
# ---------------------------
apt update && apt upgrade -y
apt install -y curl wget jq screen net-tools \
               dropbear stunnel4 openvpn \
               nginx python3 python3-pip \
               fail2ban ufw socat bzip2

# ---------------------------
#  CONFIG SSH (PORT 22)
# ---------------------------
sed -i 's/#Port 22/Port 22/' /etc/ssh/sshd_config
sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
systemctl restart ssh

# ---------------------------
#  CONFIG DROPBEAR (80/443)
# ---------------------------
cat >/etc/default/dropbear <<EOF
NO_START=0
DROPBEAR_PORT=443
DROPBEAR_EXTRA_ARGS="-p 80"
DROPBEAR_BANNER="/etc/issue.net"
EOF
systemctl restart dropbear

echo "Premium SSH Server" >/etc/issue.net

# ---------------------------
#   BADVPN UDPGW
# ---------------------------
wget -O /usr/bin/badvpn "https://raw.githubusercontent.com/forphc/VPS-Autoscript/main/badvpn"
chmod +x /usr/bin/badvpn

screen -dmS badvpn badvpn --listen-addr 127.0.0.1:7300 --max-clients 500

# ---------------------------
#   NGINX + WEBSOCKET
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
    }
}
EOF

systemctl restart nginx

# ---------------------------
#   STUNNEL SSL (443)
# ---------------------------
apt install openssl -y
mkdir -p /etc/stunnel

openssl req -new -x509 -days 1095 -nodes \
    -subj "/CN=PremiumSSH" \
    -out /etc/stunnel/stunnel.pem \
    -keyout /etc/stunnel/stunnel.pem

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
#   SLOWDNS (DNSTT)
# ---------------------------
wget -O /usr/bin/dnstt-server "https://raw.githubusercontent.com/forphc/VPS-Autoscript/main/dnstt-server"
wget -O /usr/bin/dnstt-client "https://raw.githubusercontent.com/forphc/VPS-Autoscript/main/dnstt-client"
chmod +x /usr/bin/dnstt*

# Domain KEY
dnstt-server -gen-key -privkey-file /etc/dns.key -pubkey-file /etc/dns.pub

screen -dmS slowdns dnstt-server -udp :5300 -privkey-file /etc/dns.key example.com

# ---------------------------
#   FIREWALL + FAIL2BAN
# ---------------------------
ufw allow 22
ufw allow 80
ufw allow 443
ufw allow 5300
ufw --force enable

systemctl restart fail2ban

# ---------------------------
#   MENU (premiumssh)
# ---------------------------
cat >/usr/bin/premiumssh <<'EOF'
#!/bin/bash
clear
echo "=============================="
echo "      PREMIUM SSH MENU"
echo "=============================="
echo "1) Create user"
echo "2) Delete user"
echo "3) Check users"
echo "4) Expire users"
echo "5) Active connections"
echo "6) Restart services"
echo "0) Exit"
echo -n "Choice: "
read x

case $x in
1) read -p "Username: " u
   read -p "Password: " p
   read -p "Days: " d
   useradd -e $(date -d "$d days" +"%Y-%m-%d") -s /bin/false -M $u
   echo "$u:$p" | chpasswd
   echo "User added!"
   ;;
2) read -p "Username: " u
   userdel $u
   echo "User removed!"
   ;;
3) cut -d: -f1 /etc/passwd | sort
   ;;
4) chage -l *
   ;;
5) netstat -npt | grep ssh
   ;;
6) systemctl restart ssh dropbear nginx stunnel4
   echo "All services restarted."
   ;;
0) exit;;
esac
EOF

chmod +x /usr/bin/premiumssh

# ---------------------------
#  FIN
# ---------------------------
clear
echo "========================================="
echo "   PREMIUMSSH INSTALLATION COMPLETE"
echo "========================================="
echo "SSH Port: 22"
echo "Dropbear: 80 / 443"
echo "WebSocket: ws://IP/ssh"
echo "BadVPN: 7300"
echo "SlowDNS: 5300"
echo "Menu: premiumssh"
echo "========================================="
