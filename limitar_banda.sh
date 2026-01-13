cat << 'EOF' > limitar_banda.sh
#!/bin/bash

# Cores para o terminal
VERDE='\033[0;32m'
CIANO='\033[0;36m'
AMARELO='\033[1;33m'
VERMELHO='\033[0;31m'
NC='\033[0m' # Sem cor

# Limpa a tela antes de começar
clear

# =============================================================
#  SCRIPT DE LIMITAÇÃO DE BANDA (INGRESS/EGRESS)
#  CRÉDITOS: Gravonyx.com
# =============================================================

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
echo ""

# 1. Instalar dependências se não existirem
echo -e "${AMARELO}[1/6] Verificando dependências...${NC}"
apt update && apt install iproute2 -y &>/dev/null

# 2. Detectar interface de rede ativa
INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)

echo -e "${AMARELO}[2/6] Configurações de Rede:${NC}"
echo -e "Interface detectada: ${VERDE}$INTERFACE${NC}"
echo "-----------------------------------------------"

# 3. Menu de Opções
echo -e "${CIANO}O que você deseja limitar?${NC}"
echo -e "1) ${AMARELO}Apenas Saída${NC} (Egress/Upload)"
echo -e "2) ${AMARELO}Apenas Entrada${NC} (Ingress/Download)"
echo -e "3) ${AMARELO}Ambos${NC} (Entrada e Saída)"
echo -e "0) ${VERMELHO}REMOVER TODOS OS LIMITES${NC}"
echo "-----------------------------------------------"
read -p "Opção: " TIPO_LIMITE

# Lógica para remover limites
if [ "$TIPO_LIMITE" == "0" ]; then
    echo -e "${VERMELHO}Limpando todas as regras e persistência...${NC}"
    tc qdisc del dev $INTERFACE root 2>/dev/null
    tc qdisc del dev $INTERFACE ingress 2>/dev/null
    ip link delete ifb0 2>/dev/null
    crontab -l 2>/dev/null | grep -v "limit-bandwidth.sh" | crontab -
    echo -e "${VERDE}Limites removidos com sucesso!${NC}"
    exit 0
fi

# Coleta de valores
read -p "Digite o valor numérico do limite: " VALOR
echo -e "Escolha a unidade: 1) ${VERDE}Mbps${NC}  2) ${VERDE}Kbps${NC}  3) ${VERDE}Gbps${NC}"
read -p "Opção: " UNIDADE_OPC

case $UNIDADE_OPC in
    1) SUFIXO="mbit" ;;
    2) SUFIXO="kbit" ;;
    3) SUFIXO="gbit" ;;
    *) echo -e "${VERMELHO}Opção inválida.${NC}"; exit 1 ;;
esac

LIMITE="${VALOR}${SUFIXO}"

# 4. Criar o script de persistência
echo -e "${AMARELO}[4/6] Gerando arquivo de persistência...${NC}"
cat << SCHEDULER > /usr/local/bin/limit-bandwidth.sh
#!/bin/bash
# Creditos: Gravonyx.com
# Redescobre interface no boot
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
    modprobe ifb
    ip link add ifb0 type ifb
    ip link set dev ifb0 up
    tc qdisc add dev \$IFACE handle ffff: ingress
    tc filter add dev \$IFACE parent ffff: protocol ip u32 match u32 0 0 action mirred egress redirect dev ifb0
    tc qdisc add dev ifb0 root handle 1: htb default 10
    tc class add dev ifb0 parent 1: classid 1:10 htb rate $LIMITE ceil $LIMITE
fi
SCHEDULER

chmod +x /usr/local/bin/limit-bandwidth.sh

# 5. Configurar Crontab
echo -e "${AMARELO}[5/6] Instalando no Crontab para boot automático...${NC}"
(crontab -l 2>/dev/null | grep -v "/usr/local/bin/limit-bandwidth.sh" ; echo "@reboot /usr/local/bin/limit-bandwidth.sh") | crontab -

# 6. Aplicação imediata
echo -e "${AMARELO}[6/6] Ativando regras agora...${NC}"
bash /usr/local/bin/limit-bandwidth.sh

echo ""
echo -e "${VERDE}-----------------------------------------------${NC}"
echo -e "${CIANO}Configuração de ${AMARELO}$LIMITE${CIANO} aplicada por ${VERDE}Gravonyx.com!${NC}"
echo -e "Status: ${VERDE}ATIVO E PERSISTENTE${NC}"
echo -e "${VERDE}-----------------------------------------------${NC}"
EOF

chmod +x limitar_banda.sh
./limitar_banda.sh
