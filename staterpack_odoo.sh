#!/usr/bin/env bash

set -e
clear

echo "======================================"
echo "      ODOO DOCKER STARTER GENERATOR"
echo "======================================"
echo ""

echo "1) Create New Project"
echo "2) Existing Project (already cloned)"
echo ""
read -p "Choose option (1/2): " PROJECT_TYPE

if [[ "$PROJECT_TYPE" != "1" && "$PROJECT_TYPE" != "2" ]]; then
  echo "Invalid option."
  exit 1
fi

echo ""
read -p "Project name (folder name): " PROJECT_NAME

if [[ -z "$PROJECT_NAME" ]]; then
  echo "Project name cannot be empty."
  exit 1
fi

echo ""
echo "Odoo Version Available:"
echo "14, 15, 16, 17, 18, latest"
read -p "Choose Odoo version (default latest): " ODOO_VERSION
ODOO_VERSION=${ODOO_VERSION:-latest}

if [[ "$ODOO_VERSION" != "latest" ]]; then
  if [[ "$ODOO_VERSION" =~ ^(14|15|16|17|18)$ ]]; then
    ODOO_VERSION="${ODOO_VERSION}.0"
  else
    echo "Invalid Odoo version. Allowed: 14-18 or latest."
    exit 1
  fi
fi

echo ""
echo "PostgreSQL Version Available:"
echo "12, 13, 14, 15, 16, latest"
read -p "Choose PostgreSQL version (default 15): " PG_VERSION
PG_VERSION=${PG_VERSION:-15}

if [[ "$PG_VERSION" != "latest" ]]; then
  if [[ "$PG_VERSION" =~ ^(12|13|14|15|16)$ ]]; then
    :
  else
    echo "Invalid PostgreSQL version. Allowed: 12-16 or latest."
    exit 1
  fi
fi

echo ""
read -p "Service name Odoo (default: odoo): " SERVICE_ODOO
read -p "Service name DB (default: db): " SERVICE_DB
SERVICE_ODOO=${SERVICE_ODOO:-odoo}
SERVICE_DB=${SERVICE_DB:-db}

read -s -p "Database password: " DB_PASSWORD
echo ""

if [[ -z "$DB_PASSWORD" ]]; then
  echo "Database password cannot be empty."
  exit 1
fi

CONTAINER_ODOO=${PROJECT_NAME}_${SERVICE_ODOO}
CONTAINER_DB=${PROJECT_NAME}_${SERVICE_DB}

if [[ "$PROJECT_TYPE" == "1" ]]; then
  read -p "Addons folder name (default: addons): " ADDONS_FOLDER
  ADDONS_FOLDER=${ADDONS_FOLDER:-addons}
  ADDONS_VOLUME="./${ADDONS_FOLDER}:/mnt/extra-addons"
else
  ADDONS_VOLUME="./${PROJECT_NAME}:/mnt/extra-addons"
fi

echo ""
echo "Creating project structure..."

mkdir -p ${PROJECT_NAME}/{config,secrets,tmp}
mkdir -p ${PROJECT_NAME}/var/lib/{odoo,postgresql}
mkdir -p ${PROJECT_NAME}/var/log/odoo

if [[ "$PROJECT_TYPE" == "1" ]]; then
  mkdir -p ${PROJECT_NAME}/${ADDONS_FOLDER}
fi

touch ${PROJECT_NAME}/var/log/odoo/odoo-server.log

cat > ${PROJECT_NAME}/config/odoo.conf <<EOF
[options]
addons_path = /mnt/extra-addons
admin_passwd = ${DB_PASSWORD}
db_name = False
db_host = ${SERVICE_DB}
db_port = 5432
db_user = odoo
db_password = ${DB_PASSWORD}
logfile = /var/log/odoo/odoo-server.log
log_level = info
EOF

echo "${DB_PASSWORD}" > ${PROJECT_NAME}/secrets/odoo_passwd
chmod 600 ${PROJECT_NAME}/secrets/odoo_passwd

cat > ${PROJECT_NAME}/.gitignore <<'EOF'
**/__pycache__/
*.yml
*.yaml
*.conf
Makefile
Makefile.*

