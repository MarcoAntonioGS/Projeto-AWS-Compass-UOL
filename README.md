# Projeto AWS Compass UOL 
Este projeto faz parte do programa de bolsas DevSecOps da Compass UOL 2025. O objetivo é criar um ambiente escalável na AWS para hospedar um site WordPress, utilizando um Auto Scaling Group (ASG), Classic Load Balancer (CLB), Amazon RDS, Amazon EFS e monitoramento com CloudWatch.

## Tecnologias Usadas
- **VPC:** Rede virtual na AWS para isolar e organizar os recursos.
- **Auto Scaling Group (ASG):** Gerencia o número de instâncias EC2 com base na demanda.
- **Classic Load Balancer (CLB):** Distribui o tráfego entre as instâncias do ASG.
- **Amazon RDS:** Banco de dados MySQL gerenciado pela AWS para o WordPress.
- **Amazon EFS:** Sistema de arquivos compartilhado para armazenar os arquivos do WordPress.
- **Docker e Docker Compose:** Para rodar o WordPress em containers.
- **Secrets Manager:** Armazena e gerencia as credenciais do banco de dados de forma segura.
- **CloudWatch:** Monitora o ambiente e cria alertas para escalabilidade.
  
## Pré requisitos
- Conta na AWS com permissões de administrador
- Acesso a um terminal com conexão à internet
- Conhecimento básico de Docker, WordPress e AWS

## Crie uma VPC com:
- 2 sub-redes públicas em zonas de disponibilidade diferentes (ex.: us-east-1a, us-east-1b)
- Conecte as sub-redes públicas a um Internet Gateway
- 2 sub-redes privadas em zonas de disponibilidade diferentes (ex.: us-east-1a, us-east-1b)
- Um NAT Gateway em uma sub-rede pública para saída à internet (sem IPs públicos nas instâncias privadas)
- Tabela de rotas configurada para que as sub-redes privadas acessem a internet via NAT e as públicas pelo Internet Gateway
  
## Criar os Security Groups
- Vá em "Security Groups" no console AWS
- Crie 4 SGs (SG-ELB, SG-EC2, SG-RDS, SG-EFS)
- Adicione as regras de entrada e saída conforme a tabela abaixo

| Componente | SG Nome | Inbound | Outbound |
|------------|--------|---------|----------|
| Classic Load Balancer |  SG-ELB  |  TCP 80 (0.0.0.0/0) | TCP 80 (SG-EC2) |
| EC2 Instances (ASG) |	SG-EC2 |	TCP 80 (SG-ELB), TCP 2049 (SG-EC2)|	TCP 3306 (SG-RDS), TCP 2049 (SG-EFS), TCP 443 (0.0.0.0/0) |
| RDS MySQL	| SG-RDS |	TCP 3306 (SG-EC2)| 	Todos (0.0.0.0/0) |
| EFS	| SG-EFS |	TCP 2049 (SG-EC2) |	Todos (0.0.0.0/0) |

## Crie uma instâcia RDS
- Engine: MySQL.
- Tamanho: db.t2.micro (free tier, se aplicável)
- Sub-rede privada (sem acesso público)
- Grupo de Segurança: Permitir tráfego na porta 3306 apenas das instâncias EC2
- Anote o endpoint, usuário e senha
- Configure o SG-RDS como Security Group

## Salve as credenciais no Secrets Manager
- Clique em Armazenar um novo segredo
- Crie um segredo no AWS Secrets Manager contendo as credenciais do banco de dados (host, usuário, senha e nome do banco de dados)

## Crie um sistema de arquivos EFS
- Clique criar sistema de arquivos e coloque a mesma VPC que vai usar nas instâncias
- Configure as zonas de disponibilidade para as instâncias privadas
- Configure o SG-EFS como Security Group

## Crie um Classic Load Balancer
- Nome: Escolha um nome (ex.: wordpress-elb)
- Listener:
  - Load Balancer Protocol: HTTP, Porta: 80
  - Instance Protocol: HTTP, Porta: 80
- Adicione outro listener:
  - Load Balancer Protocol: TCP, Porta: 9090 (Prometheus)
  - Instance Protocol: TCP, Porta: 9090
