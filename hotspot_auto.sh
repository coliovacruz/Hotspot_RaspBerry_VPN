#!/bin/bash

# Configurações
HOTSPOT_NAME="Hotspot"
INTERFACE="wlan1"
NETWORK="192.168.43.0/24"
GATEWAY="192.168.43.1"
LOG_FILE="/var/log/hotspot_auto.log"
RESERVATION_FILE="/etc/NetworkManager/dnsmasq-shared.d/static-hosts.conf"

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | sudo tee -a $LOG_FILE
}

show_banner() {
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════╗"
    echo "║         HackingLabSec Hotspot        ║"
    echo "║            Auto Control              ║"
    echo "╚══════════════════════════════════════╝"
    echo -e "${NC}"
}

check_interface() {
    # Aguardar até 30 segundos pela interface aparecer
    for i in {1..30}; do
        if ip link show $INTERFACE &>/dev/null; then
            log_message "Interface $INTERFACE encontrada"
            return 0
        fi
        log_message "Aguardando interface $INTERFACE... ($i/30)"
        sleep 1
    done
    
    log_message "Interface $INTERFACE não encontrada após 30 segundos"
    return 1
}

start_hotspot() {
    log_message "Tentando iniciar hotspot..."
    
    # Verificar se NetworkManager está rodando
    if ! systemctl is-active --quiet NetworkManager; then
        log_message "NetworkManager não está ativo, aguardando..."
        sleep 10
    fi
    
    # Recarregar configurações
    sudo nmcli connection reload
    
    # Ativar hotspot
    if sudo nmcli connection up $HOTSPOT_NAME 2>&1 | tee -a $LOG_FILE; then
        log_message "Hotspot iniciado com sucesso!"
        return 0
    else
        log_message "Erro ao iniciar hotspot"
        return 1
    fi
}

stop_hotspot() {
    log_message "Parando hotspot..."
    if sudo nmcli connection down $HOTSPOT_NAME; then
        log_message "Hotspot parado"
        return 0
    else
        log_message "Erro ao parar hotspot"
        return 1
    fi
}

status_hotspot() {
    if nmcli connection show --active | grep -q "$HOTSPOT_NAME"; then
        echo -e "${GREEN}[✓] Status: ATIVO${NC}"
        IP=$(ip addr show $INTERFACE 2>/dev/null | grep "inet " | awk '{print $2}' | head -1)
        if [ -n "$IP" ]; then
            echo -e "${GREEN}[✓] IP: $IP${NC}"
        fi
        return 0
    else
        echo -e "${RED}[✗] Status: INATIVO${NC}"
        return 1
    fi
}

# Funções para gerenciar reservas DHCP
create_reservation_dir() {
    if [ ! -d "/etc/NetworkManager/dnsmasq-shared.d" ]; then
        log_message "Criando diretório de configuração dnsmasq"
        sudo mkdir -p /etc/NetworkManager/dnsmasq-shared.d
    fi
}

add_reservation() {
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
        echo -e "${RED}[✗] Uso: hotspot reserve add <MAC> <IP> <HOSTNAME>${NC}"
        echo -e "${YELLOW}Exemplo: hotspot reserve add aa:bb:cc:dd:ee:ff 192.168.43.10 laptop-admin${NC}"
        return 1
    fi
    
    local MAC="$1"
    local IP="$2"
    local HOSTNAME="$3"
    
    # Validar formato MAC
    if ! echo "$MAC" | grep -qE '^[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}$'; then
        echo -e "${RED}[✗] Formato de MAC inválido${NC}"
        return 1
    fi
    
    # Validar IP na faixa correta
    if ! echo "$IP" | grep -qE '^192\.168\.43\.[0-9]{1,3}$'; then
        echo -e "${RED}[✗] IP deve estar na faixa 192.168.43.x${NC}"
        return 1
    fi
    
    create_reservation_dir
    
    # Verificar se MAC já existe
    if sudo grep -q "$MAC" "$RESERVATION_FILE" 2>/dev/null; then
        echo -e "${YELLOW}[!] MAC $MAC já possui reserva. Substituindo...${NC}"
        sudo sed -i "/$MAC/d" "$RESERVATION_FILE"
    fi
    
    # Verificar se IP já existe para outro MAC
    if sudo grep -q "$IP" "$RESERVATION_FILE" 2>/dev/null && ! sudo grep -q "$MAC.*$IP" "$RESERVATION_FILE" 2>/dev/null; then
        echo -e "${RED}[✗] IP $IP já está reservado para outro dispositivo${NC}"
        return 1
    fi
    
    # Adicionar reserva
    echo "dhcp-host=$MAC,$IP,$HOSTNAME" | sudo tee -a "$RESERVATION_FILE" > /dev/null
    
    echo -e "${GREEN}[✓] Reserva adicionada:${NC}"
    echo -e "  ${YELLOW}MAC:${NC} $MAC"
    echo -e "  ${YELLOW}IP:${NC} $IP"
    echo -e "  ${YELLOW}Hostname:${NC} $HOSTNAME"
    
    log_message "Reserva DHCP adicionada: $MAC -> $IP ($HOSTNAME)"
    restart_hotspot_for_dhcp
}

