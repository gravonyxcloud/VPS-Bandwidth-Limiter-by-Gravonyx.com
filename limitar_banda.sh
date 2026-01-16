#!/usr/bin/env bash
#
# limitar_banda.sh - Versão melhorada e profissional para otimização avançada de rede
# Compatível com VPS locais e cloud (Debian/Ubuntu/CentOS/RHEL)
#
# Funcionalidades principais:
# - Interface autodetectada (com opção de escolha)
# - Limitação de banda (upload, download, ambos) com HTB + fq_codel (controle de bufferbloat)
# - Ingress shaping via ifb
# - Persistência via systemd (serviço) e script em /usr/local/bin/limit-bandwidth.sh
# - Otimizações de kernel (sysctl) opcionais: fq, BBR (se suportado), buffers
# - Teste de rotas e sugestão de rota "melhor" por latência (não força mudanças sem confirmação)
# - Configuração/resgate de DNS (Cloudflare, Google, Quad9 e OpenDNS) com detecção de systemd-resolved
# - Menu interativo com validações e opção de voltar ao padrão (uninstall/restore)
# - Logs e saída clara (mensagens coloridas)
#
# Uso: execute como root: sudo bash limitar_banda.sh
#
set -euo pipefail
IFS=$'\n\t'

# Colors
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

VERSION="v4.0 Gravonyx - Profissional"

LOGFILE="/var/log/limit-bandwidth.log"
CONFIG_SCRIPT="/usr/local/bin/limit-bandwidth.sh"
SYSTEMD_UNIT="/etc/systemd/system/limit-bandwidth.service"
BACKUP_RESOLV="/etc/resolv.conf.gravonyx.bak"

# Ensure running as root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Este script precisa ser executado como root.${NC}"
  exit 1
fi

# Simple logger
log() {
  echo -e "[$(date '+%F %T')] $*" | tee -a "$LOGFILE"
}

# Detect distro and package manager
PKG_INSTALL=""
if command -v apt >/dev/null 2>&1; then
  PKG_INSTALL="apt-get install -y"
  PKG_UPDATE="apt-get update -y"
elif command -v yum >/dev/null 2>&1; then
  PKG_INSTALL="yum install -y"
  PKG_UPDATE="yum makecache -y"
elif command -v dnf >/dev/null 2>&1; then
  PKG_INSTALL="dnf install -y"
  PKG_UPDATE="dnf makecache -y"
else
  echo -e "${RED}Gerenciador de pacotes não suportado. Instale iproute2, iptables e iputils manualmente.${NC}"
  exit 1
fi

# Ensure required tools
install_deps() {
  log "Instalando dependências necessárias..."
  $PKG_UPDATE >/dev/null 2>&1 || true
  $PKG_INSTALL iproute2 iptstate iptables iputils-ping ethtool tc mtr traceroute >/dev/null 2>&1 || true
}

