cat << 'EOF' > instalar_ia.sh
#!/bin/bash

VERDE='\033[0;32m'
CIANO='\033[0;36m'
AMARELO='\033[1;33m'
NC='\033[0m'

clear
echo -e "${CIANO}###############################################################"
echo -e "#                 GRAVONYX IA v9.1 COMPLETE                   #"
echo -e "###############################################################${NC}"

read -p "Qual o limite real da sua VPS em Mbps? (ex: 600): " LIMITE_BASE
read -p "Deseja limitar Upload, Download ou Ambos? (1=Up, 2=Down, 3=Ambos): " TIPO_IA

INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)

BOOST=$(( LIMITE_BASE + 10 ))
MINIMO_CALC=$(( LIMITE_BASE / 2 ))
MEDIO_CALC=$(( LIMITE_BASE * 3 / 4 ))

# Piso absoluto 100mbit
[ "$MINIMO_CALC" -lt 100 ] && MINIMO=100 || MINIMO=$MINIMO_CALC
[ "$MEDIO_CALC" -lt 100 ] && MEDIO=100 || MEDIO=$MEDIO_CALC

cat << CONFIG > /etc/gravonyx_ia.conf
INTERFACE=$INTERFACE
LIMITE_BASE=$LIMITE_BASE
TIPO_IA=$TIPO_IA
BOOST=$BOOST
MINIMO=$MINIMO
MEDIO=$MEDIO
CONFIG

# ================= WORKER =================

cat << 'WORKER' > /usr/local/bin/gravonyx_worker.sh
#!/bin/bash
source /etc/gravonyx_ia.conf

PISO_MINIMO=100
[ "$MINIMO" -lt "$PISO_MINIMO" ] && MINIMO=$PISO_MINIMO
[ "$MEDIO" -lt "$PISO_MINIMO" ] && MEDIO=$PISO_MINIMO

criar_estrutura() {

    tc qdisc del dev $INTERFACE root 2>/dev/null
    tc qdisc del dev $INTERFACE ingress 2>/dev/null

    if [ "$TIPO_IA" == "1" ] || [ "$TIPO_IA" == "3" ]; then
        tc qdisc add dev $INTERFACE root handle 1: htb default 20
        tc class add dev $INTERFACE parent 1: classid 1:1 htb rate ${LIMITE_BASE}mbit ceil ${LIMITE_BASE}mbit
        tc class add dev $INTERFACE parent 1:1 classid 1:10 htb rate 15mbit ceil ${LIMITE_BASE}mbit prio 1
        tc class add dev $INTERFACE parent 1:1 classid 1:20 htb rate $((LIMITE_BASE-15))mbit ceil ${LIMITE_BASE}mbit prio 2

        tc filter add dev $INTERFACE parent 1: protocol ip prio 1 u32 match ip dport 22 0xffff flowid 1:10
        tc filter add dev $INTERFACE parent 1: protocol ip prio 1 u32 match ip sport 22 0xffff flowid 1:10
    fi

    if [ "$TIPO_IA" == "2" ] || [ "$TIPO_IA" == "3" ]; then
        tc qdisc add dev $INTERFACE handle ffff: ingress
        tc filter add dev $INTERFACE parent ffff: protocol all u32 match u32 0 0 \
        police rate ${LIMITE_BASE}mbit burst 1mb mtu 64kb drop flowid :1
    fi
}

alterar_upload() {
    NOVO=$1
    tc class change dev $INTERFACE parent 1: classid 1:1 htb rate ${NOVO}mbit ceil ${NOVO}mbit 2>/dev/null
    tc class change dev $INTERFACE parent 1:1 classid 1:20 htb rate $((NOVO-15))mbit ceil ${NOVO}mbit 2>/dev/null
}

alterar_download() {
    NOVO=$1
    tc filter replace dev $INTERFACE parent ffff: protocol all u32 match u32 0 0 \
    police rate ${NOVO}mbit burst 1mb mtu 64kb drop flowid :1 2>/dev/null
}

criar_estrutura

