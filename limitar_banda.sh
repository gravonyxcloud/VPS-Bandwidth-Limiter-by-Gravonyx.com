cat << 'EOF' > instalar_gravonyx.sh
#!/bin/bash

# Cores
VERDE='\033[0;32m'
CIANO='\033[0;36m'
AMARELO='\033[1;33m'
NC='\033[0m'

# 1. PREPARAÇÃO E LIMPEZA
systemctl stop gravonyx-ia 2>/dev/null
INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
apt-get update -y &>/dev/null
apt-get install iproute2 ethtool -y &>/dev/null

# 2. INPUT DE DADOS
clear
echo -e "${CIANO}###############################################################"
echo -e "#            INSTALADOR GRAVONYX IA - VERSÃO FINAL            #"
echo -e "###############################################################${NC}"
read -p "Limite da VPS em Mbps? (ex: 600): " LIMITE_BASE
read -p "Tipo de Limite (1=Up, 2=Down, 3=Ambos): " TIPO_IA

# 3. SALVAR CONFIGURAÇÃO
cat << CONF > /etc/gravonyx_ia.conf
INTERFACE=$INTERFACE
LIMITE_BASE=$LIMITE_BASE
TIPO_IA=$TIPO_IA
BOOST=$(( LIMITE_BASE + 10 ))
MINIMO=$(( LIMITE_BASE / 2 ))
MEDIO=$(( LIMITE_BASE * 3 / 4 ))
CONF

# 4. WORKER (O que roda no fundo)
cat << 'WORKER' > /usr/local/bin/gravonyx_worker.sh
#!/bin/bash
source /etc/gravonyx_ia.conf
ethtool -K $INTERFACE gro off gso off tso off 2>/dev/null

aplicar() {
    local taxa=$1
    tc qdisc del dev $INTERFACE root 2>/dev/null
    tc qdisc del dev $INTERFACE ingress 2>/dev/null
    [ "$TIPO_IA" == "1" ] || [ "$TIPO_IA" == "3" ] && {
        tc qdisc add dev $INTERFACE root handle 1: htb default 10
        tc class add dev $INTERFACE parent 1: classid 1:10 htb rate ${taxa}mbit ceil ${taxa}mbit burst 100k
    }
    [ "$TIPO_IA" == "2" ] || [ "$TIPO_IA" == "3" ] && {
        tc qdisc add dev $INTERFACE handle ffff: ingress
        tc filter add dev $INTERFACE parent ffff: protocol all u32 match u32 0 0 police rate ${taxa}mbit burst 100kb mtu 2k drop flowid :1
    }
}

while true; do
    R1=$(cat /sys/class/net/$INTERFACE/statistics/rx_bytes); T1=$(cat /sys/class/net/$INTERFACE/statistics/tx_bytes)
    sleep 2
    R2=$(cat /sys/class/net/$INTERFACE/statistics/rx_bytes); T2=$(cat /sys/class/net/$INTERFACE/statistics/tx_bytes)
    RX=$(( (R2-R1)*8/2/1048576 )); TX=$(( (T2-T1)*8/2/1048576 ))
    CUR=$(( RX > TX ? RX : TX ))
    if [ "$CUR" -ge "$(( LIMITE_BASE - 15 ))" ]; then
        aplicar $BOOST; sleep 10
        [ $(( RANDOM % 2 )) -eq 0 ] && N=$MINIMO || N=$MEDIO
        aplicar $N; sleep 15
    else
        aplicar $LIMITE_BASE
    fi
    sleep 1
done
WORKER

chmod +x /usr/local/bin/gravonyx_worker.sh

# 5. SERVIÇO SYSTEMD
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

# 6. PAINEL DE MONITORAMENTO (STATUS)
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
    
    R1=$(cat /sys/class/net/$INTERFACE/statistics/rx_bytes); T1=$(cat /sys/class/net/$INTERFACE/statistics/tx_bytes)
    sleep 1
    R2=$(cat /sys/class/net/$INTERFACE/statistics/rx_bytes); T2=$(cat /sys/class/net/$INTERFACE/statistics/tx_bytes)
    RX=$(( (R2-R1)*8/1048576 )); TX=$(( (T2-T1)*8/1048576 ))
    LIM=$(tc class show dev $INTERFACE | grep -oP 'rate \K[^\s]+' | head -1)

    echo "---------------------------------------------------------------"
    printf " \e[33mDOWNLOAD:\e[0m \e[32m%-10s Mbps\e[0m | \e[33mUPLOAD:\e[0m \e[32m%-10s Mbps\e[0m\n" "$RX" "$TX"
    printf " \e[33mLIMITE ATIVO NO TC:\e[0m  \e[32m%-20s\e[0m\n" "${LIM:-Padrão}"
    echo "---------------------------------------------------------------"
    MAX=$(( RX > TX ? RX : TX ))
    BARRA=$(( MAX / 25 )); [ $BARRA -gt 25 ] && BARRA=25
    printf " Uso: [\e[32m%-25s\e[0m] %s Mbps\n" "$(printf '#%.0s' $(seq 1 $BARRA 2>/dev/null))" "$MAX"
    echo -e "\n\e[36m [CTRL+C] para sair | IA continua rodando no fundo.\e[0m"
    tput ed
done
PANEL

chmod +x /usr/local/bin/painel.sh

# 7. CRIAR A FUNÇÃO "traffic status"
sed -i '/traffic()/,/}/d' ~/.bashrc
cat << 'FUNC' >> ~/.bashrc
traffic() {
    if [ "$1" == "status" ]; then
        /usr/local/bin/painel.sh
    else
        echo "Comando não reconhecido. Use: traffic status"
    fi
}
FUNC

# 8. START
systemctl daemon-reload
systemctl enable gravonyx-ia
systemctl start gravonyx-ia

echo -e "\n${VERDE}✅ INSTALADO COM SUCESSO!${NC}"
echo -e "Para ativar o comando, digite: ${AMARELO}source ~/.bashrc${NC}"
echo -e "Para ver o painel, use: ${VERDE}traffic status${NC}"
EOF

chmod +x instalar_gravonyx.sh
./instalar_gravonyx.sh
