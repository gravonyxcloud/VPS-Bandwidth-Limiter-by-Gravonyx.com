cat << 'EOF' > limitar_banda.sh
#!/bin/bash

# Cores
VERDE='\033[0;32m'
CIANO='\033[0;36m'
AMARELO='\033[1;33m'
VERMELHO='\033[0;31m'
NC='\033[0m'

# Versão
VERSAO="v5.3 X-Trava Precision"

# 1. VERIFICAÇÃO DE DEPENDÊNCIAS
if ! command -v tc &> /dev/null || ! command -v ethtool &> /dev/null; then
    echo -e "${AMARELO}Instalando ferramentas de rede essenciais...${NC}"
    apt-get update -y &>/dev/null
    apt-get install iproute2 ethtool -y &>/dev/null
fi

INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
CONFIG_FILE="/usr/local/bin/limit-bandwidth.sh"

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
echo -e "#  ${VERDE}FEITO POR: GRAVONYX.COM${NC}     |     ${AMARELO}VERSÃO: $VERSAO${CIANO}       #"
echo -e "###############################################################${NC}"

# 3. STATUS E REMOÇÃO
if [ -f "$CONFIG_FILE" ]; then
    VALOR_SALVO=$(grep -oP 'rate \K[^ ]+' "$CONFIG_FILE" | head -1)
    echo -e "-----------------------------------------------"
    echo -e "${VERDE}📊 STATUS ATUAL: $VALOR_SALVO${NC}"
    echo "-----------------------------------------------"
    echo -e "1) Nova Regra | 2) Remover e Resetar Hardware | 3) Sair"
    read -p "Opção: " OPT_EXISTENTE

    if [ "$OPT_EXISTENTE" == "2" ]; then
        tc qdisc del dev $INTERFACE root 2>/dev/null
        tc qdisc del dev $INTERFACE ingress 2>/dev/null
        ip link set dev ifb0 down 2>/dev/null
        ip link delete ifb0 2>/dev/null
        # Reativa as otimizações de hardware
        ethtool -K $INTERFACE gro on lro on tso on gso on 2>/dev/null
        crontab -l 2>/dev/null | grep -v "limit-bandwidth.sh" | crontab -
        rm -f "$CONFIG_FILE"
        echo -e "${VERDE}Limites removidos e placa resetada para o padrão!${NC}"
        exit 0
    elif [ "$OPT_EXISTENTE" == "3" ]; then exit 0; fi
    clear
fi

# 4. MENU DE CONFIGURAÇÃO
echo ""
echo -e "${CIANO}Selecione o tráfego para limitar:${NC}"
echo -e "1) Saída (Upload)"
echo -e "2) Entrada (Download)"
echo -e "3) Ambos (Entrada e Saída)"
read -p "Opção: " TIPO_LIMITE

read -p "Digite o valor numérico (ex: 300): " VALOR
echo -e "Unidade: 1) ${VERDE}Mbps${NC}  2) ${VERDE}Kbps${NC}"
read -p "Opção: " UNIDADE_OPC

SUFIXO=$([ "$UNIDADE_OPC" == "2" ] && echo "kbit" || echo "mbit")
LIMITE="${VALOR}${SUFIXO}"

# Burst de 32k é o "balde" ideal para não deixar a velocidade vazar
BURST="32k"

# 5. APLICAÇÃO E PERSISTÊNCIA
cat << SCHEDULER > "$CONFIG_FILE"
#!/bin/bash
IFACE=\$(ip route | grep default | awk '{print \$5}' | head -n1)

# DESATIVA OFFLOADING (Garante que o download seja capturado pelo TC)
ethtool -K \$IFACE gro off lro off tso off gso off 2>/dev/null

# Limpeza profunda
tc qdisc del dev \$IFACE root 2>/dev/null
tc qdisc del dev \$IFACE ingress 2>/dev/null
ip link set dev ifb0 down 2>/dev/null
ip link delete ifb0 2>/dev/null
modprobe ifb numifbs=1 2>/dev/null

# UPLOAD
if [ "$TIPO_LIMITE" == "1" ] || [ "$TIPO_LIMITE" == "3" ]; then
    tc qdisc add dev \$IFACE root handle 1: htb default 10
    tc class add dev \$IFACE parent 1: classid 1:10 htb rate $LIMITE ceil $LIMITE burst $BURST
fi

# DOWNLOAD (Trava Real via Redirecionamento IFB)
if [ "$TIPO_LIMITE" == "2" ] || [ "$TIPO_LIMITE" == "3" ]; then
    ip link add name ifb0 type ifb 2>/dev/null
    ip link set dev ifb0 up
    tc qdisc add dev \$IFACE handle ffff: ingress
    tc filter add dev \$IFACE parent ffff: protocol ip u32 match u32 0 0 action mirred egress redirect dev ifb0
    tc qdisc add dev ifb0 root handle 1: htb default 10
    tc class add dev ifb0 parent 1: classid 1:10 htb rate $LIMITE ceil $LIMITE burst $BURST
fi
SCHEDULER

chmod +x "$CONFIG_FILE"
(crontab -l 2>/dev/null | grep -v "limit-bandwidth.sh" ; echo "@reboot $CONFIG_FILE") | crontab -
bash "$CONFIG_FILE"

echo -e "\n${VERDE}✅ Limite de $LIMITE aplicado com TRAVA DE HARDWARE!${NC}"
echo -e "${CIANO}Gravonyx.com - Qualidade Garantida.${NC}"
EOF

chmod +x limitar_banda.sh
./limitar_banda.sh
