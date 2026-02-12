cat << 'EOF' > instalar_gravonyx_pro.sh
#!/bin/bash

echo "=== GRAVONYX IA PRO ==="

read -p "Limite base real da VPS (ex 600): " LIMITE_BASE
[ "$LIMITE_BASE" -lt 100 ] && LIMITE_BASE=100

INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)

BOOST=$((LIMITE_BASE + 20))
MEDIO=$((LIMITE_BASE * 75 / 100))
MINIMO=100

cat << CONF > /etc/gravonyx_ia.conf
INTERFACE=$INTERFACE
LIMITE_BASE=$LIMITE_BASE
BOOST=$BOOST
MEDIO=$MEDIO
MINIMO=$MINIMO
EMAIL_DESTINO=gabrielbomfimsilva4@gmail.com
CONF

# CRIA HTB UMA ÚNICA VEZ
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

ESTADO_ARQUIVO="/tmp/gravonyx_estado"

enviar_email() {
echo -e "Subject: $1\n\n$2" | msmtp $EMAIL_DESTINO
}

alterar_taxa() {

TAXA=$1
[ "$TAXA" -lt 100 ] && TAXA=100

RESTO=$((TAXA-20))
[ "$RESTO" -lt 80 ] && RESTO=80

tc class change dev $INTERFACE parent 1: classid 1:1 htb rate ${TAXA}mbit ceil ${TAXA}mbit
tc class change dev $INTERFACE parent 1:1 classid 1:10 htb rate 20mbit ceil ${TAXA}mbit
tc class change dev $INTERFACE parent 1:1 classid 1:20 htb rate ${RESTO}mbit ceil ${RESTO}mbit
}

while true; do

RX1=$(cat /sys/class/net/$INTERFACE/statistics/rx_bytes)
TX1=$(cat /sys/class/net/$INTERFACE/statistics/tx_bytes)
sleep 2
RX2=$(cat /sys/class/net/$INTERFACE/statistics/rx_bytes)
TX2=$(cat /sys/class/net/$INTERFACE/statistics/tx_bytes)

SPEED_RX=$(( (RX2 - RX1) * 8 / 2 / 1048576 ))
SPEED_TX=$(( (TX2 - TX1) * 8 / 2 / 1048576 ))
CURRENT=$(( SPEED_RX > SPEED_TX ? SPEED_RX : SPEED_TX ))

if [ "$CURRENT" -ge "$(( LIMITE_BASE - 10 ))" ]; then
    alterar_taxa $BOOST
    ESTADO="BOOST"
elif [ "$CURRENT" -ge "$MEDIO" ]; then
    alterar_taxa $MEDIO
    ESTADO="MEDIO"
elif [ "$CURRENT" -ge "$MINIMO" ]; then
    alterar_taxa $MINIMO
    ESTADO="MINIMO"
else
    alterar_taxa $LIMITE_BASE
    ESTADO="BASE"
fi

if [ -f "$ESTADO_ARQUIVO" ]; then
    read ESTADO_ANTERIOR < "$ESTADO_ARQUIVO"
else
    ESTADO_ANTERIOR="NENHUM"
fi

if [ "$ESTADO" != "$ESTADO_ANTERIOR" ]; then
    enviar_email "Mudança de Estado: $ESTADO" \
"Servidor: $(hostname)
Estado anterior: $ESTADO_ANTERIOR
Novo estado: $ESTADO
Upload: $SPEED_TX Mbps
Download: $SPEED_RX Mbps
Hora: $(date)"
    echo "$ESTADO" > "$ESTADO_ARQUIVO"
fi

sleep 3
done
WORKER

chmod +x /usr/local/bin/gravonyx_worker.sh

cat << SERVICE > /etc/systemd/system/gravonyx-ia.service
[Unit]
Description=Gravonyx IA PRO
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

echo "=== GRAVONYX IA PRO ATIVO ==="
EOF

chmod +x instalar_gravonyx_pro.sh
./instalar_gravonyx_pro.sh