- Sub-redes: Selecione as 2 sub-redes públicas
- Configure o SG-ELB como Security Group
- Health Check:
  - Protocol: HTTP
  - Path: /wp-admin/install.php (Mudar para "/" após instalar o Wordpress) 
  - Intervalo: 30 segundos, Timeout: 5, Threshold: 2, UnhealthyThreshold: 2, HealthyThreshold: 3
- Após criar, anote o DNS do ELB (ex:wordpress-elb-123456.us-east-1.elb.amazonaws.com)
- Editar configuração de perdurabilidade de cookies, selecione Gerado pelo balanceador de carga
  - Período de expiração: 0
  
## Crie um Launch Template:
- AMI: Amazon Linux 2
- Tipo: t2.micro
- Configure o SG-EC2 como Security Group
- Adicione uma IAM role com as políticas:
   - AmazonElasticFileSystemFullAccess
   - AmazonSSMManagedInstanceCore
   - Adicione a permissão personalizada para Secrets Manager:
 ```
{
	"Version": "2012-10-17",
	"Statement": [
		{
			"Effect": "Allow",
			"Action": "secretsmanager:GetSecretValue",
			"Resource": "<ARN DO SEU SEGREDO>"
		}
	]
}
```

- Adicione o Script user_data (veja abaixo)
```
#!/bin/bash

# Atualizar o sistema
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
mkdir -p /mnt/efs
mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport <SEU-EFS>:/ /mnt/efs

# Adicionar montagem automática no /etc/fstab
echo "<SEU-EFS>:/ /mnt/efs nfs4 defaults,_netdev 0 0" | sudo tee -a /etc/fstab

# Instalar MySQL Client e jq (para processar JSON)
yum install -y mysql jq

# Instalar a CLI da AWS (se ainda não estiver instalada)
yum install -y aws-cli

# Recuperar as credenciais do Secrets Manager
SECRET_ID="wordpress-db-credentials" # Nome do segredo no Secrets Manager
REGION="us-east-1" # Região do Secrets Manager

# Extrair o segredo
SECRET_JSON=$(aws secretsmanager get-secret-value --secret-id $SECRET_ID --region $REGION --query SecretString --output text)

# Verificar se o segredo foi recuperado com sucesso
if [ -z "$SECRET_JSON" ]; then
  echo "Erro: Não foi possível recuperar o segredo do Secrets Manager." >> /var/log/user-data.log
  exit 1
fi

# Extrair valores do JSON
WORDPRESS_DB_HOST=$(echo $SECRET_JSON | jq -r '.host')
WORDPRESS_DB_USER=$(echo $SECRET_JSON | jq -r '.username')
WORDPRESS_DB_PASSWORD=$(echo $SECRET_JSON | jq -r '.password')
WORDPRESS_DB_NAME=$(echo $SECRET_JSON | jq -r '.dbname')

# Verificar se todas as variáveis foram preenchidas
if [ -z "$WORDPRESS_DB_HOST" ] || [ -z "$WORDPRESS_DB_USER" ] || [ -z "$WORDPRESS_DB_PASSWORD" ] || [ -z "$WORDPRESS_DB_NAME" ]; then
  echo "Erro: Credenciais do banco de dados incompletas no Secrets Manager." >> /var/log/user-data.log
  exit 1
fi

# Criar o banco de dados no RDS (se não existir)
mysql -h $WORDPRESS_DB_HOST -u $WORDPRESS_DB_USER -p$WORDPRESS_DB_PASSWORD <<EOF
CREATE DATABASE IF NOT EXISTS $WORDPRESS_DB_NAME;
EOF

# Verificar se o banco de dados foi criado com sucesso
if [ $? -ne 0 ]; then
  echo "Erro: Não foi possível criar ou verificar o banco de dados no RDS." >> /var/log/user-data.log
  exit 1
fi

# Criar docker-compose.yml no EFS (se ainda não existir)
if [ ! -f /mnt/efs/docker-compose.yml ]; then
  cat <<EOF > /mnt/efs/docker-compose.yml
version: '3'
services:
  wordpress:
    image: wordpress:latest
    ports:
      - "80:80"
    environment:
      WORDPRESS_DB_HOST: $WORDPRESS_DB_HOST
      WORDPRESS_DB_USER: $WORDPRESS_DB_USER
      WORDPRESS_DB_PASSWORD: $WORDPRESS_DB_PASSWORD
      WORDPRESS_DB_NAME: $WORDPRESS_DB_NAME
    volumes:
      - /mnt/efs:/var/www/html/wp-content
EOF
fi

# Criar um serviço systemd para o Docker Compose
cat <<EOF | sudo tee /etc/systemd/system/docker-compose.service
[Unit]
Description=Docker Compose Application Service
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/mnt/efs
ExecStart=/usr/local/bin/docker-compose up -d
ExecStop=/usr/local/bin/docker-compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

# Recarregar systemd e habilitar o serviço
systemctl daemon-reload
systemctl enable docker-compose.service

# Iniciar o serviço Docker Compose
systemctl start docker-compose.service

# Verificar se o serviço foi iniciado com sucesso
if [ $? -eq 0 ]; then
  echo "Serviço Docker Compose iniciado com sucesso." >> /var/log/user-data.log
else
  echo "Erro: Falha ao iniciar o serviço Docker Compose." >> /var/log/user-data.log
  # Tentar reiniciar o serviço (opcional)
  systemctl restart docker-compose.service || echo "Falha ao reiniciar o serviço Docker Compose." >> /var/log/user-data.log
fi

```
- Nesse trecho coloque o DNS do seu EFS

