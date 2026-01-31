cat << 'EOF' > limitar_banda.sh
#!/bin/bash

# Cores
VERDE='\033[0;32m'
CIANO='\033[0;36m'
AMARELO='\033[1;33m'
NC='\033[0m'

# 1. VERIFICAÇÃO RÁPIDA
INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
CONFIG_FILE="/usr/local/bin/limit-bandwidth.sh"

clear
echo -e "${CIANO}###############################################################"
echo -e "#           TRAVA DE PRECISÃO REAL - GRAVONYX.COM             #"
echo -e "###############################################################${NC}"

# 2. INPUT
read -p "Opção de Tráfego (1-Saída, 2-Entrada, 3-Ambos): " TIPO_LIMITE
read -p "Valor (ex: 300): " VALOR
read -p "Unidade (1-Mbps, 2-Kbps): " UNIDADE_OPC

if [ "$UNIDADE_OPC" == "2" ]; then
    SUFIXO="kbit"; BURST="15k"
else
    SUFIXO="mbit"
    # BURST REDUZIDO: Para 300Mb, usamos um burst menor (5k por mega) para ser mais rígido
    BURST_VAL=$(( VALOR * 5 ))
    BURST="${BURST_VAL}k"
fi
LIMITE="${VALOR}${SUFIXO}"

# 3. GERAÇÃO DO SCRIPT COM FILTRO POLICING (O segredo para o Download)
cat << SCHEDULER > "$CONFIG_FILE"
#!/bin/bash
IFACE=\$(ip route | grep default | awk '{print \$5}' | head -n1)

# Limpa regras anteriores
tc qdisc del dev \$IFACE root 2>/dev/null
tc qdisc del dev \$IFACE ingress 2>/dev/null
ip link delete ifb0 2>/dev/null

# UPLOAD (Egress)
if [ "$TIPO_LIMITE" == "1" ] || [ "$TIPO_LIMITE" == "3" ]; then
    tc qdisc add dev \$IFACE root handle 1: htb default 10
    tc class add dev \$IFACE parent 1: classid 1:10 htb rate $LIMITE ceil $LIMITE burst $BURST cburst $BURST
fi

# DOWNLOAD (Ingress) - USANDO POLICING RÍGIDO
if [ "$TIPO_LIMITE" == "2" ] || [ "$TIPO_LIMITE" == "3" ]; then
    tc qdisc add dev \$IFACE handle ffff: ingress
    # O "police" descarta pacotes acima da taxa instantaneamente
    tc filter add dev \$IFACE parent ffff: protocol ip u32 match u32 0 0 \
    police rate $LIMITE burst $BURST mtu 2k drop flowid :1
fi
SCHEDULER

chmod +x "$CONFIG_FILE"
bash "$CONFIG_FILE"

echo -e "\n${VERDE}✅ TRAVA APLICADA! O Download deve ficar cravado em $LIMITE.${NC}"
EOF

bash limitar_banda.sh
