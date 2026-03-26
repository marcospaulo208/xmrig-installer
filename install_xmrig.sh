#!/bin/bash
# XMRig Universal Installer - MoneroOcean Optimized
# Detecta automaticamente se é VM ou físico e ajusta otimizações
# Version: 3.0

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configurações
WALLET="48ZGKQyFNHmYkWxHwxC2Wb6Ct5NLgup7vCVjx5aSGm6GRjBT7giVJdLQft7G5NGpBSV8RjWwUTZDPbSW6kfpyGB9B2RVqYv"
POOL_PRIMARY="gulf.moneroocean.stream:10128"
POOL_BACKUP="pool.supportxmr.com:3333"
MINER_USER="xmrig"
INSTALL_DIR="/opt/xmrig"

echo -e "${GREEN}"
echo "╔════════════════════════════════════════════════════════════════════╗"
echo "║     XMRig Universal Installer - MoneroOcean Optimized             ║"
echo "║              Auto-detection for Physical/VM                        ║"
echo "╚════════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# ============================================
# DETECÇÃO DE AMBIENTE
# ============================================

echo -e "${BLUE}[1/15] Detectando ambiente de execução...${NC}"

# Detecta se está em VM
IS_VM=false
if systemd-detect-virt -v 2>/dev/null | grep -qiE "vmware|kvm|virtualbox|xen|qemu"; then
    IS_VM=true
    echo -e "${YELLOW}  ⚠ Ambiente Virtualizado Detectado (VM)${NC}"
    echo -e "${YELLOW}  → MSR otimizações serão ignoradas${NC}"
    echo -e "${YELLOW}  → Prioridade de CPU ajustada${NC}"
else
    echo -e "${GREEN}  ✅ Ambiente Físico Detectado${NC}"
    echo -e "${GREEN}  → Todas otimizações disponíveis${NC}"
fi

# Detecta CPU
CPU_CORES=$(nproc)
CPU_VENDOR=$(lscpu | grep "Vendor ID" | awk '{print $3}' 2>/dev/null || echo "Unknown")
CPU_MODEL=$(lscpu | grep "Model name" | cut -d':' -f2 | xargs 2>/dev/null || echo "Unknown")
THREAD_HINT=100

echo -e "${BLUE}[2/15] Detectando hardware...${NC}"
echo "  CPU Model: $CPU_MODEL"
echo "  CPU Cores: $CPU_CORES"
echo "  CPU Vendor: $CPU_VENDOR"
echo "  Thread Hint: ${THREAD_HINT}%"

# Verifica RAM
TOTAL_RAM=$(free -g | awk '/^Mem:/{print $2}')
echo "  RAM Total: ${TOTAL_RAM}GB"

# Otimização de huge pages baseada na RAM
if [ $TOTAL_RAM -ge 16 ]; then
    HUGE_PAGES=2560
elif [ $TOTAL_RAM -ge 8 ]; then
    HUGE_PAGES=1920
else
    HUGE_PAGES=1280
fi
echo "  Huge Pages: $HUGE_PAGES"

echo ""

# ============================================
# ATUALIZAÇÃO E DEPENDÊNCIAS
# ============================================

echo -e "${GREEN}[3/15] Atualizando sistema...${NC}"
sudo apt update && sudo apt upgrade -y

echo -e "${GREEN}[4/15] Instalando dependências...${NC}"
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
    curl \
    wget \
    numactl

# ============================================
# USUÁRIO DEDICADO
# ============================================

echo -e "${GREEN}[5/15] Criando usuário dedicado...${NC}"
if id "$MINER_USER" &>/dev/null; then
    echo -e "${YELLOW}  Usuário $MINER_USER já existe${NC}"
else
    sudo useradd -r -s /bin/false -m -d $INSTALL_DIR $MINER_USER
    echo -e "${GREEN}  Usuário $MINER_USER criado${NC}"
fi

