cat << 'EOF' > painel.sh
#!/bin/bash

# Cores
VERDE='\033[0;32m'
CIANO='\033[0;36m'
AMARELO='\033[1;33m'
VERMELHO='\033[0;31m'
NC='\033[0m'

INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)

while true; do
    clear
    echo -e "${CIANO}###############################################################"
    echo -e "#                                                             #"
    echo -e "#            MONITOR DE TRÁFEGO GRAVONYX IA                   #"
    echo -e "#                                                             #"
    echo -e "###############################################################${NC}"
    
    # Status do Serviço
    STATUS=$(systemctl is-active gravonyx-ia)
    if [ "$STATUS" == "active" ]; then
        echo -e "Status do Serviço: ${VERDE}● RODANDO EM SEGUNDO PLANO${NC}"
    else
        echo -e "Status do Serviço: ${VERMELHO}○ PARADO${NC}"
    fi

    # Captura velocidade atual
    R1=$(cat /sys/class/net/$INTERFACE/statistics/rx_bytes)
    T1=$(cat /sys/class/net/$INTERFACE/statistics/tx_bytes)
    sleep 1
    R2=$(cat /sys/class/net/$INTERFACE/statistics/rx_bytes)
    T2=$(cat /sys/class/net/$INTERFACE/statistics/tx_bytes)
    
    MBPS_RX=$(( (R2 - R1) * 8 / 1048576 ))
    MBPS_TX=$(( (T2 - T1) * 8 / 1048576 ))

    # Pega o limite atual aplicado no TC
    LIMITE_ATUAL=$(tc class show dev $INTERFACE | grep -oP 'rate \K[^\s]+' | head -1)
    [ -z "$LIMITE_ATUAL" ] && LIMITE_ATUAL="Sem Limite"

    echo -e "---------------------------------------------------------------"
    echo -e "DOWNLOAD ATUAL: ${VERDE}$MBPS_RX Mbps${NC}"
    echo -e "UPLOAD ATUAL:   ${VERDE}$MBPS_TX Mbps${NC}"
    echo -e "LIMITE ATIVO:   ${AMARELO}$LIMITE_ATUAL${NC}"
    echo -e "---------------------------------------------------------------"
    echo -e "${CIANO}Dica: Deixe esta janela aberta para monitorar.${NC}"
    echo -e "${AMARELO}Pressione [CTRL+C] para fechar o painel (a IA continuará rodando).${NC}"
    
    # Simulação de gráfico simples
    echo -ne "Gráfico: ["
    for ((i=0; i<($MBPS_RX/20); i++)); do echo -ne "#"; done
    for ((i=($MBPS_RX/20); i<30; i++)); do echo -ne " "; done
    echo -e "]"
done
EOF

chmod +x painel.sh
./painel.sh
