cat << 'EOF' > instalar_ia.sh
#!/bin/bash

# Cores
VERDE='\033[0;32m'
CIANO='\033[0;36m'
AMARELO='\033[1;33m'
VERMELHO='\033[0;31m'
NC='\033[0m'

# 1. BANNER
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

# 2. COLETA DE DADOS (Será salva permanentemente)
read -p "Qual o limite real da sua VPS em Mbps? (ex: 600): " LIMITE_BASE
read -p "Deseja limitar Upload, Download ou Ambos? (1=Up, 2=Down, 3=Ambos): " TIPO_IA

# 3. CRIAÇÃO DO ARQUIVO DE CONFIGURAÇÃO
cat << CONF > /etc/gravonyx_ia.conf
INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
LIMITE_BASE=$LIMITE_BASE
TIPO_IA=$TIPO_IA
BOOST=$(( LIMITE_BASE + 10 ))
MINIMO=$(( LIMITE_BASE / 2 ))
MEDIO=$(( LIMITE_BASE * 3 / 4 ))
CONF

# 4. CRIAÇÃO DO SCRIPT WORKER (O que roda no fundo)
cat << 'WORKER' > /usr/local/bin/gravonyx_worker.sh
#!/bin/bash
source /etc/gravonyx_ia.conf

aplicar_regra() {
    local taxa=$1
    tc qdisc del dev $INTERFACE root 2>/dev/null
    tc qdisc del dev $INTERFACE ingress 2>/dev/null
    ethtool -K $INTERFACE gro off gso off tso off 2>/dev/null
    
    # Upload
    if [ "$TIPO_IA" == "1" ] || [ "$TIPO_IA" == "3" ]; then
        tc qdisc add dev $INTERFACE root handle 1: htb default 10
        tc class add dev $INTERFACE parent 1: classid 1:10 htb rate ${taxa}mbit ceil ${taxa}mbit burst 100k
    fi
    # Download
    if [ "$TIPO_IA" == "2" ] || [ "$TIPO_IA" == "3" ]; then
        tc qdisc add dev $INTERFACE handle ffff: ingress
        tc filter add dev $INTERFACE parent ffff: protocol all u32 match u32 0 0 police rate ${taxa}mbit burst 100kb mtu 2k drop flowid :1
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
        aplicar_regra $BOOST
        sleep 10
        [ $(( RANDOM % 2 )) -eq 0 ] && NOVA=$MINIMO || NOVA=$MEDIO
        aplicar_regra $NOVA
        sleep 15
    else
        aplicar_regra $LIMITE_BASE
    fi
    sleep 1
done
WORKER

chmod +x /usr/local/bin/gravonyx_worker.sh

# 5. CRIAÇÃO DO SERVIÇO SYSTEMD
cat << SERVICE > /etc/systemd/system/gravonyx-ia.service
[Unit]
Description=Gravonyx IA Bandwidth Management
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/gravonyx_worker.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE

# 6. ATIVAÇÃO
systemctl daemon-reload
systemctl enable gravonyx-ia
systemctl restart gravonyx-ia

echo -e "\n${VERDE}✅ INSTALAÇÃO CONCLUÍDA COM SUCESSO!${NC}"
echo -e "${CIANO}O serviço está rodando em segundo plano e iniciará com a VPS.${NC}"
echo -e "\n${AMARELO}Comandos úteis:${NC}"
echo -e "Ver Status: ${CIANO}systemctl status gravonyx-ia${NC}"
echo -e "Parar:      ${CIANO}systemctl stop gravonyx-ia${NC}"
echo -e "Iniciar:    ${CIANO}systemctl start gravonyx-ia${NC}"
EOF

chmod +x instalar_ia.sh
./instalar_ia.sh
