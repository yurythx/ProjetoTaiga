# 🐙 ProjetoTaiga — Stack Docker Completa

> **Taiga** é uma plataforma open-source de gestão de projetos ágeis (Scrum/Kanban).  
> Este repositório contém a configuração Docker Compose para implantação local ou em produção.

---

## 📑 Índice

1. [Visão Geral da Arquitetura](#-visão-geral-da-arquitetura)
2. [Pré-requisitos](#-pré-requisitos)
3. [Estrutura do Repositório](#-estrutura-do-repositório)
4. [Configuração do Ambiente (.env)](#-configuração-do-ambiente-env)
5. [Passo a Passo — Primeira Execução](#-passo-a-passo--primeira-execução)
6. [Acessando o Sistema](#-acessando-o-sistema)
7. [Gerenciamento & Manutenção](#️-gerenciamento--manutenção)
8. [Persistência de Dados (Volumes)](#-persistência-de-dados-volumes)
9. [Backup & Restauração](#-backup--restauração)
10. [Configuração de E-mail (SMTP)](#-configuração-de-e-mail-smtp)
11. [Produção — Proxy Reverso SSL](#-produção--proxy-reverso-ssl)
12. [Troubleshooting](#-troubleshooting)

---

## 🏗️ Visão Geral da Arquitetura

O Taiga é **modular por design** — cada responsabilidade roda em um container isolado. O fluxo de uma requisição é:

```
Navegador
   │
   ▼
taiga-gateway (Nginx :9000)  ←── único ponto de entrada
   │
   ├──► /             → taiga-front     (SPA Angular)
   ├──► /api /admin   → taiga-back      (Django REST API)
   ├──► /events       → taiga-events    (WebSocket Node.js)
   └──► /-/media/     → taiga-protected (Arquivos privados)

taiga-back ──► taiga-db          (PostgreSQL — dados principais)
           ──► taiga-redis        (Cache, sessões, filas)
           ──► taiga-rabbitmq     (Broker de mensagens)
                  │
                  └──► taiga-async (Celery Worker — tarefas em background)
```

### Tabela de Serviços

| Container | Imagem | Porta Interna | Função |
|---|---|---|---|
| `taiga-gateway` | `nginx:1.25-alpine` | `80` → host:`9000` | Proxy reverso / roteador de entrada |
| `taiga-front` | `taigaio/taiga-front` | `80` (interno) | Interface web Angular |
| `taiga-back` | `taigaio/taiga-back` | `8000` (interno) | API REST Django |
| `taiga-async` | `taigaio/taiga-back` | — | Worker Celery (tarefas assíncronas) |
| `taiga-events` | `taigaio/taiga-events` | `8888` (interno) | Notificações WebSocket em tempo real |
| `taiga-protected` | `taigaio/taiga-protected` | `8003` (interno) | Controle de acesso a arquivos privados |
| `taiga-db` | `postgres:15-alpine` | `5432` (interno) | Banco de dados relacional |
| `taiga-redis` | `redis:7-alpine` | `6379` (interno) | Cache e gerenciamento de sessões |
| `taiga-async-rabbitmq` | `rabbitmq:3.12-management-alpine` | `5672` (interno) | Broker de mensagens assíncronas |

---

## ✅ Pré-requisitos

Certifique-se de que os seguintes softwares estão instalados e funcionando:

| Software | Versão mínima | Verificação |
|---|---|---|
| Docker Engine | 24.x | `docker --version` |
| Docker Compose Plugin | 2.x | `docker compose version` |
| Git | qualquer | `git --version` |

> **Windows:** Use Docker Desktop com WSL2 habilitado.  
> **Linux:** Instale via `apt install docker.io docker-compose-plugin` ou script oficial do Docker.

---

## 🗂️ Estrutura do Repositório

```
ProjetoTaiga/
│
├── docker-compose.yml       # Orquestração de todos os serviços
├── .env.example             # Template de variáveis de ambiente (versionar ✅)
├── .env                     # Variáveis reais com senhas (NÃO versionar ❌)
├── .gitignore               # Ignora o .env e logs
├── README.md                # Esta documentação
│
└── nginx/
    └── taiga.conf           # Configuração do gateway Nginx (roteamento)
```

---

## ⚙️ Configuração do Ambiente (.env)

Todas as configurações sensíveis ficam centralizadas no arquivo `.env`.

### Como criar

```bash
cp .env.example .env
```

Edite o `.env` com seu editor de preferência:

```bash
# Linux / macOS
nano .env

# Windows (VS Code)
code .env
```

### Variáveis Obrigatórias

| Variável | Descrição | Exemplo |
|---|---|---|
| `TAIGA_DOMAIN` | IP ou domínio de acesso ao Taiga | `192.168.1.10:9000` ou `taiga.empresa.com` |
| `TAIGA_SCHEME` | Protocolo HTTP ou HTTPS | `http` (local) / `https` (produção) |
| `SECRET_KEY` | Chave criptográfica da aplicação (mínimo 64 chars aleatórios) | `abc123...xyz` |
| `POSTGRES_DB` | Nome do banco de dados | `taiga` |
| `POSTGRES_USER` | Usuário do banco de dados | `taiga` |
| `POSTGRES_PASSWORD` | Senha do banco de dados | `SenhaForte@2024!` |
| `RABBITMQ_USER` | Usuário do broker de mensagens | `taiga` |
| `RABBITMQ_PASS` | Senha do broker de mensagens | `RabbitSenha@Forte!` |
| `RABBITMQ_VHOST` | Virtual host do RabbitMQ | `taiga` |

### Gerando uma SECRET_KEY segura

```bash
# Com Python
python -c "import secrets; print(secrets.token_hex(64))"

# Com OpenSSL
openssl rand -hex 64
```

### Variáveis de E-mail (Opcionais para testes)

| Variável | Padrão | Descrição |
|---|---|---|
| `EMAIL_BACKEND` | `console` (exibe no log) | Trocar para `smtp.EmailBackend` em produção |
| `EMAIL_HOST` | — | Servidor SMTP (ex: `smtp.gmail.com`) |
| `EMAIL_PORT` | `587` | Porta SMTP |
| `EMAIL_HOST_USER` | — | Usuário SMTP |
| `EMAIL_HOST_PASSWORD` | — | Senha SMTP |
| `EMAIL_USE_TLS` | `True` | Ativa TLS |
| `DEFAULT_FROM_EMAIL` | — | Remetente padrão dos e-mails |

---

## 🚀 Passo a Passo — Primeira Execução

### Passo 1 — Clonar o repositório (se necessário)

```bash
git clone https://github.com/SEU_USUARIO/ProjetoTaiga.git
cd ProjetoTaiga
```

### Passo 2 — Configurar as variáveis de ambiente

```bash
cp .env.example .env
# Edite o .env com suas senhas e domínio
```

### Passo 3 — Subir os containers

```bash
docker compose up -d
```

> ⏳ **Na primeira vez**, o Docker baixará ~1 GB em imagens. Pode levar alguns minutos.

Acompanhe os logs durante a inicialização:

```bash
docker compose logs -f
```

Aguarde todos os serviços aparecerem como `healthy`:

```bash
docker compose ps
```

Saída esperada:

```
NAME                     STATUS
taiga-db                 healthy
taiga-async-rabbitmq     healthy
taiga-redis              healthy
taiga-back               running
taiga-async              running
taiga-front              running
taiga-events             running
taiga-protected          running
taiga-gateway            running
```

### Passo 4 — Criar o usuário administrador

```bash
docker compose exec taiga-back python manage.py createsuperuser
```

Siga as instruções no terminal:
- **Username:** nome de usuário para login
- **Email:** e-mail do administrador
- **Password:** senha (mínimo 8 caracteres)

### Passo 5 — Aplicar migrações (apenas se necessário)

Na maioria dos casos, as migrações já rodam automaticamente. Se houver erros:

```bash
docker compose exec taiga-back python manage.py migrate
```

---

## 🌐 Acessando o Sistema

Após todos os containers estarem `running`, acesse:

| URL | Descrição |
|---|---|
| `http://localhost:9000` | Interface principal do Taiga |
| `http://localhost:9000/admin` | Painel de administração Django |
| `http://localhost:15672` | Painel de gerenciamento do RabbitMQ (se exposto) |

> Em produção, substitua `localhost:9000` pelo seu domínio configurado em `TAIGA_DOMAIN`.

---

## 🛠️ Gerenciamento & Manutenção

### Comandos Essenciais

| Ação | Comando |
|---|---|
| Verificar status dos serviços | `docker compose ps` |
| Ver logs em tempo real (todos) | `docker compose logs -f` |
| Ver logs de um serviço específico | `docker compose logs -f taiga-back` |
| Reiniciar um serviço específico | `docker compose restart taiga-back` |
| Parar todos os serviços | `docker compose stop` |
| Iniciar serviços parados | `docker compose start` |
| Parar e remover containers | `docker compose down` |
| Recriar containers após mudança no `.env` | `docker compose up -d` |
| Forçar recriação de todos os containers | `docker compose up -d --force-recreate` |
| Atualizar imagens para latest | `docker compose pull && docker compose up -d` |

> ⚠️ **NUNCA use** `docker compose down -v` em produção — isso apaga todos os dados!

### Executar comandos Django no container

```bash
# Criar superusuário
docker compose exec taiga-back python manage.py createsuperuser

# Aplicar migrações pendentes
docker compose exec taiga-back python manage.py migrate

# Coletar arquivos estáticos
docker compose exec taiga-back python manage.py collectstatic --noinput

# Alterar senha de um usuário
docker compose exec taiga-back python manage.py changepassword <username>

# Abrir shell interativo Django
docker compose exec taiga-back python manage.py shell

# Abrir bash no container
docker compose exec taiga-back bash
```

---

## 💾 Persistência de Dados (Volumes)

Todos os dados importantes são armazenados em volumes Docker nomeados, que sobrevivem a `docker compose down`.

| Volume | Ponto de Montagem | Conteúdo |
|---|---|---|
| `taiga-db-data` | `/var/lib/postgresql/data` | Banco de dados PostgreSQL completo |
| `taiga-media-data` | `/taiga-back/media` | Uploads: avatares, anexos, imagens de projetos |
| `taiga-static-data` | `/taiga-back/static` | Assets estáticos da API Django |
| `taiga-rabbitmq-data` | `/var/lib/rabbitmq` | Estado e filas do RabbitMQ |
| `taiga-redis-data` | `/data` | Dados persistidos do Redis |

```bash
# Listar volumes do Taiga
docker volume ls | grep taiga

# Inspecionar um volume
docker volume inspect projetotaiga_taiga-db-data
```

---

## 🗄️ Backup & Restauração

### Backup do Banco de Dados

```bash
# Exportar dump SQL
docker compose exec taiga-db pg_dump -U ${POSTGRES_USER} ${POSTGRES_DB} \
  > backup_taiga_$(date +%Y%m%d_%H%M%S).sql
```

### Restaurar o Banco de Dados

```bash
# Restaurar a partir de um dump
cat backup_taiga_YYYYMMDD.sql | docker compose exec -T taiga-db \
  psql -U ${POSTGRES_USER} ${POSTGRES_DB}
```

### Backup dos Arquivos de Mídia

```bash
# Compactar volume de mídia em tar.gz
docker run --rm \
  -v projetotaiga_taiga-media-data:/data \
  -v $(pwd):/backup \
  alpine tar czf /backup/media_backup_$(date +%Y%m%d).tar.gz /data
```

### Restaurar Mídias

```bash
docker run --rm \
  -v projetotaiga_taiga-media-data:/data \
  -v $(pwd):/backup \
  alpine tar xzf /backup/media_backup_YYYYMMDD.tar.gz -C /
```

---

## 📧 Configuração de E-mail (SMTP)

Para que o Taiga envie e-mails de convite, notificação e recuperação de senha, configure o SMTP no `.env`:

```env
EMAIL_BACKEND=django.core.mail.backends.smtp.EmailBackend
DEFAULT_FROM_EMAIL=no-reply@suaempresa.com
EMAIL_HOST=smtp.suaempresa.com
EMAIL_PORT=587
EMAIL_HOST_USER=usuario@suaempresa.com
EMAIL_HOST_PASSWORD=SUA_SENHA_SMTP
EMAIL_USE_TLS=True
EMAIL_USE_SSL=False
```

Após editar, reinicie apenas os serviços que usam e-mail:

```bash
docker compose up -d taiga-back taiga-async
```

#### Exemplos por provedor

| Provedor | HOST | PORT | TLS |
|---|---|---|---|
| Gmail | `smtp.gmail.com` | `587` | `True` |
| Outlook/Office365 | `smtp.office365.com` | `587` | `True` |
| Amazon SES | `email-smtp.us-east-1.amazonaws.com` | `587` | `True` |
| Mailgun | `smtp.mailgun.org` | `587` | `True` |

> ⚠️ **Gmail:** Você precisa de uma "Senha de app", não a senha normal da conta.

---

## 🔒 Produção — Proxy Reverso SSL

Em produção, **nunca deixe o Taiga exposto na porta 9000 diretamente**. Coloque um proxy reverso com SSL na frente.

### Opção 1 — Nginx externo (manual)

Instale o Nginx no servidor host e configure um virtual host apontando para `localhost:9000`.

### Opção 2 — Traefik (recomendado para Docker)

Adicione ao `docker-compose.yml`:

```yaml
  traefik:
    image: traefik:v3.0
    command:
      - "--providers.docker=true"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--certificatesresolvers.le.acme.httpchallenge=true"
      - "--certificatesresolvers.le.acme.email=seu@email.com"
      - "--certificatesresolvers.le.acme.storage=/acme.json"
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./acme.json:/acme.json
    networks:
      - taiga-net
```

E adicione labels ao `taiga-gateway`:

```yaml
  taiga-gateway:
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.taiga.rule=Host(`taiga.seudominio.com`)"
      - "traefik.http.routers.taiga.entrypoints=websecure"
      - "traefik.http.routers.taiga.tls.certresolver=le"
```

Ajuste também o `.env`:

```env
TAIGA_DOMAIN=taiga.seudominio.com
TAIGA_SCHEME=https
```

---

## 🐛 Troubleshooting

### Container `taiga-back` reinicia em loop

```bash
docker compose logs taiga-back
```

**Causa comum:** banco de dados ainda não está pronto.  
**Solução:** aguarde o `taiga-db` obter status `healthy` e tente novamente.

### Erro de conexão ao banco de dados

```bash
docker compose exec taiga-db pg_isready -U taiga
```

Se retornar "não está aceitando conexões", revise as variáveis `POSTGRES_*` no `.env`.

### Página em branco ou erro 502

```bash
docker compose logs taiga-gateway
docker compose logs taiga-front
```

Verifique se o `taiga-front` subiu corretamente.

### WebSocket não conecta (notificações não funcionam)

```bash
docker compose logs taiga-events
```

Verifique se `RABBITMQ_USER` e `RABBITMQ_PASS` estão corretos e se o `taiga-async-rabbitmq` está `healthy`.

### Resetar TUDO (dados inclusos) ⚠️

```bash
# Cuidado: apaga todos os dados!
docker compose down -v
docker compose up -d
```

---

## 📌 Referências

- [Documentação oficial do Taiga](https://community.taiga.io/t/taiga-30min-setup/170)
- [Repositório oficial taiga-docker](https://github.com/taigaio/taiga-docker)
- [Taiga no Docker Hub](https://hub.docker.com/u/taigaio)
- [Fórum da comunidade Taiga](https://community.taiga.io/)

---

> Mantido por **ProjetoTaiga** | Configuração Docker Compose — versão `2025`