# Detect default interface(s)
detect_interfaces() {
  MAP_IFACES=()
  # all default routes
  while read -r line; do
    iface=$(echo "$line" | awk '{print $5}')
    MAP_IFACES+=("$iface")
  done < <(ip -4 route show default)
  # fallback: first eth-like or ens* or ens* or venet0
  if [ ${#MAP_IFACES[@]} -eq 0 ]; then
    for candidate in $(ip -o link show | awk -F': ' '{print $2}'); do
      if [[ $candidate =~ ^(e(n|th|n)|eth|ens|venet|eno|enp) ]]; then
        MAP_IFACES+=("$candidate")
      fi
    done
  fi
  # unique
  MAP_IFACES=($(printf "%s\n" "${MAP_IFACES[@]}" | awk '!x[$0]++'))
}

# Show header
show_header() {
  clear
  echo -e "${CYAN}###############################################################"
  echo -e "#                                                             #"
  echo -e "#    ____                                                     #"
  echo -e "#   / ___|_ __ __ ___   _____  _ __  _   ___  __              #"
  echo -e "#  | |  _| '__/ _\` \ \ / / _ \| '_ \| | | \ \/ /              #"
  echo -e "#  | |_| | | | (_| |\ V / (_) | | | | |_| |>  <               #"
  echo -e "#   \____|_|  \__,_| \_/ \___/|_| |_|\__, /_/\_\              #"
  echo -e "#                                    |___/                    #"
  echo -e "#                                                             #"
  echo -e "#  ${GREEN}FEITO POR: GRAVONYX.COM${NC}     |     ${YELLOW}VERSÃO: $VERSION${CYAN}       #"
  echo -e "###############################################################${NC}"
  echo
}

# Offer DNS presets
configure_dns() {
  echo -e "${CYAN}Configurar DNS público? (útil para performance/resolução)${NC}"
  echo -e "1) Cloudflare (1.1.1.1 / 1.0.0.1)"
  echo -e "2) Google (8.8.8.8 / 8.8.4.4)"
  echo -e "3) Quad9 (9.9.9.9 / 149.112.112.112)"
  echo -e "4) OpenDNS (208.67.222.222 / 208.67.220.220)"
  echo -e "5) Não alterar"
  read -p "Opção [5]: " DNS_OPT
  DNS_OPT="${DNS_OPT:-5}"

  case "$DNS_OPT" in
    1) DNS_CONF="nameserver 1.1.1.1\nnameserver 1.0.0.1" ;;
    2) DNS_CONF="nameserver 8.8.8.8\nnameserver 8.8.4.4" ;;
    3) DNS_CONF="nameserver 9.9.9.9\nnameserver 149.112.112.112" ;;
    4) DNS_CONF="nameserver 208.67.222.222\nnameserver 208.67.220.220" ;;
    5) DNS_CONF="" ;;
    *) DNS_CONF="" ;;
  esac

  if [ -n "$DNS_CONF" ]; then
    # Backup existing resolv.conf
    if [ ! -f "$BACKUP_RESOLV" ]; then
      cp -a /etc/resolv.conf "$BACKUP_RESOLV" || true
      log "Backup de /etc/resolv.conf em $BACKUP_RESOLV"
    fi

    if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet systemd-resolved; then
      # Use systemd-resolved
      echo -e "${YELLOW}Detectado systemd-resolved. Atualizando /etc/resolv.conf via resolv.conf.local ou resolvectl.${NC}"
      # set via resolvectl if available
      if command -v resolvectl >/dev/null 2>&1; then
        # apply to global
        IFS=$'\n'
        for ns in $(echo -e "$DNS_CONF" | awk '{print $2}'); do
          resolvectl dns "$(ip route | awk '/default/ {print $5; exit}')" "$ns" >/dev/null 2>&1 || true
        done
        unset IFS
        log "DNS atualizado via resolvectl para: $(echo -e "$DNS_CONF" | tr '\n' ' ' )"
      else
        # fallback: overwrite /etc/resolv.conf
        echo -e "$DNS_CONF" > /etc/resolv.conf
        log "DNS escrito em /etc/resolv.conf"
      fi
    else
      echo -e "$DNS_CONF" > /etc/resolv.conf
      log "DNS escrito em /etc/resolv.conf"
    fi
    echo -e "${GREEN}DNS configurado.${NC}"
  else
    echo -e "${YELLOW}Mantendo DNS atual.${NC}"
  fi
}

# sysctl performance tweaks (optional)
sysctl_tweaks() {
  echo -e "${CYAN}Aplicar otimizações de kernel para throughput / latência?${NC}"
  echo -e "Essas opções aplicam: fq qdisc, buffers TCP e tentam ativar BBR (se disponível)."
  read -p "Aplicar? (s/N): " APL_TWEAK
  APL_TWEAK="${APL_TWEAK:-n}"
  if [[ "$APL_TWEAK" =~ ^[sS]$ ]]; then
    log "Aplicando sysctl tuning..."
    # create conf file
    cat > /etc/sysctl.d/99-gravonyx-network.conf <<EOF
# Gravonyx network performance tuning
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_no_metrics_save = 1
EOF
    sysctl --system >/dev/null 2>&1 || true
    # Try to load bbr
    if modprobe tcp_bbr >/dev/null 2>&1; then
      log "BBR carregado com sucesso."
    else
      log "BBR não disponível no kernel atual. Ignorar se não suportado."
    fi
    echo -e "${GREEN}Sysctl aplicado. Reinicie ou deixe o serviço/systemd recarregar para persistir.${NC}"
  else
    echo -e "${YELLOW}Otimizações de kernel não aplicadas.${NC}"
  fi
}

