# Projeto-AWS-Compass-UOL
Atividade prática do programa de bolsas Devsecops da Compass UOL 2025, cria um Auto Scaling Group (ASG), com a aplicação WordPress rodando em containers Docker, direcionando o tráfego para um Load Balancer.

## Tecnologias usadas
- **VPC:** Rede virtual na região us-east-1 com sub-redes públicas e privadas.
- **Auto Scaling Group (ASG):** Gerencia 2 instâncias EC2 (escaláveis) com o Amazon Linux 2.
- **Classic Load Balancer:** Distribui o tráfego HTTP (porta 80) entre as instâncias.
- **Amazon RDS:** Instância MySQL para o banco de dados WordPress.
- **Amazon EFS:** Armazena os arquivos do WordPress (wp-content) compartilhados entre as instâncias.
- **Docker e Docker Compose:** Executa o WordPress e os serviços de monitoramento.

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
| EC2 Instances (ASG) |	SG-EC2 |	TCP 80 (SG-ELB), TCP 2049 (SG-EC2) |	TCP 3306 (SG-RDS), TCP 2049 (SG-EFS), TCP 443 (0.0.0.0/0) |
| RDS MySQL	| SG-RDS |	TCP 3306 (SG-EC2)| 	Todos (0.0.0.0/0) |
| EFS	| SG-EFS |	TCP 2049 (SG-EC2) |	Todos (0.0.0.0/0) |

## Crie uma instâcia RDS
- Engine: MySQL.
- Tamanho: db.t2.micro (free tier, se aplicável).
- Sub-rede privada (sem acesso público).
- Grupo de Segurança: Permitir tráfego na porta 3306 apenas das instâncias EC2.
- Anote o endpoint, usuário e senha do banco.ação de uma instância.
- Configure o SG-RDS como Security Group.

## Crie um sistema de arquivos EFS
- Clique Criar sistema de arquivos e coloque a mesma VPC que vai usar nas instâncias.
- Configure o SG-EFS como Security Group.

## Crie um Classic Load Balancer
- Nome: Escolha um nome (ex.: wordpress-elb).
- Listener:
  - Load Balancer Protocol: HTTP, Porta: 80.
  - Instance Protocol: HTTP, Porta: 80.











