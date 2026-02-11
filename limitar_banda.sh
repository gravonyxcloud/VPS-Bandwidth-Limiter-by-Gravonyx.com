cat << 'EOF' > painel.sh
#!/bin/bash

# Cores
VERDE='\033[0;32m'
CIANO='\033[0;36m'
AMARELO='\033[1;33m'
VERMELHO='\033[0;31m'
NC='\033[0m'

INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)

# Esconde o cursor para ficar mais bonito
tput civis
trap "tput cnorm; exit" INT TERM

clear
while true; do
    # Move o cursor para o topo em vez de limpar a tela
    tput cup 0 0
    echo -e "${CIANO}###############################################################"
    echo -e "#                                                             #"
    echo -e "#            MONITOR DE TRÁFEGO GRAVONYX IA                   #"
    echo -e "#                                                             #"
    echo -e "###############################################################${NC}"
    
    STATUS=$(systemctl is-active gravonyx-ia)
    if [ "$STATUS" == "active" ]; then
        echo -e " Status: ${VERDE}● RODANDO EM SEGUNDO PLANO${NC}                           "
    else
        echo -e " Status: ${VERMELHO}○ PARADO${NC}                                            "
    fi

    R1=$(cat /sys/class/net/$INTERFACE/statistics/rx_bytes)
    T1=$(cat /sys/class/net/$INTERFACE/statistics/tx_bytes)
    sleep 1
    R2=$(cat /sys/class/net/$INTERFACE/statistics/rx_bytes)
    T2=$(cat /sys/class/net/$INTERFACE/statistics/tx_bytes)
    
    MBPS_RX=$(( (R2 - R1) * 8 / 1048576 ))
    MBPS_TX=$(( (T2 - T1) * 8 / 1048576 ))
    LIMITE_ATUAL=$(tc class show dev $INTERFACE | grep -oP 'rate \K[^\s]+' | head -1)

    echo -e "---------------------------------------------------------------"
    printf " DOWNLOAD ATUAL: ${VERDE}%-10s Mbps${NC}\n" "$MBPS_RX"
    printf " UPLOAD ATUAL:   ${VERDE}%-10s Mbps${NC}\n" "$MBPS_TX"
    printf " LIMITE ATIVO:   ${AMARELO}%-10s${NC}\n" "${LIMITE_ATUAL:-Sem Limite}"
    echo -e "---------------------------------------------------------------"
    
    # Barra de progresso sem flickering
    BARRA_TAM=$((MBPS_RX / 20))
    [ $BARRA_TAM -gt 30 ] && BARRA_TAM=30
    printf " Gráfico: [${VERDE}%-30s${NC}]\n" "$(printf '#%.0s' $(seq 1 $BARRA_TAM 2>/dev/null))"
    echo -e "${AMARELO} Pressione [CTRL+C] para sair do painel.${NC}               "
done
EOF

chmod +x painel.sh
./painel.sh