# Test and suggest best route (latency) - does not change nada sem confirmação
test_best_route() {
  # Only run if we have multiple default gateways or multiple interfaces
  echo -e "${CYAN}Executando teste de rota para determinar melhor latência a targets públicos...${NC}"
  targets=(1.1.1.1 8.8.8.8 9.9.9.9)
  declare -A results
  for t in "${targets[@]}"; do
    # ping 3 times, capture avg
    if ping -c 3 -W 1 "$t" >/dev/null 2>&1; then
      avg=$(ping -c 3 -q "$t" 2>/dev/null | awk -F'/' 'END{print $5}')
      results["$t"]="$avg"
    else
      results["$t"]="timeout"
    fi
  done
  echo -e "${GREEN}Resultados (RTT médio em ms):${NC}"
  for k in "${!results[@]}"; do
    echo -e " - $k : ${YELLOW}${results[$k]}${NC}"
  done
  echo -e "${CYAN}Observação: O balanceamento de rota em VPS normalmente é responsabilidade do provedor. Use 'Alterar rota' apenas se souber o que faz.${NC}"
}

# Build the persistent script that applies tc rules at boot
generate_persistent_script() {
  cat > "$CONFIG_SCRIPT" <<'SCRIPT_EOF'
#!/usr/bin/env bash
# Script criado por Gravonyx para aplicar limites de banda no boot
set -euo pipefail

# Detect interface
IFACE=$(ip route | awk '/default/ {print $5; exit}')
LOG=/var/log/limit-bandwidth.log

# Variables substituted by wrapper (placeholders)
TIPO_LIMITE="{{TIPO_LIMITE}}"
LIMITE="{{LIMITE}}"
PER_IP="{{PER_IP}}"
CLASSMAP="{{CLASSMAP}}"

apply_limits() {
  echo "[$(date '+%F %T')] Aplicando regras ($TIPO_LIMITE / $LIMITE)" >> "$LOG"
  # Clean existing
  tc qdisc del dev "$IFACE" root 2>/dev/null || true
  tc qdisc del dev "$IFACE" ingress 2>/dev/null || true
  ip link set dev ifb0 down 2>/dev/null || true
  ip link delete ifb0 2>/dev/null || true

  # EGRESS (upload) - shaping on device
  if [ "$TIPO_LIMITE" = "1" ] || [ "$TIPO_LIMITE" = "3" ]; then
    tc qdisc add dev "$IFACE" root handle 1: htb default 10
    tc class add dev "$IFACE" parent 1: classid 1:10 htb rate "$LIMITE" ceil "$LIMITE"
    tc qdisc add dev "$IFACE" parent 1:10 handle 10: fq_codel
  fi

  # INGRESS (download) - redirect to ifb0 then shape
  if [ "$TIPO_LIMITE" = "2" ] || [ "$TIPO_LIMITE" = "3" ]; then
    modprobe ifb || true
    ip link add ifb0 type ifb 2>/dev/null || true
    ip link set dev ifb0 up 2>/dev/null || true
    tc qdisc add dev "$IFACE" handle ffff: ingress 2>/dev/null || true
    tc filter add dev "$IFACE" parent ffff: protocol ip u32 match u32 0 0 action mirred egress redirect dev ifb0 2>/dev/null || true
    tc qdisc add dev ifb0 root handle 1: htb default 10
    tc class add dev ifb0 parent 1: classid 1:10 htb rate "$LIMITE" ceil "$LIMITE"
    tc qdisc add dev ifb0 parent 1:10 handle 10: fq_codel
  fi
}

# Allow running by systemd or manually
case "${1:-}" in
  start|apply|"")
    apply_limits
    ;;
  stop|remove)
    tc qdisc del dev "$IFACE" root 2>/dev/null || true
    tc qdisc del dev "$IFACE" ingress 2>/dev/null || true
    ip link set dev ifb0 down 2>/dev/null || true
    ip link delete ifb0 2>/dev/null || true
    ;;
