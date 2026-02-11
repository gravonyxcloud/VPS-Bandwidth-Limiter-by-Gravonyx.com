cat << 'EOF' > painel.sh
#!/bin/bash

# Cores
VERDE='\033[0;32m'
CIANO='\033[0;36m'
AMARELO='\033[1;33m'
VERMELHO='\033[0;31m'
NC='\033[0m'

INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)

# Esconde o cursor para não ficar piscando
tput civis
# Quando fechar o script, o cursor volta ao normal
trap "tput cnorm; clear; exit" INT TERM

# Limpa a tela apenas UMA vez no início
clear

while true; do
    # Move o cursor para o início (0,0) sem apagar a tela
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
    echo -e "---------------------------------------------------------------"

    # Captura dados
    R1=$(cat /sys/class/net/$INTERFACE/statistics/rx_bytes)
    T1=$(cat /sys/class/net/$INTERFACE/statistics/tx_bytes)
    sleep 1
    R2=$(cat /sys/class/net/$INTERFACE/statistics/rx_bytes)
    T2=$(cat /sys/class/net/$INTERFACE/statistics/tx_bytes)
    
    MBPS_RX=$(( (R2 - R1) * 8 / 1048576 ))
    MBPS_TX=$(( (T2 - T1) * 8 / 1048576 ))
    
    # Pega o limite configurado no momento
    LIMITE_ATUAL=$(tc class show dev $INTERFACE | grep -oP 'rate \K[^\s]+' | head -1)
    [ -z "$LIMITE_ATUAL" ] && LIMITE_ATUAL="Sem Limite"

    # Usa printf para manter o alinhamento fixo (evita que o texto "pule")
    printf " DOWNLOAD ATUAL: ${VERDE}%-10s Mbps${NC}\n" "$MBPS_RX"
    printf " UPLOAD ATUAL:   ${VERDE}%-10s Mbps${NC}\n" "$MBPS_TX"
    printf " LIMITE ATIVO:   ${AMARELO}%-20s${NC}\n" "$LIMITE_ATUAL"
    echo -e "---------------------------------------------------------------"
    
    # Gráfico de barras fixo
    BARRA=$(( MBPS_RX / 25 ))
    [ $BARRA -gt 25 ] && BARRA=25
    printf " [${VERDE}%-25s${NC}] %s Mbps\n" "$(printf '#%.0s' $(seq 1 $BARRA 2>/dev/null))" "$MBPS_RX"
    
    echo -e "\n${AMARELO} Pressione [CTRL+C] para sair deste painel.${NC}"
    echo -e " (A IA continuará trabalhando no fundo)                      "
    
    # Limpa qualquer rastro de texto antigo que sobrar embaixo
    tput ed
done
EOF

chmod +x painel.sh
./painel.sh