# ============================================
# OTIMIZAÇÕES DE CPU (APENAS FÍSICO)
# ============================================

if [ "$IS_VM" = false ]; then
    echo -e "${GREEN}[6/15] Configurando otimizações de CPU (físico)...${NC}"
    sudo modprobe msr 2>/dev/null || true
    echo "msr" | sudo tee -a /etc/modules > /dev/null 2>&1 || true

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
else
    echo -e "${YELLOW}[6/15] Pulando otimizações MSR (ambiente virtual)${NC}"
fi

# ============================================
# HUGE PAGES
# ============================================

echo -e "${GREEN}[7/15] Configurando Huge Pages...${NC}"
sudo sysctl -w vm.nr_hugepages=$HUGE_PAGES 2>/dev/null || true
echo "vm.nr_hugepages=$HUGE_PAGES" | sudo tee -a /etc/sysctl.conf > /dev/null 2>&1 || true

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

# ============================================
# COMPILAÇÃO XMRig
# ============================================

echo -e "${GREEN}[8/15] Baixando código fonte do XMRig...${NC}"
cd /opt
if [ -d "xmrig" ]; then
    sudo rm -rf xmrig
fi
sudo git clone https://github.com/xmrig/xmrig.git
cd xmrig

echo -e "${GREEN}[9/15] Compilando XMRig (pode levar alguns minutos)...${NC}"
mkdir -p build
cd build

# Compila com otimizações
if [ "$IS_VM" = false ]; then
    sudo cmake .. -DCMAKE_BUILD_TYPE=Release -DWITH_MSR=ON -DWITH_HWLOC=ON
else
    sudo cmake .. -DCMAKE_BUILD_TYPE=Release -DWITH_HWLOC=ON
fi
sudo make -j$(nproc)

if [ -f "/opt/xmrig/build/xmrig" ]; then
    echo -e "${GREEN}  ✅ Compilação concluída${NC}"
else
    echo -e "${RED}  ❌ Falha na compilação${NC}"
    exit 1
fi

# ============================================
# CONFIGURAÇÃO COM FALLBACK
# ============================================

echo -e "${GREEN}[10/15] Criando arquivo de configuração...${NC}"
sudo mkdir -p $INSTALL_DIR/build

sudo cat > /opt/xmrig/build/config.json <<EOF
{
    "autosave": true,
    "cpu": {
        "enabled": true,
        "huge-pages": true,
        "hw-aes": true,
        "priority": 5,
        "max-threads-hint": ${THREAD_HINT},
        "asm": true,
        "argon2-impl": "AVX2",
        "numa": true
    },
    "opencl": false,
    "cuda": false,
    "donate-level": 1,
    "pools": [
        {
            "url": "${POOL_PRIMARY}",
            "user": "${WALLET}",
            "pass": "universal-miner",
            "keepalive": true,
            "tls": false,
            "nicehash": false
        },
        {
            "url": "${POOL_BACKUP}",
            "user": "${WALLET}",
            "pass": "backup-miner",
            "keepalive": true,
            "tls": false,
            "nicehash": false
        }
    ],
    "print-time": 30,
    "retries": 10,
    "retry-pause": 5,
    "watch": true
}
EOF

# ============================================
# PERMISSÕES
# ============================================

echo -e "${GREEN}[11/15] Configurando permissões...${NC}"
sudo chown -R $MINER_USER:$MINER_USER $INSTALL_DIR
sudo chmod +x /opt/xmrig/build/xmrig

# ============================================
# SERVIÇO SYSTEMD OTIMIZADO
# ============================================

echo -e "${GREEN}[12/15] Criando serviço systemd...${NC}"

# Define prioridade baseada no ambiente
if [ "$IS_VM" = false ]; then
    CPU_POLICY="fifo"
    CPU_PRIORITY=99
    NICE_LEVEL=10
else
    CPU_POLICY="batch"
    CPU_PRIORITY=0
    NICE_LEVEL=15
fi

