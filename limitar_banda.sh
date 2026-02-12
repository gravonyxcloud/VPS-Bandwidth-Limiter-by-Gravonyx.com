#!/bin/bash

echo "=== GRAVONYX IA PRO MONITOR ESTÁVEL ==="

read -p "Limite real da VPS em Mbps (ex: 450): " LIMITE_BASE
[ -z "$LIMITE_BASE" ] && LIMITE_BASE=450
[ "$LIMITE_BASE" -lt 100 ] && LIMITE_BASE=100

INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)

if [ -z "$INTERFACE" ]; then
echo "Erro: Interface de rede não detectada."
exit 1
fi

THRESHOLD=$((LIMITE_BASE * 95 / 100))
RESET=$((LIMITE_BASE * 70 / 100))

cat << CONF > /etc/gravonyx_ia.conf
INTERFACE=$INTERFACE
LIMITE_BASE=$LIMITE_BASE
THRESHOLD=$THRESHOLD
RESET=$RESET
EMAIL_DESTINO=gabrielbomfimsilva4@gmail.com
CONF

echo "Aplicando HTB..."

tc qdisc del dev $INTERFACE root 2>/dev/null

tc qdisc add dev $INTERFACE root handle 1: htb default 20

tc class add dev $INTERFACE parent 1: classid 1:1 htb rate ${LIMITE_BASE}mbit ceil ${LIMITE_BASE}mbit

tc class add dev $INTERFACE parent 1:1 classid 1:10 htb rate 20mbit ceil ${LIMITE_BASE}mbit prio 1

RESTO=$((LIMITE_BASE-20))
[ "$RESTO" -lt 50 ] && RESTO=50

tc class add dev $INTERFACE parent 1:1 classid 1:20 htb rate ${RESTO}mbit ceil ${RESTO}mbit prio 2

tc filter add dev $INTERFACE parent 1: protocol ip prio 1 u32 match ip dport 22 0xffff flowid 1:10
tc filter add dev $INTERFACE parent 1: protocol ip prio 1 u32 match ip sport 22 0xffff flowid 1:10

cat << 'WORKER' > /usr/local/bin/gravonyx_worker.sh
#!/bin/bash
source /etc/gravonyx_ia.conf

STATE_FILE="/tmp/gravonyx_state"

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

[ ! -f "$STATE_FILE" ] && echo "normal" > $STATE_FILE

while true; do

USAGE=$(get_usage)
STATE=$(cat $STATE_FILE)

if [ "$STATE" = "normal" ]; then

if [ "$USAGE" -ge "$THRESHOLD" ]; then

START=$(date +%s)

while true; do
sleep 10
USAGE=$(get_usage)
NOW=$(date +%s)
ELAPSED=$((NOW - START))

if [ "$USAGE" -lt "$THRESHOLD" ]; then
break
fi

if [ "$ELAPSED" -ge 120 ]; then
echo "alerted" > $STATE_FILE

echo "Servidor: $(hostname)
Uso detectado: ${USAGE} Mbps
Limite: ${LIMITE_BASE} Mbps
Horário: $(date)" | mail -s "ALERTA PICO DE BANDA" $EMAIL_DESTINO

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

echo "=== GRAVONYX IA PRO ATIVO E FUNCIONANDO ==="
