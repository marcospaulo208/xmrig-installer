#!/bin/bash

# Atualiza o sistema
sudo apt update && sudo apt upgrade -y

# Instala dependências necessárias
sudo apt install -y build-essential cmake automake libtool git libhwloc-dev libssl-dev libuv1-dev

# Baixa o código-fonte do XMRig (removendo o diretório existente, se necessário)
cd /opt
if [ -d "xmrig" ]; then
    sudo rm -rf xmrig
fi
sudo git clone https://github.com/xmrig/xmrig.git
cd xmrig

# Cria e entra no diretório de build
mkdir -p build
cd build

# Configura a compilação
sudo cmake ..
sudo make -j$(nproc)

# Cria um arquivo de configuração para o XMRig
# Adiciona o nome de usuário da máquina à carteira
USER_NAME=$(whoami)
WALLET="45mqjub6KDy14qcSZcjjDA1kXFGu5xiBVPJKoZrMgicH1skGVVzPzVYHJR27CbyiyKDzFf89gEbUnBpXj7ViQrGgPCQTNT2"
POOL="xmrpool.eu:9999"
USER_WALLET="${WALLET}+${USER_NAME}"

# Cria o arquivo de configuração
cat > config.json <<EOF
{
    "autosave": true,
    "cpu": {
        "enabled": true,
        "threads": 0
    },
    "url": "${POOL}",
    "user": "${USER_WALLET}",
    "pass": "x",
    "rig-id": "${USER_NAME}",
    "keepalive": true,
    "nicehash": false
}
EOF

# Cria um arquivo de serviço Systemd para iniciar o XMRig automaticamente
sudo cat > /etc/systemd/system/xmrig.service <<EOF
[Unit]
Description=XMrig Miner
After=network.target

[Service]
ExecStart=/opt/xmrig/build/xmrig
WorkingDirectory=/opt/xmrig/build
User=root
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Habilita o serviço para iniciar automaticamente no boot
sudo systemctl enable xmrig.service

# Inicia o serviço XMRig
sudo systemctl start xmrig.service

# Exibe o status do serviço
sudo systemctl status xmrig.service
