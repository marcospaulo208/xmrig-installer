#!/bin/bash
# XMRig Optimized Installer - Version 2.0
# Script otimizado para máxima performance em mineração Monero

set -e  # Para o script em caso de erro

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configurações
POOL="xmrpool.eu:9999"
WALLET="45mqjub6Kdy14qcSZcjjDA1kXFGu5xiBVPJKoZrMgicH1skGVVzPzVYHJR27CbyiyKDzFf89gEbUnBpXj7ViQrGgPCQTNT2"
MINER_USER="xmrig"
INSTALL_DIR="/opt/xmrig"

echo -e "${GREEN}"
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║     XMRig Optimized Installer - Maximum Performance      ║"
echo "║                 Monero Mining Setup                       ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Detecta CPU
CPU_CORES=$(nproc)
CPU_VENDOR=$(lscpu | grep "Vendor ID" | awk '{print $3}' 2>/dev/null || echo "Unknown")
CPU_MODEL=$(lscpu | grep "Model name" | cut -d':' -f2 | xargs 2>/dev/null || echo "Unknown")
THREAD_HINT=$((CPU_CORES * 100 / 100))

echo -e "${BLUE}Detectando Hardware:${NC}"
echo "  CPU Model: $CPU_MODEL"
echo "  CPU Cores: $CPU_CORES"
echo "  CPU Vendor: $CPU_VENDOR"
echo "  Thread Hint: ${THREAD_HINT}%"

# Verifica RAM
TOTAL_RAM=$(free -g | awk '/^Mem:/{print $2}')
echo "  RAM Total: ${TOTAL_RAM}GB"
if [ $TOTAL_RAM -lt 4 ]; then
    echo -e "${YELLOW}  ⚠ Aviso: Mínimo recomendado 4GB para RandomX${NC}"
fi
echo ""

# Atualiza o sistema
echo -e "${GREEN}[1/12] Atualizando sistema...${NC}"
sudo apt update && sudo apt upgrade -y

# Instala dependências necessárias
echo -e "${GREEN}[2/12] Instalando dependências...${NC}"
sudo apt install -y \
    build-essential \
    cmake \
    automake \
    libtool \
    git \
    libhwloc-dev \
    libssl-dev \
    libuv1-dev \
    msr-tools \
    lm-sensors \
    htop \
    curl

# Cria usuário dedicado para mineração
echo -e "${GREEN}[3/12] Criando usuário dedicado...${NC}"
if id "$MINER_USER" &>/dev/null; then
    echo -e "${YELLOW}  Usuário $MINER_USER já existe${NC}"
else
    sudo useradd -r -s /bin/false -m -d $INSTALL_DIR $MINER_USER
    echo -e "${GREEN}  Usuário $MINER_USER criado${NC}"
fi

# Configura MSR para otimização
echo -e "${GREEN}[4/12] Configurando otimizações de CPU...${NC}"
sudo modprobe msr 2>/dev/null || true
echo "msr" | sudo tee -a /etc/modules > /dev/null 2>&1 || true

# Otimizações específicas por fabricante
if [[ $CPU_VENDOR == "AuthenticAMD" ]]; then
    echo -e "${BLUE}  Aplicando otimizações para AMD Ryzen${NC}"
    if command -v wrmsr &> /dev/null; then
        sudo wrmsr -a 0xc0011020 0x400000000000 2>/dev/null || true
    fi
elif [[ $CPU_VENDOR == "GenuineIntel" ]]; then
    echo -e "${BLUE}  Aplicando otimizações para Intel${NC}"
    if command -v wrmsr &> /dev/null; then
        sudo wrmsr -a 0x1a4 0xf 2>/dev/null || true
    fi
fi

# Configura Huge Pages (ESSENCIAL para RandomX)
echo -e "${GREEN}[5/12] Configurando Huge Pages...${NC}"
sudo sysctl -w vm.nr_hugepages=1280 2>/dev/null || true
echo "vm.nr_hugepages=1280" | sudo tee -a /etc/sysctl.conf > /dev/null 2>&1 || true

# Configura limites de memória
sudo cat > /etc/security/limits.d/xmrig.conf <<EOF 2>/dev/null || true
# XMRig memory limits
* soft memlock unlimited
* hard memlock unlimited
* soft stack unlimited
* hard stack unlimited
* soft nproc 1000000
* hard nproc 1000000
EOF

# Desabilita Transparent Huge Pages
echo never | sudo tee /sys/kernel/mm/transparent_hugepage/enabled > /dev/null 2>&1 || true

# Baixa o código-fonte do XMRig
echo -e "${GREEN}[6/12] Baixando código fonte do XMRig...${NC}"
cd /opt
if [ -d "xmrig" ]; then
    sudo rm -rf xmrig
fi
sudo git clone https://github.com/xmrig/xmrig.git
cd xmrig

# Compila o XMRig com otimizações
echo -e "${GREEN}[7/12] Compilando XMRig (isso pode levar alguns minutos)...${NC}"
mkdir -p build
cd build
sudo cmake .. -DCMAKE_BUILD_TYPE=Release -DWITH_MSR=ON
sudo make -j$(nproc)

# Verifica se a compilação foi bem sucedida
if [ -f "/opt/xmrig/build/xmrig" ]; then
    echo -e "${GREEN}  ✅ Compilação concluída com sucesso${NC}"
else
    echo -e "${RED}  ❌ Falha na compilação${NC}"
    exit 1
fi