remove_reservation() {
    if [ -z "$1" ]; then
        echo -e "${RED}[✗] Uso: hotspot reserve remove <MAC_ou_IP>${NC}"
        return 1
    fi
    
    local IDENTIFIER="$1"
    
    if sudo grep -q "$IDENTIFIER" "$RESERVATION_FILE" 2>/dev/null; then
        echo -e "${YELLOW}[*] Removendo reserva para: $IDENTIFIER${NC}"
        sudo sed -i "/$IDENTIFIER/d" "$RESERVATION_FILE"
        echo -e "${GREEN}[✓] Reserva removida${NC}"
        log_message "Reserva DHCP removida: $IDENTIFIER"
        restart_hotspot_for_dhcp
    else
        echo -e "${RED}[✗] Reserva não encontrada para: $IDENTIFIER${NC}"
    fi
}

list_reservations() {
    echo -e "${BLUE}[*] Reservas DHCP configuradas:${NC}"
    echo "──────────────────────────────────────────────────────────"
    
    if [ -f "$RESERVATION_FILE" ] && [ -s "$RESERVATION_FILE" ]; then
        while IFS= read -r line; do
            if [[ $line =~ ^dhcp-host= ]]; then
                # Extrair MAC, IP e hostname
                local RESERVATION=$(echo "$line" | sed 's/dhcp-host=//')
                local MAC=$(echo "$RESERVATION" | cut -d',' -f1)
                local IP=$(echo "$RESERVATION" | cut -d',' -f2)
                local HOSTNAME=$(echo "$RESERVATION" | cut -d',' -f3)
                
                echo -e "  ${YELLOW}$MAC${NC} → ${GREEN}$IP${NC} ${YELLOW}($HOSTNAME)${NC}"
            fi
        done < "$RESERVATION_FILE"
        
        echo ""
        echo -e "${BLUE}Total de reservas:${NC} $(grep -c "^dhcp-host=" "$RESERVATION_FILE" 2>/dev/null || echo "0")"
    else
        echo -e "${YELLOW}[!] Nenhuma reserva configurada${NC}"
    fi
}

reserve_from_connected() {
    if [ -z "$1" ] || [ -z "$2" ]; then
        echo -e "${RED}[✗] Uso: hotspot reserve from-connected <IP> <HOSTNAME>${NC}"
        echo -e "${YELLOW}Exemplo: hotspot reserve from-connected 192.168.43.139 laptop-user${NC}"
        return 1
    fi
    
    local IP="$1"
    local HOSTNAME="$2"
    
    # Encontrar MAC pelo IP na tabela ARP
    local MAC=$(arp -a | grep "$IP" | grep -o '[0-9a-f]\{2\}:[0-9a-f]\{2\}:[0-9a-f]\{2\}:[0-9a-f]\{2\}:[0-9a-f]\{2\}:[0-9a-f]\{2\}')
    
    if [ -z "$MAC" ]; then
        echo -e "${RED}[✗] Não foi possível encontrar MAC para IP $IP${NC}"
        echo -e "${YELLOW}Certifique-se de que o dispositivo está conectado${NC}"
        return 1
    fi
    
    echo -e "${GREEN}[✓] MAC encontrado: $MAC${NC}"
    add_reservation "$MAC" "$IP" "$HOSTNAME"
}

