cat << 'EOF' > limitar_banda.sh
#!/bin/bash

# Cores
VERDE='\033[0;32m'
CIANO='\033[0;36m'
AMARELO='\033[1;33m'
VERMELHO='\033[0;31m'
NC='\033[0m'

# Versão
VERSAO="v3.2 Final"

# 1. PREPARAÇÃO SILENCIOSA
apt update &>/dev/null && apt install iproute2 -y &>/dev/null
INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
CONFIG_FILE="/usr/local/bin/limit-bandwidth.sh"

# 2. LIMPA TUDO E MOSTRA O TOPO PROFISSIONAL
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
echo -e "${AMARELO}Interface ativa: ${VERDE}$INTERFACE${NC}"

# 3. DETECÇÃO E EXIBIÇÃO DE STATUS
if [ -f "$CONFIG_FILE" ]; then
    VALOR_SALVO=$(grep -oP 'rate \K[^ ]+' "$CONFIG_FILE" | head -1)
    TEM_SAIDA=$(grep -c "root handle 1: htb" "$CONFIG_FILE")
    TEM_ENTRADA=$(grep -c "ifb0 root handle 1: htb" "$CONFIG_FILE")

    if [ "$TEM_SAIDA" -ge "1" ] && [ "$TEM_ENTRADA" -ge "1" ]; then
        TIPO_STR="AMBOS (Download e Upload)"
    elif [ "$TEM_SAIDA" -ge "1" ]; then
        TIPO_STR="APENAS SAÍDA (Upload)"
    else
        TIPO_STR="APENAS ENTRADA (Download)"
    fi

    echo -e "-----------------------------------------------"
    echo -e "${VERDE}📊 STATUS DE LIMITAÇÃO ATIVO:${NC}"
    echo -e "Limite: ${AMARELO}$VALOR_SALVO${NC} | Tipo: ${AMARELO}$TIPO_STR${NC}"
    echo "-----------------------------------------------"
    echo -e "${CIANO}O que deseja fazer?${NC}"
    echo -e "1) ${CIANO}Editar / Alterar limite${NC}"
    echo -e "2) ${VERMELHO}Remover e Voltar ao padrão ${NC}"
    echo -e "3) Sair"
    read -p "Opção: " OPT_EXISTENTE

    if [ "$OPT_EXISTENTE" == "2" ]; then
        tc qdisc del dev $INTERFACE root 2>/dev/null
        tc qdisc del dev $INTERFACE ingress 2>/dev/null
        ip link delete ifb0 2>/dev/null
        crontab -l 2>/dev/null | grep -v "limit-bandwidth.sh" | crontab -
        rm -f "$CONFIG_FILE"
        echo -e "${VERDE}Limites removidos com sucesso!${NC}"
        exit 0
    elif [ "$OPT_EXISTENTE" == "3" ]; then
        exit 0
    fi
    # Se for editar, limpa e mostra o menu de criação
    clear
    echo -e "${CIANO}###############################################################"
    echo -e "#                 ${VERDE}EDITAR LIMITE GRAVONYX${CIANO}                    #"
    echo -e "###############################################################${NC}"
fi

# 4. MENU DE CONFIGURAÇÃO (Caso não tenha ou escolha editar)
echo ""
echo -e "${CIANO}Selecione o tipo de limitação:${NC}"
echo -e "1) Saída (Upload)"
echo -e "2) Entrada (Download)"
echo -e "3) Ambos (Entrada e Saída)"
read -p "Opção: " TIPO_LIMITE

read -p "Digite o valor numérico (ex: 450): " VALOR
echo -e "Unidade: 1) ${VERDE}Mbps${NC}  2) ${VERDE}Kbps${NC}  3) ${VERDE}Gbps${NC}"
read -p "Opção: " UNIDADE_OPC

case $UNIDADE_OPC in
    1) SUFIXO="mbit" ;;
    2) SUFIXO="kbit" ;;
    3) SUFIXO="gbit" ;;
    *) echo -e "${VERMELHO}Opção inválida.${NC}"; exit 1 ;;
esac
LIMITE="${VALOR}${SUFIXO}"

# 5. APLICAÇÃO E PERSISTÊNCIA
cat << SCHEDULER > "$CONFIG_FILE"
#!/bin/bash
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

chmod +x "$CONFIG_FILE"
(crontab -l 2>/dev/null | grep -v "limit-bandwidth.sh" ; echo "@reboot $CONFIG_FILE") | crontab -
bash "$CONFIG_FILE"

echo -e "\n${VERDE}✅ Limite de $LIMITE configurado com sucesso!${NC}"
echo -e "${CIANO}Gravonyx.com - Qualidade Garantida.${NC}"
EOF

chmod +x limitar_banda.sh
./limitar_banda.sh
