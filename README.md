# 🐙 ProjetoTaiga — Stack Docker Completa

> **Taiga** é uma plataforma open-source de gestão de projetos ágeis (Scrum/Kanban).
> Este repositório contém a stack Docker Compose pronta para implantação local ou em servidor.
>
> ✅ **Status:** Produção local funcionando em `http://192.168.0.181:9000`

---

## 📑 Índice

1. [Como o Taiga Funciona](#-como-o-taiga-funciona)
2. [Arquitetura da Stack](#️-arquitetura-da-stack)
3. [Detalhamento de Cada Serviço](#-detalhamento-de-cada-serviço)
4. [Por Que Cada Variável Existe](#-por-que-cada-variável-existe)
5. [Pré-requisitos](#-pré-requisitos)
6. [Estrutura do Repositório](#️-estrutura-do-repositório)
7. [Passo a Passo — Deploy Completo](#-passo-a-passo--deploy-completo)
8. [Inicialização Automática (taiga-init)](#-inicialização-automática-taiga-init)
9. [Gerenciamento & Manutenção](#️-gerenciamento--manutenção)
10. [Backup & Restauração](#-backup--restauração)
11. [Troubleshooting — Erros Conhecidos e Soluções](#-troubleshooting--erros-conhecidos-e-soluções)
12. [Produção — Proxy Reverso SSL](#-produção--proxy-reverso-ssl)

---

## 🧠 Como o Taiga Funciona

O Taiga é um sistema **modular** — cada responsabilidade é isolada em um serviço separado. Eles se comunicam entre si, e o usuário final interage com a interface web.

### Fluxo de uma requisição do usuário

```
Usuário no navegador
       │
       ▼
  taiga-front :9000          ← Interface Angular (HTML/CSS/JS estático)
       │  faz chamadas REST
       ▼
  taiga-back :8000            ← API Django (cérebro da aplicação)
       │
       ├──► taiga-db          ← Lê/escreve dados (projetos, tarefas, usuários)
       ├──► taiga-redis       ← Busca em cache (sessões, resultados de queries)
       └──► taiga-rabbitmq    ← Publica eventos e tarefas na fila
                  │
                  ├──► taiga-async    ← Consome tarefas (e-mail, webhooks, imports)
                  └──► taiga-events   ← Consome eventos, envia via WebSocket ao navegador
                              │
                              ▼
                    Navegador recebe atualização em tempo real
                    (card movido, comentário adicionado, etc.)
```

### Fluxo de criar um projeto (exemplo real)

```
1. Usuário clica em "Novo Projeto" → Angular envia POST /api/v1/projects
2. taiga-back:
   a) Valida a requisição e cria o projeto no PostgreSQL
   b) Aplica o template padrão (colunas, status, permissões)
   c) Publica evento no RabbitMQ → EVENTS_PUSH_BACKEND_URL
   d) Publica tarefas async no RabbitMQ → CELERY_BROKER_URL
3. taiga-events recebe o evento e envia via WebSocket ao navegador
4. taiga-async processa tarefas em background (e-mails, índices, etc.)
5. Projeto aparece na tela em tempo real
```

---

## 🏗️ Arquitetura da Stack

```
┌─────────────────────────────────────────────────────────────┐
│                        HOST (Servidor)                       │
│                                                              │
│  :9000 ──► taiga-front     :8000 ──► taiga-back             │
│  :8888 ──► taiga-events    :8003 ──► taiga-protected         │
│  :15672 ──► rabbitmq-admin                                   │
│                                                              │
│  ┌─────────────────── rede: taiga-net ──────────────────┐   │
│  │                                                        │   │
│  │  taiga-front ──────────────────────► taiga-back       │   │
│  │  taiga-events ──► taiga-rabbitmq ◄── taiga-back       │   │
│  │  taiga-async  ──► taiga-rabbitmq                       │   │
│  │  taiga-back   ──► taiga-db                            │   │
│  │  taiga-back   ──► taiga-redis                         │   │
│  │  taiga-async  ──► taiga-db                            │   │
│  │  taiga-async  ──► taiga-redis                         │   │
│  │                                                        │   │
│  └────────────────────────────────────────────────────────┘   │
│                                                              │
│  Volumes persistentes:                                       │
│    taiga-db-data / taiga-media-data / taiga-static-data      │
│    taiga-rabbitmq-data / taiga-redis-data                    │
└─────────────────────────────────────────────────────────────┘
```

---

## 📦 Detalhamento de Cada Serviço

### 🖥️ `taiga-front` — Interface Web (porta 9000)
**Imagem:** `taigaio/taiga-front:latest`

Aplicação Angular compilada e servida por um Nginx interno. É o que o usuário vê no navegador.

- Renderiza o board Kanban, backlog, sprints, épicos e wiki
- Faz chamadas HTTP para `taiga-back:8000` para buscar e salvar dados
- Mantém uma conexão WebSocket persistente com `taiga-events:8888` para receber atualizações em tempo real
- **Não tem lógica de negócio** — é apenas o "rosto" da aplicação

**Variáveis críticas:**
```env
TAIGA_URL             → URL do back-end (usada pelo Angular nas chamadas REST)
TAIGA_WEBSOCKETS_URL  → URL do servidor WebSocket para notificações ao vivo
```

---

### 🐍 `taiga-back` — API REST Django (porta 8000)
**Imagem:** `taigaio/taiga-back:latest`

O **cérebro** do Taiga. Toda a lógica de negócio reside aqui.

**Responsabilidades:**
- Autenticação (login, tokens JWT, OAuth para GitHub/GitLab)
- CRUD completo de todos os recursos (projetos, epics, stories, tarefas, sprints)
- Sistema de permissões e papéis por projeto
- Webhooks e integrações externas
- Aplicação de migrações de banco na inicialização
- **Duas conexões independentes ao RabbitMQ** (ver abaixo)

**Por que duas conexões ao RabbitMQ?**

| Conexão | Variável | Finalidade |
|---|---|---|
| Celery | `CELERY_BROKER_URL` | Envia tarefas pesadas para o worker processar em background |
| Events | `EVENTS_PUSH_BACKEND_URL` | Emite eventos em tempo real que o `taiga-events` retransmite via WebSocket |

> ⚠️ **Lição aprendida:** Se `EVENTS_PUSH_BACKEND_URL` não estiver definida, o Django tenta conectar a um host vazio ao salvar qualquer objeto → `socket.gaierror: [Errno -3] Temporary failure in name resolution` → **erro 500 em tudo**.

---

### ⚙️ `taiga-async` — Worker Celery
**Imagem:** `taigaio/taiga-back:latest` (mesma imagem, entrypoint diferente)

Executa tarefas assíncronas que não devem bloquear a API principal.

**Tarefas processadas:**
- Envio de e-mails (convites, notificações, reset de senha)
- Importação de projetos (CSV, Jira, Trello, GitHub)
- Execução de webhooks para Slack, Teams, etc.
- Cálculo de estatísticas e relatórios

Consome mensagens da fila do RabbitMQ e usa o Redis para armazenar resultados.

---

### 🔔 `taiga-events` — Servidor WebSocket Node.js (porta 8888)
**Imagem:** `taigaio/taiga-events:latest`

Ponte entre o RabbitMQ e os navegadores conectados.

**Fluxo:**
```
taiga-back salva um objeto
    → publica evento no RabbitMQ
        → taiga-events recebe o evento
            → transmite via WebSocket para todos os usuários
                que estão visualizando aquele projeto/board
```

Isso permite que dois usuários no mesmo board vejam as mudanças um do outro **sem recarregar a página**.

---

### 🔒 `taiga-protected` — Controle de Acesso a Arquivos (porta 8003)
**Imagem:** `taigaio/taiga-protected:latest`

Um microserviço simples que garante que arquivos privados (anexos, imagens de tarefas) só possam ser acessados por usuários autorizados.

**Problema que resolve:** Se os arquivos fossem servidos diretamente pelo Nginx, qualquer pessoa com a URL poderia acessar — mesmo sem estar logada ou sem ter permissão no projeto.

**Fluxo:**
```
Navegador → GET /-/media/arquivo-privado
    → taiga-protected verifica token do usuário
        → Autorizado: retorna o arquivo (200)
        → Não autorizado: retorna 403
```

---

### 🐘 `taiga-db` — PostgreSQL 15
**Imagem:** `postgres:15-alpine`

Banco de dados principal. Armazena todo o estado da aplicação: usuários, projetos, tarefas, histórico, permissões, configurações.

**Volume:** `taiga-db-data` → `/var/lib/postgresql/data`

---

### ⚡ `taiga-redis` — Redis 7
**Imagem:** `redis:7-alpine`

Três funções simultâneas:
1. **Cache** de respostas da API Django (reduz carga no banco)
2. **Sessões** de usuários autenticados
3. **Backend de resultados** do Celery (status e resultados de tarefas assíncronas)

**Volume:** `taiga-redis-data` → `/data`

---

### 🐇 `taiga-async-rabbitmq` — RabbitMQ 3.12 (porta 15672 admin)
**Imagem:** `rabbitmq:3.12-management-alpine`

Broker de mensagens que desacopla os serviços.

**Dois consumidores:**
- `taiga-async` → consome fila de tarefas Celery
- `taiga-events` → consome fila de eventos em tempo real

**Painel de administração:** `http://IP:15672` (usuário/senha definidos no `.env`)

**Volume:** `taiga-rabbitmq-data` → `/var/lib/rabbitmq`

---

### 🚀 `taiga-init` — Serviço de Inicialização (roda uma vez)
**Imagem:** `taigaio/taiga-back:latest` (com script customizado)

Serviço com `restart: "no"` que executa apenas uma vez por `docker compose up`.

**Sequência de execução:**
```
[1/4] Aguarda o banco aceitar conexões (loop com retry de 3s)
[2/4] Aplica migrações pendentes (manage.py migrate)
[3/4] Coleta arquivos estáticos (manage.py collectstatic)
[4/4] Cria superusuário admin (verifica se já existe antes)
```

**Idempotente:** pode rodar múltiplas vezes sem efeitos colaterais.

---

## ⚙️ Por Que Cada Variável Existe

### Variáveis de Identidade
| Variável | Onde é usada | Por quê |
|---|---|---|
| `TAIGA_DOMAIN` | `taiga-front` | URL base que o Angular usa para chamar a API |
| `TAIGA_SCHEME` | `taiga-back`, `taiga-front` | Define se os links gerados são `http://` ou `https://` |
| `SECRET_KEY` | `taiga-back`, `taiga-events` | Assina tokens JWT, sessões e valida comunicação entre serviços |
| `TAIGA_SECRET_KEY` | `taiga-back` | Alias da SECRET_KEY para o settings.py do Django |

### Variáveis de Banco de Dados
| Variável | Onde é usada | Por quê |
|---|---|---|
| `POSTGRES_DB` | `taiga-db`, `taiga-back` | Nome do banco a criar/conectar |
| `POSTGRES_USER` | `taiga-db`, `taiga-back` | Usuário com acesso ao banco |
| `POSTGRES_PASSWORD` | `taiga-db`, `taiga-back` | Senha do usuário do banco |
| `POSTGRES_HOST` | `taiga-back` | Hostname do banco na rede Docker (`taiga-db`) |

### Variáveis de RabbitMQ
| Variável | Onde é usada | Por quê |
|---|---|---|
| `RABBITMQ_USER` | Todos os serviços | Usuário para autenticar no broker |
| `RABBITMQ_PASS` | Todos os serviços | Senha para autenticar no broker |
| `RABBITMQ_VHOST` | Todos os serviços | Virtual host isolado para o Taiga |
| `RABBITMQ_HOST` | `taiga-back`, `taiga-async` | Hostname do broker na rede Docker |
| `CELERY_BROKER_URL` | `taiga-back`, `taiga-async` | URL completa para o Celery conectar ao broker de tarefas |
| `EVENTS_PUSH_BACKEND` | `taiga-back` | Classe Python do backend de eventos (rabbitmq) |
| **`EVENTS_PUSH_BACKEND_URL`** | **`taiga-back`** | **⚠️ URL para emissão de eventos em tempo real — SEM ELA tudo dá 500** |

### Variáveis de Cache
| Variável | Onde é usada | Por quê |
|---|---|---|
| `CELERY_RESULT_BACKEND` | `taiga-async` | Onde o Celery salva resultados de tarefas |
| `REDIS_URL` | `taiga-back` | URL do Redis para cache e sessões Django |

### Variáveis de E-mail
| Variável | Valor Local | Valor Produção |
|---|---|---|
| `EMAIL_BACKEND` | `console` (imprime nos logs) | `smtp.EmailBackend` |
| `EMAIL_HOST` | `localhost` | `smtp.suaempresa.com` |
| `EMAIL_PORT` | `587` | `587` |
| `EMAIL_HOST_USER` | _(vazio)_ | `usuario@empresa.com` |
| `EMAIL_HOST_PASSWORD` | _(vazio)_ | senha SMTP |
| `EMAIL_USE_TLS` | `False` | `True` |

---

## ✅ Pré-requisitos

| Software | Versão mínima | Como verificar |
|---|---|---|
| Docker Engine | 24.x | `docker --version` |
| Docker Compose Plugin | 2.x | `docker compose version` |
| Git | qualquer | `git --version` |

> **Windows:** Docker Desktop com WSL2. **Linux/macOS:** Docker Engine nativo.

---

## 🗂️ Estrutura do Repositório

```
ProjetoTaiga/
│
├── docker-compose.yml       # Orquestração de todos os serviços
├── .env.example             # Template de variáveis (versionar ✅)
├── .env                     # Variáveis reais com senhas (NÃO versionar ❌)
├── .gitignore               # Ignora .env e logs
├── README.md                # Esta documentação
│
├── scripts/
│   └── init.sh              # Script de inicialização automática
│
└── nginx/
    └── taiga.conf           # Config Nginx (referência — não usada no modo local)
```

---

## 🚀 Passo a Passo — Deploy Completo

### 1. Clonar o repositório

```bash
git clone https://github.com/yurythx/ProjetoTaiga.git
cd ProjetoTaiga
```

### 2. Criar e configurar o `.env`

```bash
cp .env.example .env
nano .env   # ou: code .env
```

**Campos obrigatórios:**

```env
TAIGA_DOMAIN=192.168.0.X          # IP da sua máquina (ipconfig / ip addr)
SECRET_KEY=CHAVE_LONGA_ALEATÓRIA  # Gere com o comando abaixo
POSTGRES_PASSWORD=SenhaForte!
RABBITMQ_PASS=SenhaForte!
DJANGO_SUPERUSER_USERNAME=admin
DJANGO_SUPERUSER_EMAIL=admin@local.com
DJANGO_SUPERUSER_PASSWORD=SenhaAdmin!
```

**Gerar SECRET_KEY:**
```bash
python3 -c "import secrets; print(secrets.token_hex(64))"
# ou
openssl rand -hex 64
```

### 3. Subir a stack

```bash
docker compose up -d
```

> ⏳ **Primeira execução:** baixa ~1-2 GB de imagens. Pode levar alguns minutos.

### 4. Acompanhar a inicialização automática

```bash
docker compose logs -f taiga-init
```

Aguarde a mensagem:
```
✅ Inicialização concluída com sucesso!
```

### 5. Verificar todos os serviços

```bash
docker compose ps
```

Todos devem aparecer como `running` ou `healthy`.

### 6. Acessar o Taiga

| URL | O quê |
|---|---|
| `http://SEU_IP:9000` | Interface principal |
| `http://SEU_IP:8000/admin` | Admin Django |
| `http://SEU_IP:15672` | Admin RabbitMQ |

**Login:** usuário e senha definidos em `DJANGO_SUPERUSER_*` no `.env`.

---

## 🤖 Inicialização Automática (`taiga-init`)

O serviço `taiga-init` é executado automaticamente a cada `docker compose up` e:

1. **Aguarda o banco** estar pronto (loop com retry a cada 3s)
2. **Aplica migrações** → `manage.py migrate --noinput`
3. **Coleta estáticos** → `manage.py collectstatic --noinput --clear`
4. **Cria o superusuário** → só cria se ainda não existir

```bash
# Ver o que o taiga-init executou
docker compose logs taiga-init
```

**Seguro para re-execuções:** não duplica dados nem gera erros se já existirem.

---

## 🛠️ Gerenciamento & Manutenção

### Comandos do dia a dia

| Ação | Comando |
|---|---|
| Ver status | `docker compose ps` |
| Logs em tempo real (todos) | `docker compose logs -f` |
| Logs de um serviço | `docker compose logs -f taiga-back` |
| Reiniciar um serviço | `docker compose restart taiga-back` |
| Parar tudo | `docker compose stop` |
| Iniciar parado | `docker compose start` |
| Recriar após mudança no `.env` | `docker compose up -d --force-recreate taiga-back taiga-async` |
| Atualizar imagens | `docker compose pull && docker compose up -d` |

### Comandos Django úteis

```bash
# Aplicar migrações manualmente
docker compose exec taiga-back python manage.py migrate

# Criar superusuário interativo
docker compose exec taiga-back python manage.py createsuperuser

# Alterar senha de usuário
docker compose exec taiga-back python manage.py changepassword admin

# Shell interativo Django
docker compose exec taiga-back python manage.py shell

# Bash dentro do container
docker compose exec taiga-back bash
```

---

## 💾 Backup & Restauração

### Backup do banco de dados

```bash
docker compose exec taiga-db pg_dump -U taiga taiga \
  > backup_taiga_$(date +%Y%m%d_%H%M%S).sql
```

### Restaurar banco de dados

```bash
cat backup_taiga_YYYYMMDD.sql | \
  docker compose exec -T taiga-db psql -U taiga taiga
```

### Backup dos arquivos de mídia (uploads)

```bash
docker run --rm \
  -v projetotaiga_taiga-media-data:/data \
  -v $(pwd):/backup \
  alpine tar czf /backup/media_$(date +%Y%m%d).tar.gz /data
```

### Restaurar mídia

```bash
docker run --rm \
  -v projetotaiga_taiga-media-data:/data \
  -v $(pwd):/backup \
  alpine tar xzf /backup/media_YYYYMMDD.tar.gz -C /
```

---

## 🐛 Troubleshooting — Erros Conhecidos e Soluções

### ❌ ERR_CONNECTION_REFUSED na porta 8000 ou 9000
**Causa:** `.env` não existe ou está vazio — containers não sobem sem variáveis.

```bash
# Verificar se o .env existe
ls -la .env

# Verificar se os containers estão rodando
docker compose ps

# Solução
cp .env.example .env
# preencher o .env
docker compose up -d
```

---

### ❌ 500 Internal Server Error ao criar projetos
**Causa:** `EVENTS_PUSH_BACKEND_URL` não definida.

O `taiga-back` usa **duas conexões separadas** ao RabbitMQ:
- `CELERY_BROKER_URL` → tarefas assíncronas (Celery)
- `EVENTS_PUSH_BACKEND_URL` → eventos em tempo real

Sem a segunda, ao salvar **qualquer objeto** no banco, o Django tenta emitir um evento para um host vazio → DNS falha → 500.

```bash
# Verificar nos logs
docker compose logs taiga-back | grep "gaierror\|name resolution"

# Solução: garantir no .env estas variáveis
EVENTS_PUSH_BACKEND=taiga.events.backends.rabbitmq.EventsPushBackend
EVENTS_PUSH_BACKEND_URL=amqp://USER:PASS@taiga-async-rabbitmq/taiga
```

---

### ❌ 404 em `/api/v1/user-storage/...` (console do browser)
**Comportamento NORMAL — não é um erro.**

O Angular busca preferências de UI do usuário ao carregar a tela. Se o usuário nunca salvou aquela preferência, a API retorna 404. O front-end usa os valores padrão e cria a preferência quando necessário. Desaparece conforme se usa o sistema.

---

### ❌ Container `taiga-back` em loop de reinicialização
```bash
docker compose logs taiga-back
```

**Causas comuns:**
- `taiga-db` ainda não está `healthy` (aguardar)
- Variáveis do banco incorretas no `.env`
- `SECRET_KEY` vazia

---

### ❌ Notificações em tempo real não funcionam (sem WebSocket)
**Causa:** `taiga-events` não conecta ao RabbitMQ.

```bash
docker compose logs taiga-events
# Verificar se RABBITMQ_USER e RABBITMQ_PASS estão corretos
# Verificar se taiga-async-rabbitmq está healthy
docker compose ps taiga-async-rabbitmq
```

---

### ❌ Resetar TUDO (incluindo dados)
```bash
# ⚠️ APAGA TODOS OS DADOS — use apenas em ambiente de teste!
docker compose down -v
docker compose up -d
```

---

## 🔒 Produção — Proxy Reverso SSL

Em produção, coloque um proxy reverso com SSL na frente. O `taiga-gateway` expõe a porta 9000.

### Nginx Externo (exemplo)

```nginx
server {
    listen 443 ssl;
    server_name taiga.suaempresa.com;

    ssl_certificate     /etc/letsencrypt/live/taiga.suaempresa.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/taiga.suaempresa.com/privkey.pem;

    location / {
        proxy_pass http://localhost:9000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-Proto https;
    }
}
```

**Atualize o `.env`:**
```env
TAIGA_DOMAIN=taiga.suaempresa.com
TAIGA_SCHEME=https
```

---

## 📌 Referências

- [Repositório oficial taiga-docker](https://github.com/taigaio/taiga-docker)
- [Documentação oficial Taiga](https://community.taiga.io/t/taiga-30min-setup/170)
- [Taiga no Docker Hub](https://hub.docker.com/u/taigaio)
- [Fórum da comunidade Taiga](https://community.taiga.io/)

---

> **ProjetoTaiga** | Stack Docker — Implantado e validado em produção local `192.168.0.181`
> Versão: `2025` | Maintainer: DTI
