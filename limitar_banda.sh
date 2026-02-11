cat << 'EOF' > limitar_dinamico.sh
#!/bin/bash

# Cores
VERDE='\033[0;32m'
CIANO='\033[0;36m'
AMARELO='\033[1;33m'
VERMELHO='\033[0;31m'
NC='\033[0m'

# CONFIGURAÇÕES BASE
INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
LIMITE_NATIVO=600  # Mbps
BOOST=610          # Mbps
MINIMO=300         # Mbps
MEDIO=450          # Mbps

# 1. BANNER
clear
echo -e "${CIANO}###############################################################"
echo -e "#                                                             #"
echo -e "#        GRAVONYX DYNAMIC ADAPTIVE (MODO INTELIGENTE)         #"
echo -e "#                                                             #"
echo -e "###############################################################${NC}"
echo -e "${VERDE}Monitorando interface:${NC} $INTERFACE"

# Função para aplicar o limite instantâneo sem derrubar a rede
aplicar_tc() {
    local rate=$1
    tc qdisc del dev $INTERFACE root 2>/dev/null
    tc qdisc del dev $INTERFACE ingress 2>/dev/null
    
    # Aplica na Saída (Upload)
    tc qdisc add dev $INTERFACE root handle 1: htb default 10
    tc class add dev $INTERFACE parent 1: classid 1:10 htb rate ${rate}mbit ceil ${rate}mbit burst 100k
    
    # Aplica na Entrada (Download) via Policing Bruto
    tc qdisc add dev $INTERFACE handle ffff: ingress
    tc filter add dev $INTERFACE parent ffff: protocol all u32 match u32 0 0 \
    police rate ${rate}mbit burst 100kb mtu 2k drop flowid :1
}

# 2. LOOP DE MONITORAMENTO REAL-TIME
echo -e "${AMARELO}Iniciando IA de tráfego... Pressione [CTRL+C] para parar.${NC}"

while true; do
    # Captura a velocidade atual de RX (Download)
    RX1=$(cat /sys/class/net/$INTERFACE/statistics/rx_bytes)
    sleep 2
    RX2=$(cat /sys/class/net/$INTERFACE/statistics/rx_bytes)
    
    # Cálculo: (Bytes2 - Bytes1) * 8 bits / 2 segundos / 1024 / 1024 = Mbps
    MBPS=$(( (RX2 - RX1) * 8 / 2 / 1048576 ))
    
    echo -e "Consumo Atual: ${VERDE}${MBPS} Mbps${NC}"

    if [ "$MBPS" -ge "$((LIMITE_NATIVO - 20))" ]; then
        echo -e "${AMARELO}⚠️ PICO DETECTADO! Liberando Boost para ${BOOST} Mbps...${NC}"
        aplicar_tc $BOOST
        sleep 10 # Mantém o fôlego por 10 segundos
        
        VAR_ALEATORIA=$(( ( RANDOM % 2 )  + 1 ))
        if [ "$VAR_ALEATORIA" == "1" ]; then
            echo -e "${VERMELHO}📉 Resfriando para ${MINIMO} Mbps...${NC}"
            aplicar_tc $MINIMO
        else
            echo -e "${VERMELHO}📉 Ajustando para ${MEDIO} Mbps...${NC}"
            aplicar_tc $MEDIO
        fi
        sleep 15 # Tempo de resfriamento
    else
        # Se o tráfego está calmo, mantém no limite padrão de 600 ou varia levemente
        aplicar_tc $LIMITE_NATIVO
    fi
    
    sleep 1
done
EOF

chmod +x limitar_dinamico.sh
./limitar_dinamico.sh