show_clients_with_reservations() {
    echo -e "${BLUE}[*] Dispositivos Conectados:${NC}"
    echo "──────────────────────────────────────────────────────────"
    
    # ARP table com indicação de reservas
    arp -a | grep -E "192\.168\.43\." | grep -v incomplete | while read line; do
        local IP=$(echo "$line" | grep -o '192\.168\.43\.[0-9]*')
        local MAC=$(echo "$line" | grep -o '[0-9a-f]\{2\}:[0-9a-f]\{2\}:[0-9a-f]\{2\}:[0-9a-f]\{2\}:[0-9a-f]\{2\}:[0-9a-f]\{2\}')
        
        # Verificar se tem reserva
        if [ -f "$RESERVATION_FILE" ] && sudo grep -q "$MAC" "$RESERVATION_FILE" 2>/dev/null; then
            local HOSTNAME=$(sudo grep "$MAC" "$RESERVATION_FILE" | cut -d',' -f3)
            echo -e "  ${GREEN}[RESERVADO]${NC} ${YELLOW}IP:${NC} $IP ${YELLOW}MAC:${NC} $MAC ${YELLOW}→${NC} ${GREEN}$HOSTNAME${NC}"
        else
            echo -e "  ${YELLOW}[DINÂMICO]${NC}  ${YELLOW}IP:${NC} $IP ${YELLOW}MAC:${NC} $MAC"
        fi
    done
    
    echo ""
    echo -e "${BLUE}Para reservar um IP dinâmico:${NC}"
    echo -e "${YELLOW}hotspot reserve from-connected <IP> <hostname>${NC}"
}

restart_hotspot_for_dhcp() {
    echo -e "${YELLOW}[*] Aplicando mudanças nas reservas DHCP...${NC}"
    
    # Recarregar configurações
    sudo nmcli connection reload
    
    # Restart do hotspot
    sudo nmcli connection down $HOTSPOT_NAME 2>/dev/null
    sleep 3
    
    if sudo nmcli connection up $HOTSPOT_NAME; then
        echo -e "${GREEN}[✓] Hotspot reiniciado, reservas aplicadas${NC}"
        log_message "Hotspot reiniciado para aplicar reservas DHCP"
    else
        echo -e "${RED}[✗] Erro ao reiniciar hotspot${NC}"
        log_message "Erro ao reiniciar hotspot para reservas DHCP"
    fi
}

manage_reservations() {
    case "$1" in
        add)
            add_reservation "$2" "$3" "$4"
            ;;
        remove)
            remove_reservation "$2"
            ;;
        list)
            list_reservations
            ;;
        from-connected)
            reserve_from_connected "$2" "$3"
            ;;
        quick-setup)
            quick_setup_known_devices
            ;;
        *)
            echo -e "${YELLOW}Uso: hotspot reserve [comando]${NC}"
            echo ""
            echo -e "${GREEN}Comandos de reserva:${NC}"
            echo "  add <MAC> <IP> <HOST>      - Adicionar reserva DHCP"
            echo "  remove <MAC_ou_IP>         - Remover reserva"
            echo "  list                       - Listar reservas"
            echo "  from-connected <IP> <HOST> - Reservar IP de dispositivo conectado"
            echo "  quick-setup                - Configurar dispositivos conhecidos"
            echo ""
            echo -e "${YELLOW}Exemplos:${NC}"
            echo "  hotspot reserve add aa:bb:cc:dd:ee:ff 192.168.43.10 laptop"
            echo "  hotspot reserve from-connected 192.168.43.139 smartphone"
            echo "  hotspot reserve list"
            echo "  hotspot reserve quick-setup"
            ;;
    esac
}

