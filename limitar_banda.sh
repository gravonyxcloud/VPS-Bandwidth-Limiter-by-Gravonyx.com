cat << 'EOF' > instalar_ia.sh
#!/bin/bash

# Cores
VERDE='\033[0;32m'
CIANO='\033[0;36m'
AMARELO='\033[1;33m'
VERMELHO='\033[0;31m'
NC='\033[0m'

# 1. BANNER DE INSTALAÇÃO
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
echo -e "#  ${VERDE}INSTALADOR: MODO SERVIÇO IA${NC}  |     ${AMARELO}GRAVONYX.COM${CIANO}        #"
echo -e "###############################################################${NC}"

# 2. COLETA DE DADOS
read -p "Qual o limite real da sua VPS em Mbps? (ex: 600): " LIMITE_BASE
read -p "Deseja limitar Upload, Download ou Ambos? (1=Up, 2=Down, 3=Ambos): " TIPO_IA

INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)

# 3. ARQUIVO DE CONFIGURAÇÃO PERMANENTE
echo "INTERFACE=$INTERFACE
LIMITE_BASE=$LIMITE_BASE
TIPO_IA=$TIPO_IA
BOOST=$(( LIMITE_BASE + 10 ))
MINIMO=$(( LIMITE_BASE / 2 ))
MEDIO=$(( LIMITE_BASE * 3 / 4 ))" > /etc/gravonyx_ia.conf

# 4. SCRIPT WORKER (O QUE RODA NO FUNDO - MANTENDO SUA LÓGICA)
cat << 'WORKER_SCRIPT' > /usr/local/bin/gravonyx_worker.sh
#!/bin/bash
source /etc/gravonyx_ia.conf

aplicar_regra() {
    local taxa=$1
    tc qdisc del dev $INTERFACE root 2>/dev/null
    tc qdisc del dev $INTERFACE ingress 2>/dev/null
    ethtool -K $INTERFACE gro off gso off tso off 2>/dev/null
    
    # Upload + Proteção SSH (Para o terminal não travar)
    tc qdisc add dev $INTERFACE root handle 1: htb default 20
    tc class add dev $INTERFACE parent 1: classid 1:1 htb rate ${taxa}mbit ceil ${taxa}mbit
    tc class add dev $INTERFACE parent 1:1 classid 1:10 htb rate 15mbit ceil ${taxa}mbit prio 1
    tc class add dev $INTERFACE parent 1:1 classid 1:20 htb rate $((taxa - 15))mbit ceil $((taxa - 15))mbit prio 2
    tc filter add dev $INTERFACE parent 1: protocol ip prio 1 u32 match ip dport 22 0xffff flowid 1:10
    tc filter add dev $INTERFACE parent 1: protocol ip prio 1 u32 match ip sport 22 0xffff flowid 1:10

    # Download (Com Burst de 1mb para não ficar lento demais)
    if [ "$TIPO_IA" == "2" ] || [ "$TIPO_IA" == "3" ]; then
        tc qdisc add dev $INTERFACE handle ffff: ingress
        tc filter add dev $INTERFACE parent ffff: protocol all u32 match u32 0 0 \
        police rate ${taxa}mbit burst 1mb mtu 64kb drop flowid :1
    fi
}

while true; do
    RX1=$(cat /sys/class/net/$INTERFACE/statistics/rx_bytes)
    TX1=$(cat /sys/class/net/$INTERFACE/statistics/tx_bytes)
    sleep 2
    RX2=$(cat /sys/class/net/$INTERFACE/statistics/rx_bytes)
    TX2=$(cat /sys/class/net/$INTERFACE/statistics/tx_bytes)
    
    SPEED_RX=$(( (RX2 - RX1) * 8 / 2 / 1048576 ))
    SPEED_TX=$(( (TX2 - TX1) * 8 / 2 / 1048576 ))
    CURRENT=$(( SPEED_RX > SPEED_TX ? SPEED_RX : SPEED_TX ))

    if [ "$CURRENT" -ge "$(( LIMITE_BASE - 15 ))" ]; then
        aplicar_regra $BOOST; sleep 10
        [ $(( RANDOM % 2 )) -eq 0 ] && NOVA=$MINIMO || NOVA=$MEDIO
        aplicar_regra $NOVA; sleep 15
    else
        aplicar_regra $LIMITE_BASE
    fi
    sleep 1
done
WORKER_SCRIPT

chmod +x /usr/local/bin/gravonyx_worker.sh

# 5. SCRIPT DO PAINEL (TRAFFIC STATUS)
cat << 'PANEL_SCRIPT' > /usr/local/bin/painel.sh
#!/bin/bash
source /etc/gravonyx_ia.conf
tput civis; trap "tput cnorm; clear; exit" INT TERM; clear
while true; do
    tput cup 0 0
    echo -e "\e[36m###############################################################"
    echo -e "#            MONITOR DE TRÁFEGO GRAVONYX IA                   #"
    echo -e "###############################################################\e[0m"
    R1=$(cat /sys/class/net/$INTERFACE/statistics/rx_bytes); T1=$(cat /sys/class/net/$INTERFACE/statistics/tx_bytes)
    sleep 1
    R2=$(cat /sys/class/net/$INTERFACE/statistics/rx_bytes); T2=$(cat /sys/class/net/$INTERFACE/statistics/tx_bytes)
    RX=$(( (R2-R1)*8/1048576 )); TX=$(( (T2-T1)*8/1048576 ))
    LIM=$(tc class show dev $INTERFACE | grep -oP 'rate \K[^\s]+' | head -1)
    echo -e " Status: \e[32m● SERVIÇO ATIVO EM SEGUNDO PLANO\e[0m"
    echo "---------------------------------------------------------------"
    printf " DOWNLOAD ATUAL: \e[32m%-10s Mbps\e[0m\n" "$RX"
    printf " UPLOAD ATUAL:   \e[32m%-10s Mbps\e[0m\n" "$TX"
    printf " LIMITE NO TC:   \e[33m%-20s\e[0m\n" "${LIM:-Padrao}"
    echo "---------------------------------------------------------------"
    echo -e "\e[33m Pressione [CTRL+C] para sair do painel.\e[0m"
    tput ed
done
PANEL_SCRIPT

chmod +x /usr/local/bin/painel.sh

# 6. CRIANDO O COMANDO GLOBAL 'traffic status'
echo '#!/bin/bash
if [ "$1" == "status" ]; then
    /usr/local/bin/painel.sh
else
    echo "Uso: traffic status"
fi' > /usr/local/bin/traffic
chmod +x /usr/local/bin/traffic

# 7. CRIANDO O SERVIÇO SYSTEMD
echo "[Unit]
Description=Gravonyx IA Bandwidth Management
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/gravonyx_worker.sh
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target" > /etc/systemd/system/gravonyx-ia.service

# 8. ATIVAÇÃO FINAL
systemctl daemon-reload
systemctl enable gravonyx-ia
systemctl restart gravonyx-ia

echo -e "\n${VERDE}✅ INSTALAÇÃO CONCLUÍDA COM SUCESSO!${NC}"
echo -e "O comando ${AMARELO}traffic status${NC} já está disponível."
EOF

chmod +x instalar_ia.sh
./instalar_ia.sh
