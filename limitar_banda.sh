cat << 'EOF' > instalar_ia_v9.sh
#!/bin/bash

VERDE='\033[0;32m'
NC='\033[0m'

clear
echo "INSTALADOR GRAVONYX IA v9.0"

read -p "Limite real da VPS (Mbps): " LIMITE_BASE
read -p "Interface (enter para auto): " INTERFACE

[ -z "$INTERFACE" ] && INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)

# Nunca permitir menos que 100mbit
[ "$LIMITE_BASE" -lt 100 ] && LIMITE_BASE=100

BOOST=$((LIMITE_BASE + 20))
MEDIO=$((LIMITE_BASE * 75 / 100))
MINIMO=100

cat << CONFIG > /etc/gravonyx_ia.conf
INTERFACE=$INTERFACE
LIMITE_BASE=$LIMITE_BASE
BOOST=$BOOST
MEDIO=$MEDIO
MINIMO=$MINIMO
EMAIL_DESTINO=gabrielbomfimsilva4@gmail.com
CONFIG

cat << 'WORKER' > /usr/local/bin/gravonyx_worker.sh
#!/bin/bash
source /etc/gravonyx_ia.conf

ESTADO_ARQUIVO="/tmp/gravonyx_estado"

enviar_email() {
echo -e "Subject: $1\n\n$2" | msmtp $EMAIL_DESTINO
}

aplicar_regra() {
tc qdisc del dev $INTERFACE root 2>/dev/null
tc qdisc del dev $INTERFACE ingress 2>/dev/null

tc qdisc add dev $INTERFACE root handle 1: htb default 20
tc class add dev $INTERFACE parent 1: classid 1:1 htb rate ${1}mbit ceil ${1}mbit
tc class add dev $INTERFACE parent 1:1 classid 1:10 htb rate 20mbit ceil ${1}mbit prio 1
tc class add dev $INTERFACE parent 1:1 classid 1:20 htb rate $((1-20))mbit ceil $((1-20))mbit prio 2

tc filter add dev $INTERFACE parent 1: protocol ip prio 1 u32 match ip dport 22 0xffff flowid 1:10
tc filter add dev $INTERFACE parent 1: protocol ip prio 1 u32 match ip sport 22 0xffff flowid 1:10
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
    aplicar_regra $BOOST
    ESTADO="BOOST"
elif [ "$CURRENT" -ge "$MEDIO" ]; then
    aplicar_regra $MEDIO
    ESTADO="MEDIO"
elif [ "$CURRENT" -ge "$MINIMO" ]; then
    aplicar_regra $MINIMO
    ESTADO="MINIMO"
else
    aplicar_regra $LIMITE_BASE
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
Description=Gravonyx IA
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

echo -e "${VERDE}INSTALADO E ATIVO${NC}"
EOF

chmod +x instalar_ia_v9.sh
./instalar_ia_v9.sh
