
#!/bin/bash

# Atualizar sistema
yum update -y

# Instalar Docker
yum install -y docker
systemctl start docker
systemctl enable docker
usermod -aG docker ec2-user

# Instalar Docker Compose
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose

# Instalar amazon-efs-utils e montar EFS
yum install -y amazon-efs-utils

# Criar diretório para montagem do EFS
mkdir -p /mnt/efs

# Montar o EFS manualmente
mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport fs-xxxxxxxxxxxxxxxxx.efs.us-east-1.amazonaws.com:/ /mnt/efs

# Adicionar montagem automática no /etc/fstab
echo "fs-xxxxxxxxxxxxxxxxx.efs.us-east-1.amazonaws.com:/ /mnt/efs nfs4 defaults,_netdev 0 0" | sudo tee -a /etc/fstab

# Configurar Docker para expor métricas
cat <<EOF > /etc/docker/daemon.json
{
  "metrics-addr": "0.0.0.0:9323",
  "experimental": false
}
EOF
systemctl restart docker
if [ $? -ne 0 ]; then
  echo "Erro ao reiniciar o Docker. Verifique os logs."
  exit 1
fi

# Aguardar até que a porta 9323 esteja disponível
echo "Aguardando Docker expor métricas na porta 9323..."
until curl -s http://localhost:9323/metrics >/dev/null; do
  echo "Porta 9323 não está disponível, aguardando..."
  sleep 2
done
echo "Porta 9323 disponível!"

# Criar docker-compose.yml no EFS
if [ ! -f /mnt/efs/docker-compose.yml ]; then
  cat <<EOF > /mnt/efs/docker-compose.yml
version: '3.8'

services:
  wordpress:
    image: wordpress:latest
    ports:
      - "80:80"
    environment:
      WORDPRESS_DB_HOST: database-xxxxxxxxxxxx.us-east-1.rds.amazonaws.com
      WORDPRESS_DB_USER: admin
      WORDPRESS_DB_PASSWORD: SenhaSegura
      WORDPRESS_DB_NAME: wordpress
    volumes:
      - /mnt/efs:/var/www/html/wp-content
    restart: always

  prometheus:
    image: prom/prometheus:latest
    network_mode: host
    ports:
      - "9090:9090"
    volumes:
      - /mnt/efs/prometheus.yml:/etc/prometheus/prometheus.yml
    command:
      - "--config.file=/etc/prometheus/prometheus.yml"
    restart: always

  node-exporter:
    image: prom/node-exporter:latest
    network_mode: host
    ports:
      - "9100:9100"
    restart: always
EOF
fi

# Criar arquivo de configuração do Prometheus
if [ ! -f /mnt/efs/prometheus.yml ]; then
  cat <<EOF > /mnt/efs/prometheus.yml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'docker'
    static_configs:
      - targets: ['localhost:9323']

  - job_name: 'node'
    ec2_sd_configs:
      - region: us-east-1
        port: 9100
    relabel_configs:
      - source_labels: [__meta_ec2_tag_prometheus]
        regex: true
        action: keep
EOF
fi

# Dar permissões ao diretório do EFS
chown -R ec2-user:ec2-user /mnt/efs

# Iniciar os containers automaticamente
cd /mnt/efs
docker-compose up -d