# Cria arquivo de configuração otimizado
echo -e "${GREEN}[8/12] Criando arquivo de configuração...${NC}"
sudo mkdir -p $INSTALL_DIR/build 2>/dev/null || true

sudo cat > /opt/xmrig/build/config.json <<EOF
{
    "autosave": true,
    "cpu": {
        "enabled": true,
        "huge-pages": true,
        "hw-aes": true,
        "priority": null,
        "max-threads-hint": ${THREAD_HINT},
        "asm": true,
        "argon2-impl": null
    },
    "opencl": false,
    "cuda": false,
    "donate-level": 1,
    "pools": [
        {
            "url": "${POOL}",
            "user": "${WALLET}",
            "pass": "optimized-linux-miner",
            "keepalive": true,
            "tls": true,
            "nicehash": false
        }
    ],
    "print-time": 60,
    "retries": 5,
    "retry-pause": 5,
    "watch": true
}
EOF

# Ajusta permissões
echo -e "${GREEN}[9/12] Configurando permissões...${NC}"
sudo chown -R $MINER_USER:$MINER_USER $INSTALL_DIR
sudo chmod +x /opt/xmrig/build/xmrig

# Cria serviço Systemd otimizado
echo -e "${GREEN}[10/12] Criando serviço systemd...${NC}"
sudo cat > /etc/systemd/system/xmrig.service <<EOF
[Unit]
Description=XMrig Optimized Miner
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${MINER_USER}
Group=${MINER_USER}
ExecStart=/opt/xmrig/build/xmrig -c /opt/xmrig/build/config.json
WorkingDirectory=/opt/xmrig/build
Restart=always
RestartSec=30
StandardOutput=journal
StandardError=journal
LimitMEMLOCK=infinity
LimitNOFILE=1000000
Nice=10
CPUSchedulingPolicy=fifo
CPUSchedulingPriority=99

[Install]
WantedBy=multi-user.target
EOF

# Cria scripts auxiliares
echo -e "${GREEN}[11/12] Criando scripts de monitoramento...${NC}"

# Script de monitoramento
sudo cat > /usr/local/bin/xmrig-monitor <<'EOF'
#!/bin/bash
while true; do
    clear
    echo "=== XMRig Monitor ==="
    echo "Time: $(date)"
    echo ""
    echo "Service Status: $(systemctl is-active xmrig)"
    echo ""
    echo "Last 10 accepted shares:"
    journalctl -u xmrig.service --since "10 minutes ago" | grep "accepted" | tail -10
    echo ""
    echo "Current Hashrate (last minute):"
    journalctl -u xmrig.service --since "1 minute ago" | grep "speed" | tail -1
    echo ""
    echo "CPU Usage:"
    top -bn1 | grep "Cpu(s)" | awk '{print "User: " $2 "%  System: " $4 "%"}'
    echo ""
    echo "Memory Usage:"
    free -h | grep "Mem:"
    echo ""
    echo "Temperature:"
    sensors 2>/dev/null | grep -E "Core|Package|Tctl" | head -3 || echo "  sensors not available"
    echo ""
    echo "Press Ctrl+C to exit"
    sleep 10
done
EOF

sudo chmod +x /usr/local/bin/xmrig-monitor

# Script para logs
sudo cat > /usr/local/bin/xmrig-logs <<'EOF'
#!/bin/bash
journalctl -u xmrig.service -f -n 50
EOF

sudo chmod +x /usr/local/bin/xmrig-logs

# Script para restart
sudo cat > /usr/local/bin/xmrig-restart <<'EOF'
#!/bin/bash
echo "Restarting XMRig miner..."
sudo systemctl restart xmrig
sleep 3
sudo systemctl status xmrig --no-pager
EOF

sudo chmod +x /usr/local/bin/xmrig-restart

# Inicia o serviço
echo -e "${GREEN}[12/12] Iniciando serviço...${NC}"
sudo systemctl daemon-reload
sudo systemctl enable xmrig.service
sudo systemctl start xmrig.service

# Aguarda inicialização
sleep 3

# Exibe o status do serviço
echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              INSTALAÇÃO CONCLUÍDA COM SUCESSO!           ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Status do Serviço:${NC}"
sudo systemctl status xmrig.service --no-pager -l
echo ""
echo -e "${YELLOW}Configuração Aplicada:${NC}"
echo "  Pool: $POOL"
echo "  Wallet: ${WALLET:0:30}..."
echo "  CPU Threads: $CPU_CORES (${THREAD_HINT}%)"
echo "  Huge Pages: Ativado (1280 páginas)"
echo "  MSR Otimizações: Aplicadas para $CPU_VENDOR"
echo ""
echo -e "${YELLOW}Comandos Úteis:${NC}"
echo "  ${GREEN}xmrig-monitor${NC}   - Monitor em tempo real (atualiza a cada 10s)"
echo "  ${GREEN}xmrig-logs${NC}       - Ver logs em tempo real"
echo "  ${GREEN}xmrig-restart${NC}    - Reiniciar o minerador"
echo "  ${GREEN}systemctl status xmrig${NC} - Ver status do serviço"
echo "  ${GREEN}systemctl stop xmrig${NC}   - Parar o minerador"
echo "  ${GREEN}systemctl start xmrig${NC}  - Iniciar o minerador"
echo ""
echo -e "${YELLOW}Verificando Huge Pages:${NC}"
cat /proc/meminfo | grep -i huge
echo ""
echo -e "${GREEN}Para ver os logs agora, execute: xmrig-logs${NC}"
echo -e "${GREEN}Para monitorar o hashrate, execute: xmrig-monitor${NC}"
echo ""