sudo cat > /etc/systemd/system/xmrig.service <<EOF
[Unit]
Description=XMrig Universal Miner (MoneroOcean)
Documentation=https://github.com/xmrig/xmrig
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
Nice=${NICE_LEVEL}
CPUSchedulingPolicy=${CPU_POLICY}
CPUSchedulingPriority=${CPU_PRIORITY}
IOSchedulingClass=best-effort
IOSchedulingPriority=0
OOMScoreAdjust=-500

[Install]
WantedBy=multi-user.target
EOF

# ============================================
# SCRIPTS DE MONITORAMENTO
# ============================================

echo -e "${GREEN}[13/15] Criando scripts de monitoramento...${NC}"

# Script de monitoramento
sudo cat > /usr/local/bin/xmrig-monitor <<'EOF'
#!/bin/bash
while true; do
    clear
    echo "=== XMRig Universal Monitor ==="
    echo "Time: $(date)"
    echo ""
    echo "Service Status: $(systemctl is-active xmrig)"
    echo ""
    echo "Last 15 accepted shares:"
    journalctl -u xmrig.service --since "15 minutes ago" | grep "accepted" | tail -15
    echo ""
    echo "Current Hashrate:"
    journalctl -u xmrig.service --since "1 minute ago" | grep "speed" | tail -1
    echo ""
    echo "CPU Usage:"
    top -bn1 | grep "Cpu(s)" | awk '{print "User: " $2 "%  System: " $4 "%"}'
    echo ""
    echo "Memory Usage:"
    free -h | grep "Mem:"
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

# Script para status completo
sudo cat > /usr/local/bin/xmrig-status <<'EOF'
#!/bin/bash
echo "=== XMRig Status ==="
echo ""
echo "Service Status:"
systemctl status xmrig --no-pager -l
echo ""
echo "Last 10 accepted shares:"
journalctl -u xmrig.service --since "30 minutes ago" | grep accepted | tail -10
echo ""
echo "Last 3 hashrates:"
journalctl -u xmrig.service --since "30 minutes ago" | grep speed | tail -3
echo ""
echo "Total shares today:"
journalctl -u xmrig.service --since today | grep -c accepted
EOF

sudo chmod +x /usr/local/bin/xmrig-status

# ============================================
# INICIALIZAÇÃO
# ============================================

echo -e "${GREEN}[14/15] Iniciando serviço...${NC}"
sudo systemctl daemon-reload
sudo systemctl enable xmrig.service
sudo systemctl start xmrig.service

sleep 5

# ============================================
# FINALIZAÇÃO
# ============================================

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              INSTALAÇÃO CONCLUÍDA COM SUCESSO!                     ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${YELLOW}Configuração Aplicada:${NC}"
echo "  Pool Primária: $POOL_PRIMARY"
echo "  Pool Backup: $POOL_BACKUP"
echo "  Wallet: ${WALLET:0:35}..."
echo "  CPU Threads: $CPU_CORES (100%)"
echo "  Huge Pages: $HUGE_PAGES páginas"
echo "  Ambiente: $( [ "$IS_VM" = true ] && echo "Virtualizado" || echo "Físico" )"
echo ""

echo -e "${YELLOW}Comandos Úteis:${NC}"
echo "  ${GREEN}xmrig-monitor${NC}   - Monitor em tempo real"
echo "  ${GREEN}xmrig-logs${NC}       - Ver logs em tempo real"
echo "  ${GREEN}xmrig-status${NC}     - Status completo"
echo "  ${GREEN}xmrig-restart${NC}    - Reiniciar minerador"
echo ""

echo -e "${YELLOW}Verificando Huge Pages:${NC}"
cat /proc/meminfo | grep -i huge

echo ""
echo -e "${GREEN}Para ver os logs agora, execute: xmrig-logs${NC}"
echo -e "${GREEN}Para monitorar o hashrate, execute: xmrig-monitor${NC}"
echo ""
