cat << 'EOF' > limitar_banda_ia.sh
#!/bin/bash

# Cores
VERDE='\033[0;32m'
CIANO='\033[0;36m'
AMARELO='\033[1;33m'
VERMELHO='\033[0;31m'
NC='\033[0m'

# 1. VERIFICAÇÃO DE DEPENDÊNCIAS
if ! command -v tc &> /dev/null || ! command -v ethtool &> /dev/null; then
    echo -e "${AMARELO}Instalando ferramentas de rede...${NC}"
    apt-get update -y &>/dev/null
    apt-get install iproute2 ethtool -y &>/dev/null
fi

INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)

# 2. BANNER GRAVONYX
clear
echo -e "${CIANO}###############################################################"
echo -e "#                                                             #"
echo -e "#    ____                                                     #"
echo -e "#   / ___|_ __ __ ___   _____  _ __  _   ___  __              #"
echo -e "#  | |  _| '__/ _\` \ \ / / _ \| '_ \| | | \ \/ /              #"
echo -e "#  | |_| | | | (_| |\ V / (_) | | | | |_| |>  <               #"
echo -e "#   \____|_|  \__,_| \_/ \___/|_| |_|\__, /_/\_\              #"
echo -e "#                                    |___/                    #"
echo -e "#                                                             #"
echo -e "#  ${VERDE}FEITO POR: GRAVONYX.COM${NC}     |     ${AMARELO}MODO: IA DINÂMICA${CIANO}      #"
echo -e "###############################################################${NC}"

# 3. ENTRADA DO USUÁRIO
echo -e "\n${AMARELO}CONFIGURAÇÃO DE BANDA DINÂMICA${NC}"
read -p "Qual o limite real da sua VPS em Mbps? (ex: 600): " LIMITE_BASE
read -p "Deseja limitar Upload, Download ou Ambos? (1=Up, 2=Down, 3=Ambos): " TIPO_IA

# Cálculos Automáticos
BOOST=$(( LIMITE_BASE + 10 ))
MINIMO=$(( LIMITE_BASE / 2 ))     # 50% da banda
MEDIO=$(( LIMITE_BASE * 3 / 4 ))  # 75% da banda

echo -e "\n${VERDE}Configuração concluída:${NC}"
echo -e "Teto Máximo: ${AMARELO}${LIMITE_BASE} Mbps${NC}"
echo -e "Boost de Pico: ${VERDE}${BOOST} Mbps${NC}"
echo -e "Resfriamento: ${VERMELHO}${MINIMO} ou ${MEDIO} Mbps${NC}"
echo -e "-----------------------------------------------"

# 4. FUNÇÃO DE APLICAÇÃO DE TRAVA (USANDO POLICING PARA DOWNLOAD)
aplicar_regra() {
    local taxa=$1
    local burst="100k"
    
    # Limpa regras
    tc qdisc del dev $INTERFACE root 2>/dev/null
    tc qdisc del dev $INTERFACE ingress 2>/dev/null
    ethtool -K $INTERFACE gro off gso off tso off 2>/dev/null

    # Regra de Saída
    if [ "$TIPO_IA" == "1" ] || [ "$TIPO_IA" == "3" ]; then
        tc qdisc add dev $INTERFACE root handle 1: htb default 10
        tc class add dev $INTERFACE parent 1: classid 1:10 htb rate ${taxa}mbit ceil ${taxa}mbit burst $burst
    fi

    # Regra de Entrada (A que você precisava travar)
    if [ "$TIPO_IA" == "2" ] || [ "$TIPO_IA" == "3" ]; then
        tc qdisc add dev $INTERFACE handle ffff: ingress
        tc filter add dev $INTERFACE parent ffff: protocol all u32 match u32 0 0 \
        police rate ${taxa}mbit burst $burst mtu 2k drop flowid :1
    fi
}

# 5. LOOP DE INTELIGÊNCIA
echo -e "${CIANO}IA Gravonyx Ativa. Monitorando tráfego...${NC}"
echo -e "${AMARELO}Pressione [CTRL+C] para encerrar.${NC}"

while true; do
    # Mede a velocidade atual (intervalo de 1 segundo)
    RX1=$(cat /sys/class/net/$INTERFACE/statistics/rx_bytes)
    TX1=$(cat /sys/class/net/$INTERFACE/statistics/tx_bytes)
    sleep 1
    RX2=$(cat /sys/class/net/$INTERFACE/statistics/rx_bytes)
    TX2=$(cat /sys/class/net/$INTERFACE/statistics/tx_bytes)

    # Cálculo de Mbps real
    SPEED_RX=$(( (RX2 - RX1) * 8 / 1048576 ))
    SPEED_TX=$(( (TX2 - TX1) * 8 / 1048576 ))
    
    # Pega o maior valor entre Up e Down para decidir o pico
    CURRENT_SPEED=$(( SPEED_RX > SPEED_TX ? SPEED_RX : SPEED_TX ))

    echo -ne "Consumo Atual: ${VERDE}${CURRENT_SPEED} Mbps${NC} / Limite: ${AMARELO}${LIMITE_BASE}${NC}    \r"

    # LÓGICA DE VARIAÇÃO
    if [ "$CURRENT_SPEED" -ge "$(( LIMITE_BASE - 15 ))" ]; then
        echo -e "\n${AMARELO}[PICO]${NC} Batendo no teto! Liberando Boost: ${VERDE}${BOOST} Mbps${NC}"
        aplicar_regra $BOOST
        sleep 8 # Tempo de boost curto

        # Decide aleatoriamente o resfriamento
        if [ $(( RANDOM % 2 )) -eq 0 ]; then
            NOVA_TAXA=$MINIMO
        else
            NOVA_TAXA=$MEDIO
        fi
        
        echo -e "${VERMELHO}[VARIAÇÃO]${NC} Reduzindo dinamicamente para: ${NOVA_TAXA} Mbps"
        aplicar_regra $NOVA_TAXA
        sleep 12 # Tempo de resfriamento antes de voltar ao normal
    else
        # Mantém a banda no limite padrão informado pelo usuário
        aplicar_regra $LIMITE_BASE
    fi
done
EOF

chmod +x limitar_banda_ia.sh
./limitar_banda_ia.sh
