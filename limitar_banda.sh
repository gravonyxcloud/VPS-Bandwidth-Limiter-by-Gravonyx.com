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

    # Pega o rate real aplicado no upload
    RATE_UPLOAD=$(tc class show dev $INTERFACE 2>/dev/null | \
        grep "class htb 1:1" | grep -oP 'rate \K[0-9]+mbit')

    # Pega o rate real aplicado no download (se existir)
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