config/
secrets/
var/
tmp/

.DS_Store
._*
.Spotlight-V100
.Trashes
ehthumbs.db
Thumbs.db
Desktop.ini

*.lnk
*.stackdump

*~
.fuse_hidden*
.directory
.Trash-*

.vscode/
.idea/
*.swp
*.swo
EOF

cat > ${PROJECT_NAME}/docker-compose.yml <<EOF
version: '3.8'

services:
  ${SERVICE_ODOO}:
    container_name: ${CONTAINER_ODOO}
    platform: linux/amd64
    image: odoo:${ODOO_VERSION}
    depends_on:
      - ${SERVICE_DB}
    ports:
      - "8110:8069"
    volumes:
      - ./var/lib/odoo:/var/lib/odoo
      - ./config:/etc/odoo
      - ${ADDONS_VOLUME}
      - ./var/log/odoo/odoo-server.log:/var/log/odoo/odoo-server.log
      - ./tmp:/tmp
    secrets:
      - postgresql_password

  ${SERVICE_DB}:
    container_name: ${CONTAINER_DB}
    image: postgres:${PG_VERSION}
    ports:
      - "5435:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U odoo"]
      interval: 5s
      timeout: 5s
      retries: 5
    environment:
      POSTGRES_DB: postgres
      POSTGRES_USER: odoo
      POSTGRES_PASSWORD_FILE: /run/secrets/postgresql_password
      PGDATA: /var/lib/postgresql/data/pgdata
    volumes:
      - ./var/lib/postgresql:/var/lib/postgresql/data/pgdata
    secrets:
      - postgresql_password

secrets:
  postgresql_password:
    file: ./secrets/odoo_passwd
EOF

# =============================
# MAKEFILE
# =============================

cat > ${PROJECT_NAME}/Makefile <<EOF
DOCKER = docker
DOCKER_COMPOSE = \${DOCKER} compose
CONTAINER_ODOO = ${CONTAINER_ODOO}
CONTAINER_DB = ${CONTAINER_DB}
POSTGRES_USER = odoo
POSTGRES_DB = postgres
SERVICE_ODOO = ${SERVICE_ODOO}
SERVICE_DB = ${SERVICE_DB}
DB_PASSWORD = ${DB_PASSWORD}

start:
	\${DOCKER_COMPOSE} up -d

stop:
	\${DOCKER_COMPOSE} stop

restart:
	\${DOCKER_COMPOSE} restart

remove:
	\${DOCKER_COMPOSE} down -v

status:
	\${DOCKER_COMPOSE} ps

console:
	\${DOCKER} exec -it \${CONTAINER_ODOO} bash

psql:
	\${DOCKER} exec -it \${CONTAINER_DB} psql -U \${POSTGRES_USER} -d \${POSTGRES_DB}

logs:
	@target="\$(word 2,\$(MAKECMDGOALS))"; \
	if [ "\$\$target" = "odoo" ]; then \
		\${DOCKER_COMPOSE} logs -f \${SERVICE_ODOO}; \
	elif [ "\$\$target" = "db" ]; then \
		\${DOCKER_COMPOSE} logs -f \${SERVICE_DB}; \
	else \
		echo "Use: make logs odoo | make logs db"; \
	fi

addon:
	@addon_name="\$(word 2,\$(MAKECMDGOALS))"; \
	if [ -z "\$\$addon_name" ]; then \
		echo "Usage: make addon <addon_name>"; exit 1; \
	fi; \
	\${DOCKER} exec -it \${CONTAINER_ODOO} odoo \
		--db_host=\${CONTAINER_DB} \
		-d \${POSTGRES_DB} \
		-r \${POSTGRES_USER} \
		-w \${DB_PASSWORD} \
		-u "\$\$addon_name" --no-http --stop-after-init

%:
	@:

.PHONY: start stop restart remove console psql logs addon
EOF

echo ""
echo "======================================"
echo "PROJECT ${PROJECT_NAME} CREATED SUCCESSFULLY"
echo ""
echo "Next steps:"
echo "cd ${PROJECT_NAME}"
echo "make start"
echo ""
echo "Odoo URL: http://localhost:8110"
echo "======================================"
