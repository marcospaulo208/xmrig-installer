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

# Cria o arquivo de configuração para o XMRig
POOL="xmrpool.eu:9999"
WALLET="45mqjub6Kdy14qcSZcjjDA1kXFGu5xiBVPJKoZrMgicH1skGVVzPzVYHJR27CbyiyKDzFf89gEbUnBpXj7ViQrGgPCQTNT2"

# Cria o arquivo de configuração em /opt/xmrig/build/config.json
sudo cat > /opt/xmrig/build/config.json <<EOF
{
    "autosave": true,
    "cpu": true,
    "opencl": false,
    "cuda": false,
    "pools": [
        {
            "url": "${POOL}",
            "user": "${WALLET}",
            "keepalive": true,
            "tls": true
        }
    ]
}
EOF

# Cria um arquivo de serviço Systemd para iniciar o XMRig automaticamente
sudo cat > /etc/systemd/system/xmrig.service <<EOF
[Unit]
Description=XMrig Miner
After=network.target

[Service]
ExecStart=/opt/xmrig/build/xmrig -c /opt/xmrig/build/config.json
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
