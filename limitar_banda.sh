cat << 'EOF' > limitar_banda.sh
#!/bin/bash

# Cores
VERDE='\033[0;32m'
CIANO='\033[0;36m'
AMARELO='\033[1;33m'
VERMELHO='\033[0;31m'
NC='\033[0m'

# 1. PREPARAÇÃO SILENCIOSA
export DEBIAN_FRONTEND=noninteractive
apt-get update -y &>/dev/null
apt-get install iproute2 ethtool -y &>/dev/null

INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
CONFIG_FILE="/usr/local/bin/limit-bandwidth.sh"

clear
echo -e "${CIANO}###############################################################"
echo -e "#           LIMITADOR DE BANDA PRECISO - GRAVONYX             #"
echo -e "###############################################################${NC}"

# 2. MENU DE LIMITAÇÃO
echo -e "\n${CIANO}Selecione o tipo de limitação:${NC}"
echo -e "1) Saída | 2) Entrada | 3) Ambos"
read -p "Opção: " TIPO_LIMITE

read -p "Digite o valor numérico (ex: 300): " VALOR
echo -e "Unidade: 1) Mbps  2) Kbps"
read -p "Opção: " UNIDADE_OPC

if [ "$UNIDADE_OPC" == "2" ]; then
    SUFIXO="kbit"
    # Burst menor para Kbps
    BURST="15k"
else
    SUFIXO="mbit"
    # CÁLCULO DE BURST: Para velocidades altas, o burst deve ser maior (aprox. 10kb por megabit)
    # Isso evita que o limite "vaze" ou oscile demais
    BURST_VAL=$(( VALOR * 10 ))
    BURST="${BURST_VAL}k"
fi

LIMITE="${VALOR}${SUFIXO}"

# 3. GERAÇÃO DO SCRIPT COM TRAVA DE BURST
cat << SCHEDULER > "$CONFIG_FILE"
#!/bin/bash
IFACE=\$(ip route | grep default | awk '{print \$5}' | head -n1)
tc qdisc del dev \$IFACE root 2>/dev/null
tc qdisc del dev \$IFACE ingress 2>/dev/null
modprobe ifb 2>/dev/null
ip link delete ifb0 2>/dev/null

# SAÍDA (Upload) - Com burst calculado para precisão
if [ "$TIPO_LIMITE" == "1" ] || [ "$TIPO_LIMITE" == "3" ]; then
    tc qdisc add dev \$IFACE root handle 1: htb default 10
    tc class add dev \$IFACE parent 1: classid 1:10 htb rate $LIMITE ceil $LIMITE burst $BURST
fi

# ENTRADA (Download) - Redirecionando para interface virtual IFB
if [ "$TIPO_LIMITE" == "2" ] || [ "$TIPO_LIMITE" == "3" ]; then
    ip link add ifb0 type ifb && ip link set dev ifb0 up
    tc qdisc add dev \$IFACE handle ffff: ingress
    tc filter add dev \$IFACE parent ffff: protocol ip u32 match u32 0 0 action mirred egress redirect dev ifb0
    tc qdisc add dev ifb0 root handle 1: htb default 10
    tc class add dev ifb0 parent 1: classid 1:10 htb rate $LIMITE ceil $LIMITE burst $BURST
fi
SCHEDULER

chmod +x "$CONFIG_FILE"
(crontab -l 2>/dev/null | grep -v "limit-bandwidth.sh" ; echo "@reboot $CONFIG_FILE") | crontab -
bash "$CONFIG_FILE"

echo -e "\n${VERDE}✅ Limite de $LIMITE aplicado com TRAVA DE PRECISÃO (Burst: $BURST).${NC}"
echo -e "${CIANO}Gravonyx.com - Teste agora no Speedtest!${NC}"
EOF

bash limitar_banda.sh