while true; do

    RX1=$(cat /sys/class/net/$INTERFACE/statistics/rx_bytes)
    TX1=$(cat /sys/class/net/$INTERFACE/statistics/tx_bytes)
    sleep 2
    RX2=$(cat /sys/class/net/$INTERFACE/statistics/rx_bytes)
    TX2=$(cat /sys/class/net/$INTERFACE/statistics/tx_bytes)

    SPEED_RX=$(( (RX2 - RX1) * 8 / 2 / 1048576 ))
    SPEED_TX=$(( (TX2 - TX1) * 8 / 2 / 1048576 ))
    CURRENT=$(( SPEED_RX > SPEED_TX ? SPEED_RX : SPEED_TX ))

    if [ "$CURRENT" -ge "$(( LIMITE_BASE - 15 ))" ]; then
        TARGET=$BOOST
        sleep 8
        [ $(( RANDOM % 2 )) -eq 0 ] && TARGET=$MINIMO || TARGET=$MEDIO
    else
        TARGET=$LIMITE_BASE
    fi

    if [ "$TIPO_IA" == "1" ]; then
        alterar_upload $TARGET
    elif [ "$TIPO_IA" == "2" ]; then
        alterar_download $TARGET
    else
        alterar_upload $TARGET
        alterar_download $TARGET
    fi

    sleep 5
done
WORKER

chmod +x /usr/local/bin/gravonyx_worker.sh

# ================= PAINEL =================

cat << 'PANEL' > /usr/local/bin/painel.sh
#!/bin/bash
source /etc/gravonyx_ia.conf

tput civis
trap "tput cnorm; clear; exit" INT TERM
clear

while true; do
    tput cup 0 0

    echo -e "\e[36m###############################################################"
    echo -e "#            MONITOR DE TRÁFEGO GRAVONYX IA                   #"
    echo -e "###############################################################\e[0m"

    R1=$(cat /sys/class/net/$INTERFACE/statistics/rx_bytes)
    T1=$(cat /sys/class/net/$INTERFACE/statistics/tx_bytes)
    sleep 1
    R2=$(cat /sys/class/net/$INTERFACE/statistics/rx_bytes)
    T2=$(cat /sys/class/net/$INTERFACE/statistics/tx_bytes)

    RX=$(( (R2-R1)*8/1048576 ))
    TX=$(( (T2-T1)*8/1048576 ))

    RATE_UPLOAD=$(tc class show dev $INTERFACE 2>/dev/null | \
        grep "class htb 1:1" | grep -oP 'rate \K[0-9]+mbit')

    RATE_DOWNLOAD=$(tc filter show dev $INTERFACE parent ffff: 2>/dev/null | \
        grep -oP 'rate \K[0-9]+mbit' | head -1)

    echo " Status: ● SERVIÇO ATIVO"
    echo "---------------------------------------------------------------"

    printf " DOWNLOAD ATUAL: %-10s Mbps\n" "$RX"
    printf " UPLOAD ATUAL:   %-10s Mbps\n" "$TX"

    echo "---------------------------------------------------------------"

    if [ "$TIPO_IA" == "1" ]; then
        printf " LIMITADOR UPLOAD:   %-10s\n" "${RATE_UPLOAD:-Base}"
    elif [ "$TIPO_IA" == "2" ]; then
        printf " LIMITADOR DOWNLOAD: %-10s\n" "${RATE_DOWNLOAD:-Base}"
    else
        printf " LIMITADOR UPLOAD:   %-10s\n" "${RATE_UPLOAD:-Base}"
        printf " LIMITADOR DOWNLOAD: %-10s\n" "${RATE_DOWNLOAD:-Base}"
    fi

    echo "---------------------------------------------------------------"
    echo " Pressione CTRL+C para sair"
    tput ed
done
PANEL

chmod +x /usr/local/bin/painel.sh

# ================= COMANDO =================

echo '#!/bin/bash
if [ "$1" == "status" ]; then
    /usr/local/bin/painel.sh
else
    echo "Uso: traffic status"
fi' > /usr/local/bin/traffic

chmod +x /usr/local/bin/traffic

# ================= SYSTEMD =================

cat << SERVICE > /etc/systemd/system/gravonyx-ia.service
[Unit]
Description=Gravonyx IA Bandwidth Management
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/gravonyx_worker.sh
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable gravonyx-ia
systemctl restart gravonyx-ia

echo -e "\n${VERDE}✅ INSTALAÇÃO CONCLUÍDA!${NC}"
echo -e "Use: ${AMARELO}traffic status${NC}"
EOF

chmod +x instalar_ia.sh
./instalar_ia.sh
