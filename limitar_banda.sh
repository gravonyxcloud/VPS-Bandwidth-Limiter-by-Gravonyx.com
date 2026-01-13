cat << 'EOF' > limitar_banda.sh
#!/bin/bash

# Cores
VERDE='\033[0;32m'
CIANO='\033[0;36m'
AMARELO='\033[1;33m'
VERMELHO='\033[0;31m'
NC='\033[0m'

# 1. TRABALHO SILENCIOSO (Verifica tudo antes de mostrar o menu)
apt update &>/dev/null && apt install iproute2 -y &>/dev/null
INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)

# 2. LIMPA A TELA PARA O ESTADO FINAL
clear

# 3. BANNER E MENU NO TOPO (A primeira coisa que o usuário vê)
echo -e "${CIANO}###############################################################"
echo -e "#                                                             #"
echo -e "#    ____                                            .com     #"
echo -e "#   / ___|_ __ __ ___   _____  _ __  _   ___  __              #"
echo -e "#  | |  _| '__/ _\` \ \ / / _ \| '_ \| | | \ \/ /              #"
echo -e "#  | |_| | | | (_| |\ V / (_) | | | | |_| |>  <               #"
echo -e "#   \____|_|  \__,_| \_/ \___/|_| |_|\__, /_/\_\              #"
echo -e "#                                    |___/                    #"
echo -e "#                                                             #"
echo -e "#                 ${VERDE}FEITO POR: GRAVONYX.COM${CIANO}                     #"
echo -e "###############################################################${NC}"
echo -e "${AMARELO}Interface ativa: ${VERDE}$INTERFACE${NC}"
echo "-----------------------------------------------"
echo -e "${CIANO}O que você deseja limitar?${NC}"
echo -e "1) ${AMARELO}Apenas Saída${NC} (Egress/Upload)"
echo -e "2) ${AMARELO}Apenas Entrada${NC} (Ingress/Download)"
echo -e "3) ${AMARELO}Ambos${NC} (Entrada e Saída)"
echo -e "0) ${VERMELHO}REMOVER TODOS OS LIMITES${NC}"
echo "-----------------------------------------------"
read -p "Opção: " TIPO_LIMITE

# --- Lógica de Remoção ---
if [ "$TIPO_LIMITE" == "0" ]; then
    tc qdisc del dev $INTERFACE root 2>/dev/null
    tc qdisc del dev $INTERFACE ingress 2>/dev/null
    ip link delete ifb0 2>/dev/null
    crontab -l 2>/dev/null | grep -v "limit-bandwidth.sh" | crontab -
    echo -e "${VERDE}Limites removidos com sucesso!${NC}"
    exit 0
fi

# --- Coleta de Dados ---
read -p "Valor numérico: " VALOR
echo -e "Unidade: 1) ${VERDE}Mbps${NC}  2) ${VERDE}Kbps${NC}  3) ${VERDE}Gbps${NC}"
read -p "Opção: " UNIDADE_OPC

case $UNIDADE_OPC in
    1) SUFIXO="mbit" ;;
    2) SUFIXO="kbit" ;;
    3) SUFIXO="gbit" ;;
    *) echo -e "${VERMELHO}Opção inválida.${NC}"; exit 1 ;;
esac
LIMITE="${VALOR}${SUFIXO}"

# --- Persistência ---
cat << SCHEDULER > /usr/local/bin/limit-bandwidth.sh
#!/bin/bash
# Creditos: Gravonyx.com
IFACE=\$(ip route | grep default | awk '{print \$5}' | head -n1)
tc qdisc del dev \$IFACE root 2>/dev/null
tc qdisc del dev \$IFACE ingress 2>/dev/null
modprobe ifb 2>/dev/null
ip link set dev ifb0 down 2>/dev/null
ip link delete ifb0 2>/dev/null
if [ "$TIPO_LIMITE" == "1" ] || [ "$TIPO_LIMITE" == "3" ]; then
    tc qdisc add dev \$IFACE root handle 1: htb default 10
    tc class add dev \$IFACE parent 1: classid 1:10 htb rate $LIMITE ceil $LIMITE
fi
if [ "$TIPO_LIMITE" == "2" ] || [ "$TIPO_LIMITE" == "3" ]; then
    modprobe ifb && ip link add ifb0 type ifb && ip link set dev ifb0 up
    tc qdisc add dev \$IFACE handle ffff: ingress
    tc filter add dev \$IFACE parent ffff: protocol ip u32 match u32 0 0 action mirred egress redirect dev ifb0
    tc qdisc add dev ifb0 root handle 1: htb default 10
    tc class add dev ifb0 parent 1: classid 1:10 htb rate $LIMITE ceil $LIMITE
fi
SCHEDULER

chmod +x /usr/local/bin/limit-bandwidth.sh
(crontab -l 2>/dev/null | grep -v "limit-bandwidth.sh" ; echo "@reboot /usr/local/bin/limit-bandwidth.sh") | crontab -
bash /usr/local/bin/limit-bandwidth.sh

echo -e "\n${VERDE}Configuração de $LIMITE aplicada por Gravonyx.com!${NC}"
EOF

chmod +x limitar_banda.sh
./limitar_banda.sh
