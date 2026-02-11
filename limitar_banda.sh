#!/bin/bash
source /etc/gravonyx_ia.conf

PISO_MINIMO=100

# Garante piso mínimo absoluto
if [ "$MINIMO" -lt "$PISO_MINIMO" ]; then
    MINIMO=$PISO_MINIMO
fi

if [ "$MEDIO" -lt "$PISO_MINIMO" ]; then
    MEDIO=$PISO_MINIMO
fi

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

alterar_rate_upload() {
    NOVO=$1
    tc class change dev $INTERFACE parent 1: classid 1:1 htb rate ${NOVO}mbit ceil ${NOVO}mbit 2>/dev/null
    tc class change dev $INTERFACE parent 1:1 classid 1:20 htb rate $((NOVO-15))mbit ceil ${NOVO}mbit 2>/dev/null
}

alterar_rate_download() {
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

        if [ $(( RANDOM % 2 )) -eq 0 ]; then
            TARGET=$MINIMO
        else
            TARGET=$MEDIO
        fi

    else
        TARGET=$LIMITE_BASE
    fi

    # Aplica conforme modo escolhido
    if [ "$TIPO_IA" == "1" ]; then
        alterar_rate_upload $TARGET
    elif [ "$TIPO_IA" == "2" ]; then
        alterar_rate_download $TARGET
    else
        alterar_rate_upload $TARGET
        alterar_rate_download $TARGET
    fi

    sleep 5
done