quick_setup_known_devices() {
    echo -e "${BLUE}[*] Configuração rápida para dispositivos conhecidos:${NC}"
    echo "──────────────────────────────────────────────────────────"
    
    # Adicione aqui os MACs e IPs dos seus dispositivos conhecidos
    # Formato: ["MAC_DO_DISPOSITIVO"]="IP,HOSTNAME"
    # Use: hotspot clients para ver os MACs dos dispositivos conectados
    declare -A KNOWN_DEVICES=(
        ["aa:bb:cc:dd:ee:01"]="192.168.43.10,device-1"
        ["aa:bb:cc:dd:ee:02"]="192.168.43.11,device-2"
        ["aa:bb:cc:dd:ee:03"]="192.168.43.12,device-3"
        ["aa:bb:cc:dd:ee:04"]="192.168.43.13,device-4"
        ["aa:bb:cc:dd:ee:05"]="192.168.43.14,device-5"
        ["aa:bb:cc:dd:ee:06"]="192.168.43.15,device-6"
    )
    
    create_reservation_dir
    
    for MAC in "${!KNOWN_DEVICES[@]}"; do
        local IP_HOST="${KNOWN_DEVICES[$MAC]}"
        local IP=$(echo "$IP_HOST" | cut -d',' -f1)
        local HOSTNAME=$(echo "$IP_HOST" | cut -d',' -f2)
        
        # Verificar se já existe reserva para este MAC
        if sudo grep -q "$MAC" "$RESERVATION_FILE" 2>/dev/null; then
            echo -e "${YELLOW}[SKIP] $MAC já possui reserva${NC}"
        else
            echo "dhcp-host=$MAC,$IP,$HOSTNAME" | sudo tee -a "$RESERVATION_FILE" > /dev/null
            echo -e "${GREEN}[ADD] $MAC → $IP ($HOSTNAME)${NC}"
            log_message "Reserva rápida adicionada: $MAC -> $IP ($HOSTNAME)"
        fi
    done
    
    echo ""
    echo -e "${GREEN}[✓] Configuração rápida concluída${NC}"
    restart_hotspot_for_dhcp
}

show_clients() {
    show_clients_with_reservations
}

monitor_clients() {
    echo -e "${BLUE}[*] Monitoramento em tempo real (Ctrl+C para sair)${NC}"
    
    while true; do
        clear
        show_banner
        echo -e "${BLUE}[$(date '+%H:%M:%S')] Monitorando...${NC}"
        echo ""
        status_hotspot
        echo ""
        show_clients
        echo ""
        list_reservations
        sleep 5
    done
}

# Função principal para boot
auto_start() {
    log_message "=== Iniciando script de auto-start ==="
    
    # Verificar se interface existe
    if ! check_interface; then
        log_message "Interface $INTERFACE não disponível, saindo..."
        exit 0
    fi
    
    # Aguardar NetworkManager
    sleep 5
    
    # Iniciar hotspot
    if start_hotspot; then
        log_message "Hotspot auto-iniciado com sucesso"
    else
        log_message "Falha ao auto-iniciar hotspot"
        exit 1
    fi
}

show_help() {
    show_banner
    echo -e "${YELLOW}Uso: $0 [comando] [parâmetros]${NC}"
    echo ""
    echo -e "${GREEN}Comandos principais:${NC}"
    echo "  auto      - Auto-start (usado no boot)"
    echo "  start     - Iniciar hotspot manualmente"
    echo "  stop      - Parar hotspot"
    echo "  restart   - Reiniciar hotspot"
    echo "  status    - Ver status"
    echo "  clients   - Ver dispositivos conectados"
    echo "  monitor   - Monitorar em tempo real"
    echo "  logs      - Ver logs"
    echo ""
    echo -e "${GREEN}Comandos de reserva DHCP:${NC}"
    echo "  reserve add <MAC> <IP> <HOST>      - Adicionar reserva"
    echo "  reserve remove <MAC_ou_IP>         - Remover reserva"
    echo "  reserve list                       - Listar reservas"
    echo "  reserve from-connected <IP> <HOST> - Reservar IP conectado"
    echo "  reserve quick-setup                - Configurar dispositivos conhecidos"
    echo ""
    echo -e "${YELLOW}Exemplos:${NC}"
    echo "  $0 clients"
    echo "  $0 reserve from-connected 192.168.43.139 smartphone"
    echo "  $0 reserve quick-setup"
    echo "  $0 reserve list"
    echo ""
}

# Menu principal
case "$1" in
    auto)
        auto_start
        ;;
    start)
        show_banner
        if check_interface; then
            start_hotspot
        else
            echo -e "${RED}Interface $INTERFACE não disponível${NC}"
        fi
        ;;
    stop)
        show_banner
        stop_hotspot
        ;;
    restart)
        show_banner
        stop_hotspot
        sleep 2
        if check_interface; then
            start_hotspot
        fi
        ;;
    status)
        show_banner
        status_hotspot
        ;;
    clients)
        show_banner
        show_clients
        ;;
    monitor)
        monitor_clients
        ;;
    reserve)
        show_banner
        manage_reservations "$2" "$3" "$4" "$5"
        ;;
    logs)
        echo -e "${BLUE}[*] Logs do hotspot:${NC}"
        sudo tail -f $LOG_FILE
        ;;
    help|*)
        show_help
        ;;
esac
