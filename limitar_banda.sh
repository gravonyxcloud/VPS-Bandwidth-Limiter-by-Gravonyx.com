cat << 'EOF' > instalar_gravonyx.sh
#!/bin/bash

# Cores
VERDE='\033[0;32m'
CIANO='\033[0;36m'
AMARELO='\033[1;33m'
NC='\033[0m'

# 1. PREPARAÇÃO
systemctl stop gravonyx-ia 2>/dev/null
INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
apt-get update -y &>/dev/null
apt-get install iproute2 ethtool -y &>/dev/null

# 2. INPUT
clear
echo -e "${CIANO}###############################################################"
echo -e "#         GRAVONYX IA v8.0 - SSH SAFE & SMOOTH                #"
echo -e "###############################################################${NC}"
read -p "Limite da VPS em Mbps? (ex: 600): " LIMITE_BASE
read -p "Tipo de Limite (1=Up, 2=Down, 3=Ambos): " TIPO_IA

# 3. CONFIGURAÇÃO
cat << CONF > /etc/gravonyx_ia.conf
INTERFACE=$INTERFACE
LIMITE_BASE=$LIMITE_BASE
TIPO_IA=$TIPO_IA
BOOST=$(( LIMITE_BASE + 10 ))
MINIMO=$(( LIMITE_BASE / 2 ))
MEDIO=$(( LIMITE_BASE * 3 / 4 ))
CONF

# 4. WORKER COM PROTEÇÃO DE SSH
cat << 'WORKER' > /usr/local/bin/gravonyx_worker.sh
#!/bin/bash
source /etc/gravonyx_ia.conf

aplicar() {
    local taxa=$1
    tc qdisc del dev $INTERFACE root 2>/dev/null
    tc qdisc del dev $INTERFACE ingress 2>/dev/null

    # --- SAÍDA (UPLOAD) COM PRIORIDADE SSH ---
    tc qdisc add dev $INTERFACE root handle 1: htb default 20
    # Classe Mestre
    tc class add dev $INTERFACE parent 1: classid 1:1 htb rate ${taxa}mbit ceil ${taxa}mbit
    # Classe 10: Prioridade Alta (SSH) - Garantimos 5mbps fixos só pra você
    tc class add dev $INTERFACE parent 1:1 classid 1:10 htb rate 5mbit ceil ${taxa}mbit prio 1
    # Classe 20: Tráfego Normal
    tc class add dev $INTERFACE parent 1:1 classid 1:20 htb rate $((taxa - 5))mbit ceil $((taxa - 5))mbit prio 2
    
    # Filtro para jogar SSH (porta 22) na via rápida
    tc filter add dev $INTERFACE parent 1: protocol ip prio 1 u32 match ip dport 22 0xffff flowid 1:10
    tc filter add dev $INTERFACE parent 1: protocol ip prio 1 u32 match ip sport 22 0xffff flowid 1:10

    # --- ENTRADA (DOWNLOAD) COM BURST SUAVE ---
    if [ "$TIPO_IA" == "2" ] || [ "$TIPO_IA" == "3" ]; then
        tc qdisc add dev $INTERFACE handle ffff: ingress
        # Aumentamos o burst para 512kb para o download não "engasgar"
        tc filter add dev $INTERFACE parent ffff: protocol all u32 match u32 0 0 \
        police rate ${taxa}mbit burst 512kb mtu 64kb drop flowid :1
    fi
}

while true; do
    R1=$(cat /sys/class/net/$INTERFACE/statistics/rx_bytes); T1=$(cat /sys/class/net/$INTERFACE/statistics/tx_bytes)
    sleep 2
    R2=$(cat /sys/class/net/$INTERFACE/statistics/rx_bytes); T2=$(cat /sys/class/net/$INTERFACE/statistics/tx_bytes)
    RX=$(( (R2-R1)*4/1048576 )); TX=$(( (T2-T1)*4/1048576 )) # Cálculo p/ 2 segundos
    CUR=$(( RX > TX ? RX : TX ))

    if [ "$CUR" -ge "$(( LIMITE_BASE - 20 ))" ]; then
        aplicar $BOOST; sleep 8
        [ $(( RANDOM % 2 )) -eq 0 ] && N=$MINIMO || N=$MEDIO
        aplicar $N; sleep 12
    else
        # Só aplica se não houver regra ativa ou para manter estabilidade
        aplicar $LIMITE_BASE
    fi
    sleep 2
done
WORKER

chmod +x /usr/local/bin/gravonyx_worker.sh

# 5. COMANDO TRAFFIC STATUS
cat << 'PANEL' > /usr/local/bin/painel.sh
#!/bin/bash
source /etc/gravonyx_ia.conf
tput civis; trap "tput cnorm; clear; exit" INT TERM; clear
while true; do
    tput cup 0 0
    echo -e "\e[36m###############################################################"
    echo -e "#            MONITOR DE TRÁFEGO GRAVONYX IA                   #"
    echo -e "###############################################################\e[0m"
    R1=$(cat /sys/class/net/$INTERFACE/statistics/rx_bytes); sleep 1; R2=$(cat /sys/class/net/$INTERFACE/statistics/rx_bytes)
    T1=$(cat /sys/class/net/$INTERFACE/statistics/tx_bytes); T2=$(cat /sys/class/net/$INTERFACE/statistics/tx_bytes)
    RX=$(( (R2-R1)*8/1048576 )); TX=$(( (T2-T1)*8/1048576 ))
    LIM=$(tc class show dev $INTERFACE | grep -oP 'rate \K[^\s]+' | head -1)
    echo -e " Status: \e[32m● PROTEÇÃO SSH ATIVA\e[0m"
    echo "---------------------------------------------------------------"
    printf " DOWNLOAD: \e[32m%-10s Mbps\e[0m | UPLOAD: \e[32m%-10s Mbps\e[0m\n" "$RX" "$TX"
    printf " LIMITE ATIVO: \e[33m%-20s\e[0m\n" "${LIM:-Padrão}"
    echo "---------------------------------------------------------------"
    tput ed
done
PANEL
chmod +x /usr/local/bin/painel.sh

# 6. CRIAÇÃO DO COMANDO 'traffic'
cat << 'EOF' > /usr/local/bin/traffic
#!/bin/bash
if [ "$1" == "status" ]; then /usr/local/bin/painel.sh; else echo "Use: traffic status"; fi
EOF
chmod +x /usr/local/bin/traffic

# 7. SERVIÇO
cat << SERVICE > /etc/systemd/system/gravonyx-ia.service
[Unit]
Description=Gravonyx IA Service
After=network.target

[Service]
ExecStart=/usr/local/bin/gravonyx_worker.sh
Restart=always
User=root

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable gravonyx-ia
systemctl start gravonyx-ia

echo -e "\n${VERDE}✅ INSTALADO! O SSH agora está em via prioritária.${NC}"
echo -e "Use: ${AMARELO}traffic status${NC}"
EOF

chmod +x instalar_gravonyx.sh
./instalar_gravonyx.sh
