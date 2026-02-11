cat << 'EOF' > instalar_gravonyx.sh
#!/bin/bash

# Cores
VERDE='\033[0;32m'
CIANO='\033[0;36m'
AMARELO='\033[1;33m'
VERMELHO='\033[0;31m'
NC='\033[0m'

# 1. LIMPEZA TOTAL DE INSTALAÇÕES ANTIGAS
systemctl stop gravonyx-ia 2>/dev/null
systemctl disable gravonyx-ia 2>/dev/null
rm -f /etc/systemd/system/gravonyx-ia.service
rm -f /usr/local/bin/gravonyx_worker.sh
rm -f /usr/local/bin/painel.sh

# 2. INSTALAÇÃO DE DEPENDÊNCIAS
echo -e "${AMARELO}Instalando ferramentas de rede...${NC}"
apt-get update -y &>/dev/null
apt-get install iproute2 ethtool -y &>/dev/null

INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)

# 3. BANNER
clear
echo -e "${CIANO}###############################################################"
echo -e "#            INSTALADOR GRAVONYX IA - CORRIGIDO               #"
echo -e "###############################################################${NC}"
read -p "Qual o limite real da sua VPS em Mbps? (ex: 600): " LIMITE_BASE
read -p "Tipo de Limite (1=Up, 2=Down, 3=Ambos): " TIPO_IA

# 4. SALVAR CONFIGURAÇÃO
cat << CONF > /etc/gravonyx_ia.conf
INTERFACE=$INTERFACE
LIMITE_BASE=$LIMITE_BASE
TIPO_IA=$TIPO_IA
BOOST=$(( LIMITE_BASE + 10 ))
MINIMO=$(( LIMITE_BASE / 2 ))
MEDIO=$(( LIMITE_BASE * 3 / 4 ))
CONF

# 5. CRIAR O SCRIPT QUE TRABALHA NO FUNDO (WORKER)
cat << 'WORKER' > /usr/local/bin/gravonyx_worker.sh
#!/bin/bash
source /etc/gravonyx_ia.conf

# Desativa offloading para precisão total
ethtool -K $INTERFACE gro off gso off tso off 2>/dev/null

aplicar_regra() {
    local taxa=$1
    tc qdisc del dev $INTERFACE root 2>/dev/null
    tc qdisc del dev $INTERFACE ingress 2>/dev/null
    
    # Upload (Egress)
    if [ "$TIPO_IA" == "1" ] || [ "$TIPO_IA" == "3" ]; then
        tc qdisc add dev $INTERFACE root handle 1: htb default 10
        tc class add dev $INTERFACE parent 1: classid 1:10 htb rate ${taxa}mbit ceil ${taxa}mbit burst 100k
    fi
    # Download (Ingress - Policiamento Bruto)
    if [ "$TIPO_IA" == "2" ] || [ "$TIPO_IA" == "3" ]; then
        tc qdisc add dev $INTERFACE handle ffff: ingress
        tc filter add dev $INTERFACE parent ffff: protocol all u32 match u32 0 0 police rate ${taxa}mbit burst 100kb mtu 2k drop flowid :1
    fi
}

while true; do
    R1=$(cat /sys/class/net/$INTERFACE/statistics/rx_bytes)
    T1=$(cat /sys/class/net/$INTERFACE/statistics/tx_bytes)
    sleep 2
    R2=$(cat /sys/class/net/$INTERFACE/statistics/rx_bytes)
    T2=$(cat /sys/class/net/$INTERFACE/statistics/tx_bytes)
    
    RX=$(( (R2 - R1) * 8 / 2 / 1048576 )); TX=$(( (T2 - T1) * 8 / 2 / 1048576 ))
    CUR=$(( RX > TX ? RX : TX ))

    if [ "$CUR" -ge "$(( LIMITE_BASE - 15 ))" ]; then
        aplicar_regra $BOOST; sleep 10
        [ $(( RANDOM % 2 )) -eq 0 ] && NOVA=$MINIMO || NOVA=$MEDIO
        aplicar_regra $NOVA; sleep 15
    else
        aplicar_regra $LIMITE_BASE
    fi
    sleep 1
done
WORKER

chmod +x /usr/local/bin/gravonyx_worker.sh

# 6. CRIAR O ARQUIVO DE SERVIÇO (O CORAÇÃO DO SEGUNDO PLANO)
cat << SERVICE > /etc/systemd/system/gravonyx-ia.service
[Unit]
Description=Gravonyx IA Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/gravonyx_worker.sh
Restart=always
RestartSec=3
User=root

[Install]
WantedBy=multi-user.target
SERVICE

# 7. CRIAR O PAINEL DE MONITORAMENTO (STATUS)
cat << 'PANEL' > /usr/local/bin/painel.sh
#!/bin/bash
source /etc/gravonyx_ia.conf
tput civis; trap "tput cnorm; clear; exit" INT TERM; clear
while true; do
    tput cup 0 0
    echo -e "\e[36m###############################################################"
    echo -e "#            MONITOR DE TRÁFEGO GRAVONYX IA                   #"
    echo -e "###############################################################\e[0m"
    echo -e " Status: \e[32m● ATIVO EM SEGUNDO PLANO\e[0m"
    R1=$(cat /sys/class/net/$INTERFACE/statistics/rx_bytes); sleep 1; R2=$(cat /sys/class/net/$INTERFACE/statistics/rx_bytes)
    RX=$(( (R2-R1)*8/1048576 ))
    LIM=$(tc class show dev $INTERFACE | grep -oP 'rate \K[^\s]+' | head -1)
    echo "---------------------------------------------------------------"
    printf " CONSUMO ATUAL: \e[32m%-10s Mbps\e[0m\n" "$RX"
    printf " LIMITE ATIVO:  \e[33m%-20s\e[0m\n" "${LIM:-Padrão}"
    echo "---------------------------------------------------------------"
    BARRA=$(( RX / 25 )); [ $BARRA -gt 25 ] && BARRA=25
    printf " [\e[32m%-25s\e[0m] %s Mbps\n" "$(printf '#%.0s' $(seq 1 $BARRA 2>/dev/null))" "$RX"
    echo -e "\n\e[33m [CTRL+C] para sair | IA continua rodando.\e[0m"
    tput ed
done
PANEL

chmod +x /usr/local/bin/painel.sh

# 8. CONFIGURAR O ALIAS "status"
grep -q "alias status" ~/.bashrc || echo "alias status='/usr/local/bin/painel.sh'" >> ~/.bashrc

# 9. ATIVAÇÃO FINAL
systemctl daemon-reload
systemctl enable gravonyx-ia
systemctl start gravonyx-ia

echo -e "\n${VERDE}✅ TUDO PRONTO E CORRIGIDO!${NC}"
echo -e "Para ver o painel, digite: ${AMARELO}source ~/.bashrc${NC} e depois ${VERDE}status${NC}"
EOF

chmod +x instalar_gravonyx.sh
./instalar_gravonyx.sh
