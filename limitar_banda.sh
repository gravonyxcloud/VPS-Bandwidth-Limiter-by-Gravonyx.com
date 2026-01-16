cat << 'EOF' > limitar_banda.sh
#!/bin/bash

# Cores
VERDE='\033[0;32m'
CIANO='\033[0;36m'
AMARELO='\033[1;33m'
VERMELHO='\033[0;31m'
NC='\033[0m'

# Versão
VERSAO="v4.1 Ultra Pro"

# 1. PREPARAÇÃO SILENCIOSA E DETECÇÃO REAL
apt update &>/dev/null && apt install iproute2 ethtool -y &>/dev/null
INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
CONFIG_FILE="/usr/local/bin/limit-bandwidth.sh"

# Detecta a velocidade real da placa para evitar texto fixo
SPEED_RAW=$(ethtool $INTERFACE 2>/dev/null | grep Speed | awk '{print $2}' | sed 's/Mb\/s//')
SPEED_REAL=${SPEED_RAW:-"1000"} # Default 1000mb se falhar a detecção

# 2. LIMPA TUDO E MOSTRA O BANNER
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
echo -e "${AMARELO}Placa:${NC} $INTERFACE | ${AMARELO}Banda Nativa:${NC} ${VERDE}${SPEED_REAL}Mb/s${NC}"

# 3. VERIFICAÇÃO DE STATUS
if [ -f "$CONFIG_FILE" ]; then
    VALOR_SALVO=$(grep -oP 'rate \K[^ ]+' "$CONFIG_FILE" | head -1)
    echo -e "-----------------------------------------------"
    echo -e "${VERDE}📊 STATUS ATUAL:${NC}"
    echo -e "Limite Ativo: ${AMARELO}$VALOR_SALVO${NC}"
    echo "-----------------------------------------------"
    echo -e "${CIANO}O que deseja fazer?${NC}"
    echo -e "1) ${CIANO}Editar Limite${NC}"
    echo -e "2) ${VERMELHO}Remover e Voltar ao padrão (${SPEED_REAL}Mb/s)${NC}"
    echo -e "3) Sair"
    read -p "Opção: " OPT_EXISTENTE

    if [ "$OPT_EXISTENTE" == "2" ]; then
        tc qdisc del dev $INTERFACE root 2>/dev/null
        tc qdisc del dev $INTERFACE ingress 2>/dev/null
        ip link delete ifb0 2>/dev/null
        crontab -l 2>/dev/null | grep -v "limit-bandwidth.sh" | crontab -
        rm -f "$CONFIG_FILE"
        echo -e "${VERDE}Limites removidos! Velocidade restaurada.${NC}"
        exit 0
    elif [ "$OPT_EXISTENTE" == "3" ]; then exit 0; fi
    clear
fi

# 4. OTIMIZAÇÃO DE REDE (BBR + DNS)
echo -e "\n${AMARELO}[+] OTIMIZAÇÃO PROFISSIONAL DE REDE${NC}"
read -p "Deseja aplicar Otimização de Kernel (BBR) e DNS Pro? (s/n): " OP_OTIMIZAR

if [[ "$OP_OTIMIZAR" =~ ^[S,s]$ ]]; then
    echo -e "${VERDE}Aplicando TCP BBR e Buffers Avançados...${NC}"
    cat << 'SYS' > /etc/sysctl.d/99-gravonyx.conf
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 65536 16777216
SYS
    sysctl -p /etc/sysctl.d/99-gravonyx.conf &>/dev/null
    echo -e "nameserver 1.1.1.1\nnameserver 8.8.8.8" > /etc/resolv.conf
    echo -e "${VERDE}[OK] Rede Otimizada!${NC}"
fi

# 5. MENU DE LIMITAÇÃO
echo -e "\n${CIANO}Configurar Controle de Banda:${NC}"
echo -e "1) Saída (Upload) | 2) Entrada (Download) | 3) Ambos"
read -p "Escolha: " TIPO_LIMITE
read -p "Valor numérico (ex: 450): " VALOR
echo -e "Unidade: 1) ${VERDE}Mbps${NC}  2) ${VERDE}Kbps${NC}"
read -p "Opção: " UNIDADE_OPC
SUFIXO=$([ "$UNIDADE_OPC" == "2" ] && echo "kbit" || echo "mbit")
LIMITE="${VALOR}${SUFIXO}"

# 6. PERSISTÊNCIA
cat << SCHEDULER > "$CONFIG_FILE"
#!/bin/bash
# Gravonyx Pro
IFACE=\$(ip route | grep default | awk '{print \$5}' | head -n1)
tc qdisc del dev \$IFACE root 2>/dev/null
tc qdisc del dev \$IFACE ingress 2>/dev/null
modprobe ifb 2>/dev/null
ip link delete ifb0 2>/dev/null
if [ "$TIPO_LIMITE" == "1" ] || [ "$TIPO_LIMITE" == "3" ]; then
    tc qdisc add dev \$IFACE root handle 1: htb default 10
    tc class add dev \$IFACE parent 1: classid 1:10 htb rate $LIMITE ceil $LIMITE
fi
if [ "$TIPO_LIMITE" == "2" ] || [ "$TIPO_LIMITE" == "3" ]; then
    ip link add ifb0 type ifb && ip link set dev ifb0 up
    tc qdisc add dev \$IFACE handle ffff: ingress
    tc filter add dev \$IFACE parent ffff: protocol ip u32 match u32 0 0 action mirred egress redirect dev ifb0
    tc qdisc add dev ifb0 root handle 1: htb default 10
    tc class add dev ifb0 parent 1: classid 1:10 htb rate $LIMITE ceil $LIMITE
fi
SCHEDULER

chmod +x "$CONFIG_FILE"
(crontab -l 2>/dev/null | grep -v "limit-bandwidth.sh" ; echo "@reboot $CONFIG_FILE") | crontab -
bash "$CONFIG_FILE"

echo -e "\n${VERDE}✅ VPS OTIMIZADA E LIMITADA EM $LIMITE!${NC}"
echo -e "${CIANO}Gravonyx.com - Performance de Elite.${NC}"
EOF

chmod +x limitar_banda.sh
./limitar_banda.sh
