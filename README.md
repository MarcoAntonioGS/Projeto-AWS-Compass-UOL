# Projeto AWS Compass UOL
Atividade prática do programa de bolsas DevSecOps da Compass UOL 2025, cria um Auto Scaling Group (ASG) com a aplicação WordPress rodando em containers Docker, direcionando o tráfego para um Classic Load Balancer (CLB), com monitoramento avançado usando Prometheus e Node Exporter.

## Tecnologias usadas
- **VPC:** Rede virtual na região us-east-1 com sub-redes públicas e privadas.
- **Auto Scaling Group (ASG):** Gerencia 2 instâncias EC2 (escaláveis) com o Amazon Linux 2.
- **Classic Load Balancer:** Distribui o tráfego HTTP (porta 80) entre as instâncias.
- **Amazon RDS:** Instância MySQL para o banco de dados WordPress.
- **Amazon EFS:** Armazena os arquivos do WordPress (wp-content) compartilhados entre as instâncias.
- **Docker e Docker Compose:** Executa o WordPress e os serviços de monitoramento.
- **Prometheus:** Monitora métricas do Docker e das instâncias.
- **Node Exporter:** Coleta métricas de sistema (CPU, memória, disco) das instâncias.
- **AWS Service Discovery:** Descoberta automática de instâncias via API EC2.
  
## Pré requisitos
- Conta na AWS com permissões de administrador.
- CLI da AWS configurada (aws configure) com credenciais válidas.
- Acesso a um terminal com conexão à internet.

## Crie uma VPC com:
- 2 sub-redes públicas em zonas de disponibilidade diferentes (ex.: us-east-1a, us-east-1b).
- Conecte as sub-redes públicas a um Internet Gateway. 
- 2 sub-redes privadas em zonas de disponibilidade diferentes (ex.: us-east-1a, us-east-1b).
- Um NAT Gateway em uma sub-rede pública para saída à internet (sem IPs públicos nas instâncias privadas).
- Tabela de rotas configurada para que as sub-redes privadas acessem a internet via NAT e as públicas pelo Internet Gateway.
  
## Criar os Security Groups
- Vá em "Security Groups" no console AWS.
- Crie 4 SGs (SG-ELB, SG-EC2, SG-RDS, SG-EFS).
- Adicione as regras de entrada e saída conforme a tabela abaixo.

| Componente | SG Nome | Inbound | Outbound |
|------------|--------|---------|----------|
| Classic Load Balancer |  SG-ELB  |  TCP 80 (0.0.0.0/0) | TCP 80 (SG-EC2) |
| EC2 Instances (ASG) |	SG-EC2 |	TCP 80 (SG-ELB), TCP 2049 (SG-EC2), TCP 9100 (SG-EC2) |	TCP 3306 (SG-RDS), TCP 2049 (SG-EFS), TCP 443 (0.0.0.0/0) |
| RDS MySQL	| SG-RDS |	TCP 3306 (SG-EC2)| 	Todos (0.0.0.0/0) |
| EFS	| SG-EFS |	TCP 2049 (SG-EC2) |	Todos (0.0.0.0/0) |

## Crie uma instâcia RDS
- Engine: MySQL.
- Tamanho: db.t2.micro (free tier, se aplicável).
- Sub-rede privada (sem acesso público).
- Grupo de Segurança: Permitir tráfego na porta 3306 apenas das instâncias EC2.
- Anote o endpoint, usuário e senha do banco.ação de uma instância.
- Configure o SG-RDS como Security Group.
- Crie o banco de dados:
  ```
  mysql -h <seu endpoint> -u admin -p221203Ma
  CREATE DATABASE wordpress;
  ```
## Crie um sistema de arquivos EFS
- Clique Criar sistema de arquivos e coloque a mesma VPC que vai usar nas instâncias.
- Configure o SG-EFS como Security Group.

## Crie um Classic Load Balancer
- Nome: Escolha um nome (ex.: wordpress-elb).
- Listener:
  - Load Balancer Protocol: HTTP, Porta: 80.
  - Instance Protocol: HTTP, Porta: 80.
- Adicione outro listener:
  - Load Balancer Protocol: TCP, Porta: 9090 (Prometheus).
  - Instance Protocol: TCP, Porta: 9090.
- Sub-redes: Selecione as 2 sub-redes públicas.
- Configure o SG-ELB como Security Group.
- Health Check:
  - Protocol: HTTP.
  - Path: /wp-admin/install.php (Mudar para "/" após instalar o Wordpress) 
  - Intervalo: 30 segundos, Threshold: 2.
- Após criar, anote o DNS do ELB (ex:wordpress-elb-123456.us-east-1.elb.amazonaws.com).
- Editar configuração de perdurabilidade de cookies, selecione Gerado pelo balanceador de carga.

## Crie um Launch Template:
- AMI: Amazon Linux 2.
- Tipo: t2.micro.
- Configure o SG-EC2 como Security Group.
- Adicione uma IAM role com as políticas:
   - AmazonElasticFileSystemFullAccess.
   - AmazonSSMManagedInstanceCore.
   - Adicione a permissão personalizada para Service Discovery:
 ```
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "ec2:DescribeInstances",
      "Resource": "*"
    }
  ]
}
```

- Adicione o Script user_data (veja abaixo).
```
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
```

## Crie um Auto Scaling Group
- Min: 2 instâncias, Max: 2 (ou mais, se desejar).
- Sub-redes: As 2 sub-redes privadas.
- Associe ao Classic Load Balancer.
- Adicione a tag prometheus=true ao ASG para Service Discovery

## Teste
- Acesse o DNS do CLB no navegador: http://loadbalancer-2050655957.us-east-1.elb.amazonaws.com.
- Instale o Wordpress.
- Acesse o Prometheus: http://loadbalancer-2050655957.us-east-1.elb.amazonaws.com:9090 > Status > Targets para confirmar que job="docker" e job="node" estão "Up".
- Teste métricas como node_cpu_seconds_total na aba Graph.








