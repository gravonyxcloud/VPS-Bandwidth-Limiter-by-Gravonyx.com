cat << 'EOF' > limitar_banda.sh
#!/bin/bash

# Cores
VERDE='\033[0;32m'
CIANO='\033[0;36m'
AMARELO='\033[1;33m'
VERMELHO='\033[0;31m'
NC='\033[0m'

# Versão
VERSAO="v5.4 Brutal Precision"

# 1. VERIFICAÇÃO RÁPIDA
if ! command -v tc &> /dev/null || ! command -v ethtool &> /dev/null; then
    echo -e "${AMARELO}Instalando dependências essenciais...${NC}"
    apt-get update -y &>/dev/null
    apt-get install iproute2 ethtool -y &>/dev/null
fi

INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
SPEED_RAW=$(ethtool $INTERFACE 2>/dev/null | grep Speed | awk '{print $2}' | sed 's/Mb\/s//')
SPEED_REAL=${SPEED_RAW:-"1000"} 
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
echo -e "${AMARELO}Placa:${NC} $INTERFACE | ${AMARELO}Banda Nativa:${NC} ${VERDE}${SPEED_REAL}Mb/s${NC}"

# 3. STATUS E REMOÇÃO
if [ -f "$CONFIG_FILE" ]; then
    VALOR_SALVO=$(grep -oP 'rate \K[^ ]+' "$CONFIG_FILE" | head -1)
    echo -e "-----------------------------------------------"
    echo -e "${VERDE}📊 STATUS ATUAL DA LIMITAÇÃO:${NC}"
    echo -e "Limite Configurado: ${AMARELO}$VALOR_SALVO${NC}"
    echo "-----------------------------------------------"
    echo -e "${CIANO}O que deseja fazer?${NC}"
    echo -e "1) ${CIANO}Editar / Criar nova regra${NC}"
    echo -e "2) ${VERMELHO}Remover e Voltar ao padrão (${SPEED_REAL}Mb/s)${NC}"
    echo -e "3) Sair"
    read -p "Opção: " OPT_EXISTENTE

    if [ "$OPT_EXISTENTE" == "2" ]; then
        tc qdisc del dev $INTERFACE root 2>/dev/null
        tc qdisc del dev $INTERFACE ingress 2>/dev/null
        ethtool -K $INTERFACE gro on gso on tso on 2>/dev/null
        crontab -l 2>/dev/null | grep -v "limit-bandwidth.sh" | crontab -
        rm -f "$CONFIG_FILE"
        echo -e "${VERDE}Limites removidos com sucesso!${NC}"
        exit 0
    elif [ "$OPT_EXISTENTE" == "3" ]; then exit 0; fi
    clear
fi

# 4. MENU DE CONFIGURAÇÃO
echo ""
echo -e "${CIANO}Selecione o tráfego para limitar:${NC}"
echo -e "1) Saída (Upload)"
echo -e "2) Entrada (Download)"
echo -e "3) Ambos"
read -p "Opção: " TIPO_LIMITE

read -p "Digite o valor numérico (ex: 300): " VALOR
echo -e "Unidade: 1) ${VERDE}Mbps${NC}  2) ${VERDE}Kbps${NC}"
read -p "Opção: " UNIDADE_OPC

SUFIXO=$([ "$UNIDADE_OPC" == "2" ] && echo "kbit" || echo "mbit")
LIMITE="${VALOR}${SUFIXO}"

# Burst para o Police: Em download alto, o burst precisa ser controlado
BURST="128kb"

# 5. APLICAÇÃO E PERSISTÊNCIA
cat << SCHEDULER > "$CONFIG_FILE"
#!/bin/bash
IFACE=\$(ip route | grep default | awk '{print \$5}' | head -n1)

# Desativa Offloading para a placa não "enganar" o limitador
ethtool -K \$IFACE gro off gso off tso off 2>/dev/null

# Limpeza
tc qdisc del dev \$IFACE root 2>/dev/null
tc qdisc del dev \$IFACE ingress 2>/dev/null

# UPLOAD (Egress - HTB é estável aqui)
if [ "$TIPO_LIMITE" == "1" ] || [ "$TIPO_LIMITE" == "3" ]; then
    tc qdisc add dev \$IFACE root handle 1: htb default 10
    tc class add dev \$IFACE parent 1: classid 1:10 htb rate $LIMITE ceil $LIMITE burst 15k
fi

# DOWNLOAD (Ingress - USANDO POLICING BRUTO)
if [ "$TIPO_LIMITE" == "2" ] || [ "$TIPO_LIMITE" == "3" ]; then
    tc qdisc add dev \$IFACE handle ffff: ingress
    # A regra abaixo descarta o pacote no exato momento que ele excede a taxa
    tc filter add dev \$IFACE parent ffff: protocol all u32 match u32 0 0 \
    police rate $LIMITE burst $BURST mtu 2k drop flowid :1
fi
SCHEDULER

chmod +x "$CONFIG_FILE"
(crontab -l 2>/dev/null | grep -v "limit-bandwidth.sh" ; echo "@reboot $CONFIG_FILE") | crontab -
bash "$CONFIG_FILE"

echo -e "\n${VERDE}✅ Limite BRUTAL aplicado: $LIMITE${NC}"
echo -e "${CIANO}Hardware Offloading Desativado para precisão total.${NC}"
EOF

chmod +x limitar_banda.sh
./limitar_banda.sh