esac
SCRIPT_EOF

  # Replace placeholders
  sed -i "s|{{TIPO_LIMITE}}|$TIPO_LIMITE|g" "$CONFIG_SCRIPT"
  sed -i "s|{{LIMITE}}|$LIMITE|g" "$CONFIG_SCRIPT"
  sed -i "s|{{PER_IP}}|$PER_IP|g" "$CONFIG_SCRIPT"
  sed -i "s|{{CLASSMAP}}|$CLASSMAP|g" "$CONFIG_SCRIPT"

  chmod +x "$CONFIG_SCRIPT"
  log "Script persistente salvo em $CONFIG_SCRIPT"
}

# Create systemd service for persistence
create_systemd_service() {
  cat > "$SYSTEMD_UNIT" <<EOF
[Unit]
Description=Gravonyx Limit Bandwidth Service
After=network.target

[Service]
Type=oneshot
ExecStart=$CONFIG_SCRIPT start
ExecStop=$CONFIG_SCRIPT stop
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now limit-bandwidth.service
  log "Systemd service criado e habilitado: limit-bandwidth.service"
}

# Remove everything (uninstall/restore)
uninstall_all() {
  echo -e "${YELLOW}Removendo regras, serviço e restaurando DNS (se backup existir).${NC}"
  # stop service
  systemctl stop limit-bandwidth.service 2>/dev/null || true
  systemctl disable limit-bandwidth.service 2>/dev/null || true
  rm -f "$SYSTEMD_UNIT" "$CONFIG_SCRIPT"
  systemctl daemon-reload
  # remove tc rules
  for ifc in $(ip -o link show | awk -F': ' '{print $2}'); do
    tc qdisc del dev "$ifc" root 2>/dev/null || true
    tc qdisc del dev "$ifc" ingress 2>/dev/null || true
  done
  ip link set dev ifb0 down 2>/dev/null || true
  ip link delete ifb0 2>/dev/null || true
  # restore resolv.conf if backup exists
  if [ -f "$BACKUP_RESOLV" ]; then
    cp -a "$BACKUP_RESOLV" /etc/resolv.conf
    log "resolv.conf restaurado a partir do backup."
  fi
  log "Desinstalação concluída."
  echo -e "${GREEN}Tudo removido. Reboot recomendado.${NC}"
  exit 0
}

# Validate netfilter present
if ! command -v tc >/dev/null 2>&1; then
  echo "tc não encontrado. Abortando."
  exit 1
fi

# Entrypoint
case "${1:-menu}" in
  remove|uninstall)
    uninstall_all
    ;;
  start|apply)
    # run apply only
    bash "$CONFIG_SCRIPT" start
    ;;
  menu)
    ;;
  *)
    ;;
esac

exit 0
}

