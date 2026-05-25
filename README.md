# 📡 HackingLabSec Hotspot

Sistema completo de hotspot WiFi para Raspberry Pi com Kali Linux — com auto-inicialização, reservas DHCP por MAC, integração com ProtonVPN e múltiplos modos de operação.

---

## 📋 Índice

- [Visão Geral](#-visão-geral)
- [Equipamentos Utilizados](#-equipamentos-utilizados)
- [Arquitetura do Sistema](#-arquitetura-do-sistema)
- [Pré-requisitos](#-pré-requisitos)
- [Passo a Passo de Montagem](#-passo-a-passo-de-montagem)
  - [1. Preparar o sistema](#1-preparar-o-sistema)
  - [2. Criar estrutura de diretórios](#2-criar-estrutura-de-diretórios)
  - [3. Instalar os scripts](#3-instalar-os-scripts)
  - [4. Configurar o hotspot no NetworkManager](#4-configurar-o-hotspot-no-networkmanager)
  - [5. Configurar reservas DHCP](#5-configurar-reservas-dhcp)
  - [6. Configurar auto-inicialização](#6-configurar-auto-inicialização)
  - [7. Configurar aliases](#7-configurar-aliases)
  - [8. Configurar integração com VPN](#8-configurar-integração-com-vpn)
- [Modos de Operação](#-modos-de-operação)
- [Comandos de Uso](#-comandos-de-uso)
- [Estrutura de Arquivos](#-estrutura-de-arquivos)
- [Resolução de Problemas](#-resolução-de-problemas)
- [Logs e Monitoramento](#-logs-e-monitoramento)
- [Licença](#-licença)

---

## 🔍 Visão Geral

Este projeto transforma um Raspberry Pi em um hotspot WiFi controlado por script, com recursos avançados como:

- **Auto-inicialização inteligente** — inicia o hotspot no boot apenas se a interface `wlan1` estiver disponível
- **Reservas DHCP por MAC** — IPs fixos para dispositivos conhecidos
- **Integração com ProtonVPN** — clientes do hotspot navegam anonimizados via VPN
- **Modo isolado** — hotspot sem acesso à internet para os clientes (somente rede local)
- **Monitoramento em tempo real** — visualização de dispositivos conectados e status de reservas
- **Dois scripts independentes** — um para o hotspot (`wlan1`) e outro para a conexão cliente (`wlan0`)

---

## 🛠️ Equipamentos Utilizados

| Equipamento | Descrição |
|---|---|
| **Raspberry Pi** | Qualquer modelo com porta USB e WiFi integrado (testado com Kali Linux) |
| **Alfa AWUS036ACM** | Adaptador USB WiFi dual-band com suporte a **modo AP (Access Point)** — chipset MT7612U, usado como `wlan1` para o hotspot |
| **WiFi integrado** | Interface nativa do Raspberry Pi (`wlan0`) — usada para conexão cliente com a internet |
| **Cartão microSD** | Com Kali Linux instalado |
| **Fonte de alimentação** | Compatível com o modelo do Raspberry Pi |

> ⚠️ **Importante:** O adaptador WiFi USB **precisa suportar modo AP**. Verifique com `iw list | grep -A 10 "Supported interface modes"` e confirme que `AP` aparece na lista.

### Adaptadores com suporte a AP testados

- **Alfa AWUS036ACM** (chipset MT7612U) ✅ — usado neste projeto
- Alfa AWUS036ACH (chipset RTL8812AU)
- TP-Link TL-WN722N v1 (chipset AR9271)
- Panda PAU06 (chipset RT5372)
- Alfa AWUS036NHA (chipset AR9271)

---

## 🏗️ Arquitetura do Sistema

```
┌─────────────────────────────────────────────────┐
│               Raspberry Pi (Kali)               │
│                                                 │
│  wlan0 ──────────► Internet (WiFi cliente)      │
│  wlan1 ──────────► Hotspot (192.168.43.1/24)    │
│  tun0  ──────────► ProtonVPN (opcional)         │
│                                                 │
│  Modos:                                         │
│    Normal  → wlan1 NAT via wlan0                │
│    VPN     → wlan1 NAT via tun0 (ProtonVPN)     │
│    Isolado → wlan1 sem acesso à internet        │
└─────────────────────────────────────────────────┘
         │
         ▼
   Dispositivos clientes do lab (192.168.43.x)
```

---

## 📦 Pré-requisitos

- Kali Linux instalado no Raspberry Pi
- Duas interfaces WiFi disponíveis (`wlan0` e `wlan1`)
- Acesso root / sudo
- NetworkManager instalado
- (Opcional) ProtonVPN com arquivos `.ovpn`

---

## 🚀 Passo a Passo de Montagem

### 1. Preparar o sistema

```bash
# Atualizar o sistema
sudo apt update && sudo apt upgrade -y

# Instalar dependências
sudo apt install network-manager net-tools nmap -y

# Parar e desabilitar serviços conflitantes (se existirem)
sudo systemctl stop hostapd dnsmasq 2>/dev/null
sudo systemctl disable hostapd dnsmasq 2>/dev/null

# Garantir que NetworkManager está ativo
sudo systemctl enable NetworkManager
sudo systemctl start NetworkManager

# Verificar se as duas interfaces estão disponíveis
ip link show wlan0
ip link show wlan1
```

> Se `wlan1` não aparecer, conecte o adaptador USB e verifique com `lsusb` e `dmesg | tail -20`.

---

### 2. Criar estrutura de diretórios

```bash
mkdir -p ~/Documents/Ferramentas/wifi/MeuHotspot
mkdir -p ~/Documents/Ferramentas/VPN
cd ~/Documents/Ferramentas/wifi/MeuHotspot
```

---

### 3. Instalar os scripts

**Arquivos deste repositório:**

```
hackinglabsec-hotspot/
├── hotspot_auto.sh       # Script principal — gerencia o hotspot (wlan1)
├── wifi_client.sh        # Script cliente — gerencia conexão WiFi (wlan0)
└── README.md             # Esta documentação
```

Clone este repositório ou copie os arquivos manualmente:

```bash
# Via git — clone direto no diretório criado na etapa anterior
cd ~/Documents/Ferramentas/wifi/MeuHotspot
git clone https://github.com/coliovacruz/Hotspot_RaspBerry_VPN.git .

# Dar permissão de execução
chmod +x hotspot_auto.sh
chmod +x wifi_client.sh
```

---

### 4. Configurar o hotspot no NetworkManager

Crie ou edite o arquivo de conexão:

```bash
sudo nano /etc/NetworkManager/system-connections/Hotspot.nmconnection
```

> 💡 Gere um UUID único para sua instalação com `uuidgen` e substitua o valor abaixo.

Conteúdo:

```ini
[connection]
id=Hotspot
uuid=25f6f7b7-3afb-49c2-a620-ad0fc1582cf8
type=wifi
autoconnect=false
interface-name=wlan1

[wifi]
band=bg
channel=7
mode=ap
ssid=MUDE_PARA_SEU_SSID          # ⚠️ Altere para o nome da sua rede

[wifi-security]
group=ccmp;
key-mgmt=wpa-psk
pairwise=ccmp;
proto=rsn;
psk=MUDE_PARA_SUA_SENHA          # ⚠️ Altere para uma senha forte (mín. 12 caracteres)

[ipv4]
address1=192.168.43.1/24
dns-search=
method=shared

[ipv6]
method=ignore
```

```bash
# Ajustar permissões (obrigatório para o NetworkManager)
sudo chmod 600 /etc/NetworkManager/system-connections/Hotspot.nmconnection

# Recarregar configurações
sudo nmcli connection reload

# Testar
sudo nmcli connection up Hotspot
```

---

### 5. Configurar reservas DHCP

Crie o diretório e arquivo de reservas estáticas:

```bash
sudo mkdir -p /etc/NetworkManager/dnsmasq-shared.d/
sudo nano /etc/NetworkManager/dnsmasq-shared.d/static-hosts.conf
```

Formato:

```
# dhcp-host=MAC,IP,HOSTNAME
dhcp-host=aa:bb:cc:dd:ee:01,192.168.43.10,laptop-admin
dhcp-host=aa:bb:cc:dd:ee:02,192.168.43.11,smartphone-user
dhcp-host=aa:bb:cc:dd:ee:03,192.168.43.12,tablet-guest
```

> IPs fixos recomendados: faixa `192.168.43.10–19` (fora do DHCP dinâmico).

Após editar, reinicie o hotspot:

```bash
~/Documents/Ferramentas/wifi/MeuHotspot/hotspot_auto.sh restart
```

> Os aliases serão configurados na etapa 7. Após isso, basta usar `hotspot restart`.

---

### 6. Configurar auto-inicialização

#### Como funciona o fluxo de boot

```
Raspberry Pi liga
        │
        ▼
NetworkManager sobe
        │
        ▼
hotspot-auto.service dispara
        │
        ▼
wlan1 (Alfa) disponível?
       │              │
      SIM             NÃO
       │               └──► Boot normal, sem hotspot
       ▼
Hotspot sobe em wlan1
(SSID visível para conexão)
        │
        ▼
wlan0 (interna) já tem rede salva e conhecida?
       │              │
      SIM             NÃO
       │               └──► Hotspot ativo, mas SEM internet nos clientes
       │                    └──► Usuário conecta no hotspot via Wi-Fi
       │                         └──► Acessa o Pi via SSH
       │                              └──► Roda: wifi connect "Rede" "senha"
       │                                   └──► wlan0 conecta → internet liberada
       ▼
wlan0 conectada → clientes com internet
```

> 📌 **Pré-requisito:** O acesso via SSH pelo hotspot pressupõe que o servidor SSH já esteja habilitado no Raspberry Pi (`openssh-server` instalado e `sshd` ativo).

#### Habilitar o serviço de auto-inicialização

```bash
sudo nano /etc/systemd/system/hotspot-auto.service
```

```ini
[Unit]
Description=HackingLabSec Hotspot Auto Start
After=NetworkManager.service
Wants=NetworkManager.service

[Service]
Type=oneshot
User=root
ExecStart=/home/kali/Documents/Ferramentas/wifi/MeuHotspot/hotspot_auto.sh auto
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable hotspot-auto.service
```

#### Habilitar o servidor SSH (para acesso remoto via hotspot)

```bash
sudo systemctl enable ssh
sudo systemctl start ssh

# Confirmar que está rodando
sudo systemctl status ssh
```

#### Como acessar o Pi via SSH pelo hotspot

Quando o Pi estiver em um local com rede desconhecida, o fluxo é:

**1.** Conecte seu dispositivo no hotspot (SSID configurado na etapa 4)

**2.** Acesse o Pi via SSH — o IP do gateway é sempre fixo:

```bash
ssh kali@192.168.43.1
```

**3.** Verifique quais redes estão disponíveis:

```bash
wifi scan
```

**4.** Conecte a interface interna (`wlan0`) à rede desejada:

```bash
wifi connect "NomeDaRede" "senha123"
```

**5.** Confirme que `wlan0` conectou e a internet está disponível para os clientes:

```bash
wifi status
ping -c 3 8.8.8.8
```

> A partir desse momento os clientes do hotspot já têm acesso à internet — sem precisar reiniciar nada.

---

### 7. Configurar aliases

Para Zsh (padrão no Kali):

```bash
echo 'alias hotspot="~/Documents/Ferramentas/wifi/MeuHotspot/hotspot_auto.sh"' >> ~/.zshrc
echo 'alias wifi="~/Documents/Ferramentas/wifi/MeuHotspot/wifi_client.sh"' >> ~/.zshrc
source ~/.zshrc
```

Para Bash:

```bash
echo 'alias hotspot="~/Documents/Ferramentas/wifi/MeuHotspot/hotspot_auto.sh"' >> ~/.bashrc
echo 'alias wifi="~/Documents/Ferramentas/wifi/MeuHotspot/wifi_client.sh"' >> ~/.bashrc
source ~/.bashrc
```

---

### 8. Configurar integração com ProtonVPN

> Esta etapa é **opcional**. O hotspot funciona normalmente sem VPN. Configure apenas se quiser rotear o tráfego dos clientes via ProtonVPN.

#### 8.1 Criar conta no ProtonVPN

1. Acesse **[protonvpn.com](https://protonvpn.com)** e crie uma conta (plano Free já funciona)
2. Faça login no painel em **[account.proton.me](https://account.proton.me)**

#### 8.2 Baixar os arquivos `.ovpn`

1. No painel do ProtonVPN, vá em **Downloads → OpenVPN configuration files**
2. Selecione:
   - **Platform**: Linux
   - **Protocol**: TCP (mais estável) ou UDP (mais rápido)
   - **Config file**: escolha o servidor desejado (ex: `us-co-21`, `br-sao-01`)
3. Baixe os arquivos `.ovpn` e transfira para o Raspberry Pi:

```bash
# Crie o diretório para os arquivos VPN
mkdir -p ~/Documents/Ferramentas/VPN

# Copie os .ovpn para lá (via scp, pendrive, ou download direto)
# Exemplo com scp a partir de outro computador:
# scp *.ovpn kali@IP_DO_PI:~/Documents/Ferramentas/VPN/
```

#### 8.3 Instalar dependências do OpenVPN

```bash
sudo apt install openvpn resolvconf -y

# Verificar se o update-resolv-conf está presente (usado pelo hook de DNS)
ls /etc/openvpn/update-resolv-conf
```

> Se o arquivo não existir: `sudo ln -s /usr/share/openvpn/contrib/pull-resolv-conf/client.up /etc/openvpn/update-resolv-conf`

#### 8.4 Criar o hook de integração com o hotspot

O hook é um script chamado automaticamente pelo OpenVPN quando a VPN sobe ou cai. Ele garante que os clientes do hotspot continuem com internet roteada via VPN.

```bash
sudo nano /etc/openvpn/hotspot-vpn-hook.sh
```

```bash
#!/bin/bash

LOG="/var/log/hotspot_auto.log"
timestamp() { date '+%Y-%m-%d %H:%M:%S'; }

echo "$(timestamp) - hook chamado: script_type=$script_type dev=$dev" >> $LOG

case "$script_type" in
    up)
        # Manter DNS funcionando
        /etc/openvpn/update-resolv-conf "$@"

        # Redirecionar tráfego do hotspot via VPN
        iptables -t nat -A POSTROUTING -o "$dev" -j MASQUERADE
        sysctl -w net.ipv4.ip_forward=1

        echo "$(timestamp) - VPN UP: hotspot redirecionado via $dev" >> $LOG
        ;;
    down)
        iptables -t nat -D POSTROUTING -o "$dev" -j MASQUERADE 2>/dev/null || true

        # Restaurar DNS
        /etc/openvpn/update-resolv-conf "$@"

        echo "$(timestamp) - VPN DOWN: hotspot restaurado" >> $LOG
        ;;
esac
```

```bash
sudo chmod +x /etc/openvpn/hotspot-vpn-hook.sh
```

#### 8.5 Habilitar ip_forward permanentemente

```bash
echo "net.ipv4.ip_forward=1" | sudo tee /etc/sysctl.d/99-forward.conf
sudo sysctl -p /etc/sysctl.d/99-forward.conf

# Confirmar que está ativo (deve retornar 1)
cat /proc/sys/net/ipv4/ip_forward
```

#### 8.6 Criar alias para o OpenVPN

O alias injeta o hook automaticamente em qualquer `.ovpn`, sem precisar editar cada arquivo:

```bash
# Para Zsh (padrão no Kali)
echo "alias openvpn='sudo openvpn --script-security 2 --up /etc/openvpn/hotspot-vpn-hook.sh --down /etc/openvpn/hotspot-vpn-hook.sh --config'" >> ~/.zshrc
source ~/.zshrc
```

```bash
# Para Bash
echo "alias openvpn='sudo openvpn --script-security 2 --up /etc/openvpn/hotspot-vpn-hook.sh --down /etc/openvpn/hotspot-vpn-hook.sh --config'" >> ~/.bashrc
source ~/.bashrc
```

#### 8.7 Testar a integração

```bash
# Conectar a VPN (hotspot já deve estar ativo)
openvpn ~/Documents/Ferramentas/VPN/NOME_DO_ARQUIVO.ovpn

# Em outro terminal, verificar se o hook rodou
tail -f /var/log/hotspot_auto.log

# Verificar se o tráfego sai pelo tun0
ip route | grep default

# Confirmar IP público dos clientes (deve ser o IP do ProtonVPN)
curl -s https://ifconfig.me
```

> ⚠️ **Nota:** O ProtonVPN bloqueia ICMP por padrão — `ping` não funciona mas navegação sim. Use `curl -s https://ifconfig.me` para testar.

#### 8.8 Trocar de servidor VPN

Basta pressionar `Ctrl+C` para desconectar e conectar outro arquivo:

```bash
openvpn ~/Documents/Ferramentas/VPN/br-sao-01.protonvpn.tcp.ovpn
openvpn ~/Documents/Ferramentas/VPN/us-ny-10.protonvpn.tcp.ovpn
```

O hook funciona com qualquer arquivo `.ovpn` do ProtonVPN automaticamente.

---

## ⚙️ Modos de Operação

O hotspot opera em modo único — NAT via `wlan0`. A VPN é independente e opcional.

### Cenários de uso

| Hotspot | VPN | Como ativar |
|---|---|---|
| ✅ | ✅ | `hotspot start` + `openvpn arquivo.ovpn` (terminal separado) |
| ✅ | ❌ | `hotspot start` (sem VPN) |
| ❌ | ✅ | Só `openvpn arquivo.ovpn` (Pi navega anonimizado, sem hotspot) |
| ❌ | ❌ | Uso normal sem hotspot |

---

## 🎮 Comandos de Uso

### Hotspot (`wlan1`)

```bash
hotspot status                          # Status do hotspot
hotspot start                           # Iniciar hotspot
hotspot stop                            # Parar
hotspot restart                         # Reiniciar
hotspot clients                         # Dispositivos conectados (com status de reserva)
hotspot monitor                         # Monitoramento em tempo real (Ctrl+C para sair)
hotspot logs                            # Ver logs do sistema
hotspot help                            # Ajuda

# Reservas DHCP (IPs fixos por MAC)
hotspot reserve list                                        # Listar reservas
hotspot reserve add aa:bb:cc:dd:ee:ff 192.168.43.10 nome   # Adicionar reserva
hotspot reserve remove aa:bb:cc:dd:ee:ff                    # Remover reserva
hotspot reserve from-connected 192.168.43.139 nome          # Reservar IP de dispositivo já conectado
hotspot reserve quick-setup                                 # Setup rápido para dispositivos conhecidos
hotspot reserve help                                        # Ajuda sobre reservas
```

### WiFi Cliente (`wlan0`)

```bash
wifi scan                               # Escanear redes disponíveis
wifi connect "NomeRede" "senha123"      # Conectar a uma rede
wifi status                             # Status da conexão
wifi disconnect                         # Desconectar
wifi saved                              # Redes salvas
wifi forget "NomeConexao"              # Esquecer rede salva
wifi help                               # Ajuda
```

### VPN (ProtonVPN)

```bash
openvpn ~/Documents/Ferramentas/VPN/us-co-21-tor.protonvpn.tcp.ovpn
```

> Com o alias configurado, o hook é aplicado automaticamente — não é necessário passar flags extras.

---

## 📁 Estrutura de Arquivos

```
~/Documents/Ferramentas/wifi/MeuHotspot/
├── hotspot_auto.sh                   # Script principal do hotspot
└── wifi_client.sh                    # Script de conexão WiFi cliente

~/Documents/Ferramentas/VPN/
└── *.ovpn                            # Arquivos de configuração ProtonVPN

/etc/NetworkManager/system-connections/
└── Hotspot.nmconnection              # Configuração do hotspot (NetworkManager)

/etc/NetworkManager/dnsmasq-shared.d/
└── static-hosts.conf                 # Reservas DHCP (IPs fixos por MAC)

/etc/openvpn/
└── hotspot-vpn-hook.sh               # Hook VPN (up/down)

/etc/systemd/system/
└── hotspot-auto.service              # Serviço de auto-inicialização

/etc/sysctl.d/
└── 99-forward.conf                   # ip_forward permanente

/var/log/
└── hotspot_auto.log                  # Log do sistema
```

---

## 🔍 Informações da Rede

| Parâmetro | Valor |
|---|---|
| SSID | `MUDE_PARA_SEU_SSID` ⚠️ |
| Senha | `MUDE_PARA_SUA_SENHA` ⚠️ |
| IP Gateway | `192.168.43.1` |
| Faixa DHCP dinâmica | `192.168.43.20–254` |
| Faixa para IPs fixos | `192.168.43.10–19` |
| Interface hotspot | `wlan1` |
| Interface cliente | `wlan0` |
| Canal | 7 |
| Segurança | WPA2-PSK (CCMP) |

---

## 🛠️ Resolução de Problemas

### Hotspot não inicia automaticamente

```bash
sudo systemctl status hotspot-auto.service
sudo journalctl -u hotspot-auto.service -f
ip link show wlan1
hotspot start
```

### Interface wlan1 não encontrada

```bash
ip link show           # Listar todas as interfaces
iwconfig               # Interfaces WiFi
lsusb                  # Verificar se o adaptador USB foi detectado
dmesg | tail -20       # Verificar mensagens de driver
```

### Dispositivos se desconectam com frequência

```bash
iwconfig wlan1
sudo iwconfig wlan1 power off       # Desabilitar power save
```

### Clientes sem internet após conectar VPN

```bash
# Verificar rota padrão
ip route | grep default

# Verificar se NAT foi criado no tun0
sudo iptables -t nat -L POSTROUTING -v -n

# Aplicar manualmente se necessário
sudo sysctl -w net.ipv4.ip_forward=1
sudo iptables -t nat -A POSTROUTING -o tun0 -j MASQUERADE
```

> ⚠️ O ProtonVPN bloqueia ICMP por padrão — `ping` não funciona mas navegação sim. Teste com `curl -s https://ifconfig.me`.

### Problemas de conectividade geral

```bash
ip route
ping -c 4 8.8.8.8
sudo iptables -L -n -v
sudo journalctl -u NetworkManager -f
```

---

## 📊 Logs e Monitoramento

### Arquivos de log

| Arquivo | Conteúdo |
|---|---|
| `/var/log/hotspot_auto.log` | Log principal do script (inicialização, erros, eventos VPN) |
| `sudo journalctl -u NetworkManager` | Logs do NetworkManager |
| `sudo journalctl -u hotspot-auto.service` | Logs do serviço de auto-inicialização |

### Comandos de monitoramento

```bash
hotspot logs                                    # Log em tempo real
hotspot clients                                 # Dispositivos conectados
hotspot monitor                                 # Monitor completo
hotspot status                                  # Status geral
ip addr show wlan0 wlan1                        # Status das interfaces
nmcli connection show --active                  # Conexões ativas
nmcli device status                             # Dispositivos gerenciados
sudo netstat -tulpn | grep -E "(53|67|68)"      # Processos de rede (DNS/DHCP)
```

---

## 📄 Licença

Este projeto é fornecido **"como está"** para fins educacionais e de laboratório. Use com responsabilidade.

---

**Versão**: 2.0  
**Compatibilidade**: Kali Linux · Raspberry Pi  
**Última atualização**: Maio 2026
