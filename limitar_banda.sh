cat << 'EOF' > instalar_gravonyx_pro.sh
#!/bin/bash

echo "=== GRAVONYX IA PRO MONITOR INTELIGENTE ==="

apt update -y >/dev/null 2>&1
apt install -y msmtp msmtp-mta mailutils >/dev/null 2>&1

read -p "Limite real da VPS em Mbps (ex: 450): " LIMITE_BASE
[ -z "$LIMITE_BASE" ] && LIMITE_BASE=450
[ "$LIMITE_BASE" -lt 100 ] && LIMITE_BASE=100

INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)

THRESHOLD=$((LIMITE_BASE * 95 / 100))
RESET=$((LIMITE_BASE * 70 / 100))

cat << CONF > /etc/gravonyx_ia.conf
INTERFACE=$INTERFACE
LIMITE_BASE=$LIMITE_BASE
THRESHOLD=$THRESHOLD
RESET=$RESET
EMAIL_DESTINO=gabrielbomfimsilva4@gmail.com
CONF

echo "Configurando HTB..."

tc qdisc del dev $INTERFACE root 2>/dev/null
tc qdisc add dev $INTERFACE root handle 1: htb default 20

tc class add dev $INTERFACE parent 1: classid 1:1 htb rate ${LIMITE_BASE}mbit ceil ${LIMITE_BASE}mbit
tc class add dev $INTERFACE parent 1:1 classid 1:10 htb rate 20mbit ceil ${LIMITE_BASE}mbit prio 1

RESTO=$((LIMITE_BASE-20))
[ "$RESTO" -lt 80 ] && RESTO=80

tc class add dev $INTERFACE parent 1:1 classid 1:20 htb rate ${RESTO}mbit ceil ${RESTO}mbit prio 2

tc filter add dev $INTERFACE parent 1: protocol ip prio 1 u32 match ip dport 22 0xffff flowid 1:10
tc filter add dev $INTERFACE parent 1: protocol ip prio 1 u32 match ip sport 22 0xffff flowid 1:10

cat << 'WORKER' > /usr/local/bin/gravonyx_worker.sh
#!/bin/bash
source /etc/gravonyx_ia.conf

STATE_FILE="/tmp/gravonyx_state"
ALERT_FILE="/tmp/gravonyx_alert_lock"

get_usage() {
RX1=$(cat /sys/class/net/$INTERFACE/statistics/rx_bytes)
TX1=$(cat /sys/class/net/$INTERFACE/statistics/tx_bytes)
sleep 10
RX2=$(cat /sys/class/net/$INTERFACE/statistics/rx_bytes)
TX2=$(cat /sys/class/net/$INTERFACE/statistics/tx_bytes)

RX_RATE=$(( (RX2 - RX1) * 8 / 1024 / 1024 / 10 ))
TX_RATE=$(( (TX2 - TX1) * 8 / 1024 / 1024 / 10 ))

echo $((RX_RATE + TX_RATE))
}

if [ ! -f "$STATE_FILE" ]; then
echo "normal" > $STATE_FILE
fi

while true; do

USAGE=$(get_usage)
STATE=$(cat $STATE_FILE)

if [ "$STATE" = "normal" ]; then

if [ "$USAGE" -ge "$THRESHOLD" ]; then

START=$(date +%s)

while [ "$USAGE" -ge "$THRESHOLD" ]; do
sleep 10
USAGE=$(get_usage)
NOW=$(date +%s)
ELAPSED=$((NOW - START))

if [ "$ELAPSED" -ge 120 ]; then
echo "alerted" > $STATE_FILE

echo -e "Subject: ALERTA PICO DE BANDA\n\nServidor: $(hostname)\nUso: ${USAGE} Mbps\nLimite: ${LIMITE_BASE} Mbps\nHora: $(date)" | msmtp $EMAIL_DESTINO

break
fi
done

fi

elif [ "$STATE" = "alerted" ]; then

if [ "$USAGE" -le "$RESET" ]; then
echo "normal" > $STATE_FILE
fi

fi

sleep 5
done
WORKER

chmod +x /usr/local/bin/gravonyx_worker.sh

cat << SERVICE > /etc/systemd/system/gravonyx-ia.service
[Unit]
Description=Gravonyx IA Monitor Inteligente
After=network.target

[Service]
ExecStart=/usr/local/bin/gravonyx_worker.sh
Restart=always
User=root

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable gravonyx-ia
systemctl restart gravonyx-ia

echo "=== GRAVONYX IA PRO ATIVO COM ALERTA INTELIGENTE ==="
EOF

chmod +x instalar_gravonyx_pro.sh
./instalar_gravonyx_pro.sh
