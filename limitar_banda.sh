#!/bin/bash

echo "=== GRAVONYX AUTO LIMITADOR DINÂMICO ==="

read -p "Limite real da VPS em Mbps (ex: 450): " LIMITE_BASE
[ -z "$LIMITE_BASE" ] && LIMITE_BASE=450
[ "$LIMITE_BASE" -lt 100 ] && LIMITE_BASE=100

INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)

if [ -z "$INTERFACE" ]; then
echo "Interface não detectada."
exit 1
fi

THRESHOLD=$((LIMITE_BASE * 95 / 100))
REDUZIDO=$((LIMITE_BASE * 70 / 100))
RESET=$((LIMITE_BASE * 60 / 100))

cat << CONF > /etc/gravonyx_auto.conf
INTERFACE=$INTERFACE
LIMITE_BASE=$LIMITE_BASE
THRESHOLD=$THRESHOLD
REDUZIDO=$REDUZIDO
RESET=$RESET
CONF

tc qdisc del dev $INTERFACE root 2>/dev/null
tc qdisc add dev $INTERFACE root handle 1: htb default 10
tc class add dev $INTERFACE parent 1: classid 1:1 htb rate ${LIMITE_BASE}mbit ceil ${LIMITE_BASE}mbit

cat << 'WORKER' > /usr/local/bin/gravonyx_auto_worker.sh
#!/bin/bash
source /etc/gravonyx_auto.conf

STATE_FILE="/tmp/gravonyx_auto_state"
[ ! -f "$STATE_FILE" ] && echo "normal" > $STATE_FILE

get_usage() {
RX1=$(cat /sys/class/net/$INTERFACE/statistics/rx_bytes)
TX1=$(cat /sys/class/net/$INTERFACE/statistics/tx_bytes)
sleep 5
RX2=$(cat /sys/class/net/$INTERFACE/statistics/rx_bytes)
TX2=$(cat /sys/class/net/$INTERFACE/statistics/tx_bytes)

RX_RATE=$(( (RX2 - RX1) * 8 / 1024 / 1024 / 5 ))
TX_RATE=$(( (TX2 - TX1) * 8 / 1024 / 1024 / 5 ))

echo $((RX_RATE + TX_RATE))
}

while true; do

USAGE=$(get_usage)
STATE=$(cat $STATE_FILE)

if [ "$STATE" = "normal" ]; then

if [ "$USAGE" -ge "$THRESHOLD" ]; then
START=$(date +%s)

while true; do
sleep 5
USAGE=$(get_usage)
NOW=$(date +%s)
ELAPSED=$((NOW - START))

if [ "$USAGE" -lt "$THRESHOLD" ]; then
break
fi

if [ "$ELAPSED" -ge 60 ]; then
tc class change dev $INTERFACE parent 1: classid 1:1 htb rate ${REDUZIDO}mbit ceil ${REDUZIDO}mbit
echo "limitado" > $STATE_FILE
break
fi
done
fi

elif [ "$STATE" = "limitado" ]; then

if [ "$USAGE" -le "$RESET" ]; then
tc class change dev $INTERFACE parent 1: classid 1:1 htb rate ${LIMITE_BASE}mbit ceil ${LIMITE_BASE}mbit
echo "normal" > $STATE_FILE
fi

fi

sleep 3
done
WORKER

chmod +x /usr/local/bin/gravonyx_auto_worker.sh

cat << SERVICE > /etc/systemd/system/gravonyx-auto.service
[Unit]
Description=Gravonyx Auto Bandwidth Control
After=network.target

[Service]
ExecStart=/usr/local/bin/gravonyx_auto_worker.sh
Restart=always
User=root

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable gravonyx-auto
systemctl restart gravonyx-auto

echo "=== AUTO LIMITADOR ATIVO ==="