```
# Instalar amazon-efs-utils e montar EFS
yum install -y amazon-efs-utils
mkdir -p /mnt/efs
mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport <SEU-EFS>:/ /mnt/efs

# Adicionar montagem automática no /etc/fstab
echo "<SEU-EFS>:/ /mnt/efs nfs4 defaults,_netdev 0 0" | sudo tee -a /etc/fstab
```

## Crie um Auto Scaling Group
- Min: 2 instâncias, Max: 4 (ou mais, se desejar)
- Sub-redes: As 2 sub-redes privadas
- Associe ao Classic Load Balancer
- Em Política de manutenção de instâncias coloque Priorizar disponibilidade
- Habilitar coleta de métricas de grupo no CloudWatch
- Em Adicionar notificações
  - Clique em Criar um tópico e adicione seu Email
  - Entre no seu email e confirme

## Crie uma política de escalabilidade
- Navegue até o serviço CloudWatch > Alarms > Create Alarm
- Selecione a métrica RequestCount
- Crie os Alarmes
- Siga o exemplo da imagem abaixo
  
 ![Captura de tela de 2025-03-19 17-10-03](https://github.com/user-attachments/assets/15b0052d-f5cf-43c0-ac92-e4750f7df13d)

- No seu grupo ASG vá em Criar política de escalabilidade dinâmica
- Crie duas políticas simples para reduzir e aumentar a capacidade
- Siga o exemplo da imagem abaixo

![Captura de tela de 2025-03-19 17-36-19](https://github.com/user-attachments/assets/58a8c50a-83ca-472a-8ade-b2aa67132bb2)

## Crie um Dashboard no CloudWatch para monitorar as instâncias
- No Console da AWS, vá até o serviço CloudWatch
- No menu lateral, clique em Dashboards
- Clique em Create dashboard
- Adicione os widgets: GroupTotalInstances, CPUUtilization, RequestCount, Latency, StorageBytes, PercentIOLimit,   FreeStorageSpace, CPUUtilization(RDS) e os alarmes
- Siga o exemplo abaixo

![Captura de tela de 2025-03-19 17-38-12](https://github.com/user-attachments/assets/261f5287-ed29-4e6a-8f47-1dedc638725b)


## Teste
- Acesse o DNS do CLB no navegador: http://loadbalancer-xxxxxxxx.us-east-1.elb.amazonaws.com
- Instale o Wordpress
- Faça o upload de uma imagem no Wordpress e veja se foi salvo no EFS
- De F5 na página varias vezes 
- Veja se o ASG cria mais instâncias ( Diminua os valores da regra se necessario)
- Espere um tempo de veja se as instâncias foram encerradas









