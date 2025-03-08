# Projeto-AWS-Compass-UOL
Atividade prática do programa de bolsas Devsecops da Compass UOL 2025, cria um Auto Scaling Group (ASG), com a aplicação WordPress rodando em containers Docker, direcionando o tráfego para um Load Balancer.

## Arquitetura
- _VPC:_ Rede virtual na região us-east-1 com sub-redes públicas e privadas.
- *Auto Scaling Group (ASG):* Gerencia 2 instâncias EC2 (escaláveis) com o Amazon Linux 2.
- *Classic Load Balancer:* Distribui o tráfego HTTP (porta 80) entre as instâncias.
- *Amazon RDS:* Instância MySQL para o banco de dados WordPress.
- *Amazon EFS:* Armazena os arquivos do WordPress (wp-content) compartilhados entre as instâncias.
- *Docker e Docker Compose:* Executa o WordPress e os serviços de monitoramento.
- *Prometheus:* Coletor de métricas do sistema (via Node Exporter) e do WordPress (com exporter opcional).
- *Grafana:* Painel de visualização das métricas coletadas
