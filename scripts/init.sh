#!/bin/sh
# =============================================================================
# init.sh — Script de inicialização automática do Taiga
#
# Executado uma única vez pelo serviço "taiga-init" no docker compose.
# Responsável por:
#   1. Aguardar o banco de dados estar pronto
#   2. Aplicar todas as migrações Django pendentes
#   3. Coletar arquivos estáticos
#   4. Criar o superusuário (ignora se já existir)
# =============================================================================

set -e

echo ""
echo "============================================="
echo "  TAIGA — Inicialização Automática"
echo "============================================="
echo ""

# -----------------------------------------------------------------------------
# 1. Aguardar o banco de dados aceitar conexões
# -----------------------------------------------------------------------------
echo "[1/4] Aguardando o banco de dados (${POSTGRES_HOST})..."

until python -c "
import psycopg2, sys, os
try:
    psycopg2.connect(
        host=os.environ['POSTGRES_HOST'],
        dbname=os.environ['POSTGRES_DB'],
        user=os.environ['POSTGRES_USER'],
        password=os.environ['POSTGRES_PASSWORD']
    )
    sys.exit(0)
except Exception as e:
    sys.exit(1)
" 2>/dev/null; do
    echo "  › Banco ainda não disponível. Aguardando 3s..."
    sleep 3
done

echo "  ✓ Banco de dados disponível!"
echo ""

# -----------------------------------------------------------------------------
# 2. Aplicar migrações
# -----------------------------------------------------------------------------
echo "[2/4] Aplicando migrações do banco de dados..."
python manage.py migrate --noinput
echo "  ✓ Migrações concluídas!"
echo ""

# -----------------------------------------------------------------------------
# 3. Coletar arquivos estáticos
# -----------------------------------------------------------------------------
echo "[3/4] Coletando arquivos estáticos..."
python manage.py collectstatic --noinput --clear
echo "  ✓ Arquivos estáticos coletados!"
echo ""

# -----------------------------------------------------------------------------
# 4. Criar superusuário (apenas se não existir)
# -----------------------------------------------------------------------------
echo "[4/4] Verificando superusuário '${DJANGO_SUPERUSER_USERNAME}'..."

python manage.py shell << EOF
from django.contrib.auth import get_user_model
User = get_user_model()

username = "${DJANGO_SUPERUSER_USERNAME}"
email    = "${DJANGO_SUPERUSER_EMAIL}"
password = "${DJANGO_SUPERUSER_PASSWORD}"

if User.objects.filter(username=username).exists():
    print(f"  › Superusuário '{username}' já existe. Nenhuma ação necessária.")
else:
    User.objects.create_superuser(username=username, email=email, password=password)
    print(f"  ✓ Superusuário '{username}' criado com sucesso!")
EOF

echo ""
echo "============================================="
echo "  ✅ Inicialização concluída com sucesso!"
echo "============================================="
echo ""
echo "  › Interface:  ${TAIGA_SITES_SCHEME}://${TAIGA_SITES_DOMAIN}:9000"
echo "  › Admin:      ${TAIGA_SITES_SCHEME}://${TAIGA_SITES_DOMAIN}:8000/admin"
echo "  › Usuário:    ${DJANGO_SUPERUSER_USERNAME}"
echo ""