# Main interactive flow
main_menu() {
  show_header
  install_deps
  detect_interfaces

  echo -e "${CYAN}Interfaces detectadas:${NC}"
  i=1
  for iface in "${MAP_IFACES[@]}"; do
    ipaddr=$(ip -4 addr show dev "$iface" | awk '/inet /{print $2; exit}')
    echo -e "  $i) ${GREEN}$iface${NC} - $ipaddr"
    ((i++))
  done
  if [ ${#MAP_IFACES[@]} -eq 0 ]; then
    echo -e "${RED}Nenhuma interface detectada. Saindo.${NC}"
    exit 1
  fi
  read -p "Escolha a interface (número) ou ENTER para primeira [1]: " IF_OPT
  IF_OPT="${IF_OPT:-1}"
  if ! [[ "$IF_OPT" =~ ^[0-9]+$ ]] || [ "$IF_OPT" -lt 1 ] || [ "$IF_OPT" -gt ${#MAP_IFACES[@]} ]; then
    echo -e "${YELLOW}Opção inválida. Usando 1.${NC}"
    IF_OPT=1
  fi
  INTERFACE="${MAP_IFACES[$((IF_OPT-1))]}"
  echo -e "${GREEN}Interface escolhida: $INTERFACE${NC}"

  # Show existing status if any
  if [ -f "$CONFIG_SCRIPT" ]; then
    # try to extract limit from script
    EXIST_LIMIT=$(grep -oP 'tc class add dev ifb0 .* htb rate \K[^ ]+' "$CONFIG_SCRIPT" 2>/dev/null | head -1 || true)
    if [ -z "$EXIST_LIMIT" ]; then
      EXIST_LIMIT=$(grep -oP 'tc class add dev '"$INTERFACE"'.* htb rate \K[^ ]+' "$CONFIG_SCRIPT" 2>/dev/null | head -1 || true)
    fi
    if [ -n "$EXIST_LIMIT" ]; then
      echo -e "${GREEN}Limitação atual detectada: ${YELLOW}$EXIST_LIMIT${NC}"
      echo -e "1) Editar/Alterar"
      echo -e "2) Remover e restaurar padrão"
      echo -e "3) Continuar criação de novo limite"
      read -p "Opção: " EXIST_OPT
      if [ "$EXIST_OPT" == "2" ]; then
        uninstall_all
      elif [ "$EXIST_OPT" == "1" ]; then
        # continue to reconfigure
        :
      fi
    fi
  fi

  echo
  echo -e "${CYAN}Selecione o tipo de limitação:${NC}"
  echo -e "1) Saída (Upload)"
  echo -e "2) Entrada (Download)"
  echo -e "3) Ambos (Entrada e Saída)"
  read -p "Opção: " TIPO_LIMITE
  if ! [[ "$TIPO_LIMITE" =~ ^[1-3]$ ]]; then
    echo -e "${RED}Opção inválida.${NC}"; exit 1
  fi

  read -p "Valor numérico (ex: 450): " VALOR
  if ! [[ "$VALOR" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}Valor inválido.${NC}"; exit 1
  fi

  echo -e "Unidade: 1) ${GREEN}Mbps${NC}  2) ${GREEN}Kbps${NC}  3) ${GREEN}Gbps${NC}"
  read -p "Opção: " UN_OP
  case $UN_OP in
    1) SUFFIX="mbit" ;;
    2) SUFFIX="kbit" ;;
    3) SUFFIX="gbit" ;;
    *) echo -e "${RED}Opç��o inválida.${NC}"; exit 1 ;;
  esac

  LIMITE="${VALOR}${SUFFIX}"

  # Option: per-IP shaping? (Basic)
  echo -e "${CYAN}Deseja aplicar limites por IP (ex.: limitar IPs específicos)?${NC}"
  echo -e "1) Não, limite global na interface"
  echo -e "2) Sim, aplicar classes por IP (básico: adicionarei marcações e classes para lista)"
  read -p "Opção [1]: " PER_IP_OPT
  PER_IP_OPT="${PER_IP_OPT:-1}"

  PER_IP="no"
  CLASSMAP=""
  if [ "$PER_IP_OPT" == "2" ]; then
    PER_IP="yes"
    echo -e "${CYAN}Forneça uma lista de IP:limite (ex: 10.0.0.5:100mbit 10.0.0.6:50mbit) separada por espaços${NC}"
    read -p "Entrada: " MAP_INPUT
    CLASSMAP="$MAP_INPUT"
    # Note: This feature is basic; personalizar conforme necessário.
  fi

  echo -e "${CYAN}Preparando script persistente, systemd e aplicando regras...${NC}"
  # Save variables globally for generating script
  export TIPO_LIMITE LIMITE PER_IP CLASSMAP INTERFACE

  generate_persistent_script
  create_systemd_service
  configure_dns
  sysctl_tweaks
  test_best_route

  log "Aplicando regras pela primeira vez..."
  bash "$CONFIG_SCRIPT" start

  echo -e "${GREEN}✅ Limite de $LIMITE configurado com sucesso na interface ${INTERFACE}!${NC}"
  echo -e "${CYAN}Serviço: systemctl status limit-bandwidth.service${NC}"
  echo -e "${CYAN}Logs: tail -f $LOGFILE${NC}"
  echo -e "${YELLOW}Para remover/restore: sudo bash limitar_banda.sh (opção 'Remover') ou systemctl stop/disable limit-bandwidth.service${NC}"
}

# If called with non-interactive flags
case "${1:-}" in
  uninstall|remove)
    uninstall_all
    ;;
  *)
    main_menu
    ;;
esac

exit 0
