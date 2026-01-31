cat << 'EOF' > limitar_banda.sh
#!/bin/bash

# Cores
VERDE='\033[0;32m'
CIANO='\033[0;36m'
AMARELO='\033[1;33m'
VERMELHO='\033[0;31m'
NC='\033[0m'

# 1. BANNER OFICIAL (O MENU ANTIGO)
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
echo -e "#  ${VERDE}FEITO POR: GRAVONYX.COM${NC}     |     ${AMARELO}VERSÃO: 5.0 FINAL${CIANO}       #"
echo -e "###############################################################${NC}"

# 2. IDENTIFICAÇÃO DE INTERFACE
INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
CONFIG_FILE="/usr/local/bin/limit-bandwidth.sh"

# 3. VERIFICAÇÃO DE STATUS
if [ -f "$CONFIG_FILE" ]; then
    echo -e "${VERDE}📊 STATUS: Existe uma regra ativa.${NC}"
    echo -e "1) Nova Regra | 2) Remover Limite | 3) Sair"
    read -p "Escolha: " OPT_EXISTENTE
    if [ "$OPT_EXISTENTE" == "2" ]; then
        tc qdisc del dev $INTERFACE root 2>/dev/null
        tc qdisc del dev $INTERFACE ingress 2>/dev/null
        ip link set dev ifb0 down 2>/dev/null
        ip link delete ifb0 2>/dev/null
        rm -f "$CONFIG_FILE"
        echo -e "${VERDE}Sistema restaurado ao padrão!${NC}"; exit 0
    elif [ "$OPT_EXISTENTE" == "3" ]; then exit 0; fi
fi

# 4. ENTRADA DE DADOS
echo -e "\n${CIANO}Configurações de Banda:${NC}"
echo -e "1) Saída (Upload) | 2) Entrada (Download) | 3) Ambos"
read -p "Opção: " TIPO
read -p "Valor (ex: 300): " VALOR
echo -e "Unidade: 1) Mbps | 2) Kbps"
read -p "Opção: " UNID

SUFIXO=$([ "$UNID" == "2" ] && echo "kbit" || echo "mbit")
LIMITE="${VALOR}${SUFIXO}"

# BURST DE PRECISÃO: 100kb é o ideal para 300mb não vazar na Contabo
BURST="100k"

# 5. GERANDO O SCRIPT DE CONFIGURAÇÃO (SEM ERROS DE VARIÁVEIS)
cat << FINAL_SCRIPT > "$CONFIG_FILE"
#!/bin/bash
IFACE=\$(ip route | grep default | awk '{print \$5}' | head -n1)

# Limpeza total antes de aplicar
tc qdisc del dev \$IFACE root 2>/dev/null
tc qdisc del dev \$IFACE ingress 2>/dev/null
ip link set dev ifb0 down 2>/dev/null
ip link delete ifb0 2>/dev/null

# Carrega módulo de interface virtual
modprobe ifb numifbs=1 2>/dev/null

# REGRA DE UPLOAD (SAÍDA)
if [ "$TIPO" == "1" ] || [ "$TIPO" == "3" ]; then
    tc qdisc add dev \$IFACE root handle 1: htb default 10
    tc class add dev \$IFACE parent 1: classid 1:10 htb rate $LIMITE ceil $LIMITE burst $BURST
fi

# REGRA DE DOWNLOAD (ENTRADA)
if [ "$TIPO" == "2" ] || [ "$TIPO" == "3" ]; then
    ip link add ifb0 type ifb 2>/dev/null
    ip link set dev ifb0 up
    tc qdisc add dev \$IFACE handle ffff: ingress
    tc filter add dev \$IFACE parent ffff: protocol ip u32 match u32 0 0 action mirred egress redirect dev ifb0
    tc qdisc add dev ifb0 root handle 1: htb default 10
    tc class add dev ifb0 parent 1: classid 1:10 htb rate $LIMITE ceil $LIMITE burst $BURST
fi
FINAL_SCRIPT

# 6. EXECUÇÃO E PERSISTÊNCIA
chmod +x "$CONFIG_FILE"
(crontab -l 2>/dev/null | grep -v "limit-bandwidth.sh" ; echo "@reboot $CONFIG_FILE") | crontab -
bash "$CONFIG_FILE"

echo -e "\n${VERDE}✅ SUCESSO! O menu voltou e o limite de $LIMITE foi travado.${NC}"
echo -e "${CIANO}Gravonyx.com - Teste agora no Speedtest.${NC}"
EOF

chmod +x limitar_banda.sh
./limitar_banda.sh
