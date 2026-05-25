#!/bin/bash

# Configurações
INTERFACE="wlan0"

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

show_banner() {
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════╗"
    echo "║         WiFi Client Manager          ║"
    echo "║              (wlan0)                 ║"
    echo "╚══════════════════════════════════════╝"
    echo -e "${NC}"
}

scan_networks() {
    echo -e "${YELLOW}[*] Escaneando redes WiFi...${NC}"
    sudo nmcli device wifi rescan
    sleep 2
    
    echo -e "${GREEN}Redes disponíveis:${NC}"
    nmcli device wifi list | head -20
}

connect_wifi() {
    if [ -z "$1" ] || [ -z "$2" ]; then
        echo -e "${RED}[✗] Uso: $0 connect <SSID> <SENHA>${NC}"
        return 1
    fi
    
    SSID="$1"
    PASSWORD="$2"
    
    echo -e "${YELLOW}[*] Conectando ao WiFi: $SSID${NC}"
    
    if sudo nmcli device wifi connect "$SSID" password "$PASSWORD" ifname $INTERFACE; then
        echo -e "${GREEN}[✓] Conectado com sucesso!${NC}"
        show_status
    else
        echo -e "${RED}[✗] Falha na conexão${NC}"
    fi
}

disconnect_wifi() {
    echo -e "${YELLOW}[*] Desconectando WiFi...${NC}"
    
    ACTIVE_CONNECTION=$(nmcli connection show --active | grep $INTERFACE | awk '{print $1}')
    
    if [ -n "$ACTIVE_CONNECTION" ]; then
        if sudo nmcli connection down "$ACTIVE_CONNECTION"; then
            echo -e "${GREEN}[✓] Desconectado${NC}"
        else
            echo -e "${RED}[✗] Erro ao desconectar${NC}"
        fi
    else
        echo -e "${YELLOW}[!] Nenhuma conexão ativa em $INTERFACE${NC}"
    fi
}

show_status() {
    echo -e "${BLUE}[*] Status da Interface $INTERFACE:${NC}"
    echo "────────────────────────────────────"
    
    # Status da interface
    if ip link show $INTERFACE &>/dev/null; then
        echo -e "${GREEN}[✓] Interface: ATIVA${NC}"
        
        # IP atual
        IP=$(ip addr show $INTERFACE | grep "inet " | awk '{print $2}' | head -1)
        if [ -n "$IP" ]; then
            echo -e "${GREEN}[✓] IP: $IP${NC}"
        fi
        
        # Conexão ativa
        ACTIVE_CONNECTION=$(nmcli connection show --active | grep $INTERFACE)
        if [ -n "$ACTIVE_CONNECTION" ]; then
            SSID=$(echo "$ACTIVE_CONNECTION" | awk '{print $1}')
            echo -e "${GREEN}[✓] Conectado a: $SSID${NC}"
            
            # Qualidade do sinal
            SIGNAL=$(nmcli device wifi | grep "$SSID" | awk '{print $7}' | head -1)
            if [ -n "$SIGNAL" ]; then
                echo -e "${GREEN}[✓] Sinal: $SIGNAL${NC}"
            fi
        else
            echo -e "${YELLOW}[!] Não conectado a nenhuma rede${NC}"
        fi
    else
        echo -e "${RED}[✗] Interface $INTERFACE não encontrada${NC}"
    fi
}

list_saved() {
    echo -e "${BLUE}[*] Conexões WiFi salvas:${NC}"
    nmcli connection show | grep wifi
}

forget_network() {
    if [ -z "$1" ]; then
        echo -e "${RED}[✗] Uso: $0 forget <NOME_CONEXAO>${NC}"
        echo -e "${YELLOW}Use 'saved' para ver conexões salvas${NC}"
        return 1
    fi
    
    CONNECTION_NAME="$1"
    
    echo -e "${YELLOW}[*] Removendo conexão: $CONNECTION_NAME${NC}"
    
    if sudo nmcli connection delete "$CONNECTION_NAME"; then
        echo -e "${GREEN}[✓] Conexão removida${NC}"
    else
        echo -e "${RED}[✗] Erro ao remover conexão${NC}"
    fi
}

show_help() {
    show_banner
    echo -e "${YELLOW}Uso: $0 [comando] [parâmetros]${NC}"
    echo ""
    echo -e "${GREEN}Comandos:${NC}"
    echo "  scan                    - Escanear redes WiFi"
    echo "  connect <SSID> <SENHA>  - Conectar a uma rede"
    echo "  disconnect              - Desconectar"
    echo "  status                  - Ver status da conexão"
    echo "  saved                   - Listar conexões salvas"
    echo "  forget <NOME>           - Esquecer uma rede salva"
    echo "  help                    - Mostrar esta ajuda"
    echo ""
    echo -e "${YELLOW}Exemplos:${NC}"
    echo "  $0 scan"
    echo "  $0 connect \"MinhaRede\" \"minhasenha123\""
    echo "  $0 status"
}

# Menu principal
case "$1" in
    scan)
        show_banner
        scan_networks
        ;;
    connect)
        show_banner
        connect_wifi "$2" "$3"
        ;;
    disconnect)
        show_banner
        disconnect_wifi
        ;;
    status)
        show_banner
        show_status
        ;;
    saved)
        show_banner
        list_saved
        ;;
    forget)
        show_banner
        forget_network "$2"
        ;;
    help|*)
        show_help
        ;;
esac
