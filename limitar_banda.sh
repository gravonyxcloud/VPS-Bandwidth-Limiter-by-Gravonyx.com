cat << 'EOF' > limitar_banda.sh
#!/bin/bash

# Cores
VERDE='\033[0;32m'
CIANO='\033[0;36m'
AMARELO='\033[1;33m'
VERMELHO='\033[0;31m'
NC='\033[0m'

# 1. IDENTIFICAÇÃO
INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
CONFIG_FILE="/usr/local/bin/limit-bandwidth.sh"

# 2. BANNER PRINCIPAL
clear
echo -e "${CIANO}###############################################################"
echo -e "#                                                             #"
echo -e "#           TRAVA DE PRECISÃO GRAVONYX (v4.9)                 #"
echo -e "#                                                             #"
echo -e "###############################################################${NC}"

# 3. VERIFICAÇÃO DE STATUS
if [ -f "$CONFIG_FILE" ]; then
    echo -e "${VERDE}📊 Limite atual detectado.${NC}"
    echo -e "1) Criar Novo Limite | 2) Remover Tudo | 3) Sair"
    read -p "Opção: " OPT
    if [ "$OPT" == "2" ]; then
        tc qdisc del dev $INTERFACE root 2>/dev/null
        tc qdisc del dev $INTERFACE ingress 2>/dev/null
        ip link delete ifb0 2>/dev/null
        rm -f "$CONFIG_FILE"
        echo -e "${VERDE}Limites removidos!${NC}"; exit 0
    elif [ "$OPT" == "3" ]; then exit 0; fi
fi

# 4. INPUTS
echo -e "\n${CIANO}Configurar Limite:${NC}"
echo -e "1) Saída (Upload) | 2) Entrada (Download) | 3) Ambos"
read -p "Escolha: " TIPO
read -p "Valor (ex: 300): " VALOR
echo -e "Unidade: 1) Mbps | 2) Kbps"
read -p "Opção: " UNID

SUFIXO=$([ "$UNID" == "2" ] && echo "kbit" || echo "mbit")
LIMITE="${VALOR}${SUFIXO}"

# Cálculo de Burst Rígido (Evita o vazamento para 400-500mb)
BURST="32k" # Burst pequeno força o limite a ser respeitado imediatamente

# 5. CRIAÇÃO DO SCRIPT DE EXECUÇÃO
cat << 'INNER' > "$CONFIG_FILE"
#!/bin/bash
IFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
tc qdisc del dev $IFACE root 2>/dev/null
tc qdisc del dev $IFACE ingress 2>/dev/null
modprobe ifb 2>/dev/null
ip link delete ifb0 2>/dev/null

# Aplicando Limite de Saída
if [ "TIPO_VAR" == "1" ] || [ "TIPO_VAR" == "3" ]; then
    tc qdisc add dev $IFACE root handle 1: htb default 10
    tc class add dev $IFACE parent 1: classid 1:10 htb rate LIMITE_VAR ceil LIMITE_VAR burst BURST_VAR
fi

# Aplicando Limite de Entrada (Download) com Interface Virtual
if [ "TIPO_VAR" == "2" ] || [ "TIPO_VAR" == "3" ]; then
    ip link add ifb0 type ifb && ip link set dev ifb0 up
    tc qdisc add dev $IFACE handle ffff: ingress
    tc filter add dev $IFACE parent ffff: protocol ip u32 match u32 0 0 action mirred egress redirect dev ifb0
    tc qdisc add dev ifb0 root handle 1: htb default 10
    tc class add dev ifb0 parent 1: classid 1:10 htb rate LIMITE_VAR ceil LIMITE_VAR burst BURST_VAR
fi
INNER

# Ajusta as variáveis dentro do script gerado
sed -i "s/TIPO_VAR/$TIPO/g" "$CONFIG_FILE"
sed -i "s/LIMITE_VAR/$LIMITE/g" "$CONFIG_FILE"
sed -i "s/BURST_VAR/$BURST/g" "$CONFIG_FILE"

chmod +x "$CONFIG_FILE"
bash "$CONFIG_FILE"

echo -e "\n${VERDE}✅ SUCESSO! Limite de $LIMITE aplicado.${NC}"
echo -e "${AMARELO}O download agora deve respeitar os $VALOR Mbps.${NC}"
EOF

chmod +x limitar_banda.sh
./limitar_banda.sh
