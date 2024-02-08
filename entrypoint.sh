#!/bin/bash

set -e

if [ -v PASSWORD_FILE ]; then
    PASSWORD="$(< $PASSWORD_FILE)"
fi

# set the postgres database host, port, user and password according to the environment
# and pass them as arguments to the odoo process if not present in the config file
: ${HOST:=${DB_PORT_5432_TCP_ADDR:='db'}}
: ${PORT:=${DB_PORT_5432_TCP_PORT:=5432}}
: ${USER:=${DB_ENV_POSTGRES_USER:=${POSTGRES_USER:='odoo'}}}
: ${PASSWORD:=${DB_ENV_POSTGRES_PASSWORD:=${POSTGRES_PASSWORD:='odoo'}}}

: ${ADMIN_PASS:='odoo'}
: ${LIST_DB:='False'}

: ${REDIS_ENABLED:='True'}
: ${REDIS_PORT:='6379'}
: ${REDIS_HOST:='redis'}
: ${REDIS_DB:='1'}
: ${REDIS_PASS:='redis'}

# Caminho para a pasta onde o repositório será clonado
ADDONS_DIR="/mnt/extra-addons"

git config --global --add safe.directory /mnt/extra-addons

if [ -d "$ADDONS_DIR/.git" ]; then
    echo "Atualizando o repositório existente em $ADDONS_DIR"
    cd $ADDONS_DIR
    git fetch origin main
    git reset --hard origin/main
fi


function update_or_add_config() {
    param="$1"
    value="$2"
    config_file="$3"

    if grep -q -E "^\s*\b${param}\b\s*=" "$config_file"; then
        # Parametro existe, atualizar valor
        sed -i "s/^\s*\b${param}\b\s*=.*/${param} = ${value}/" "$config_file"
    else
        # Parametro não existe, adicionar ao arquivo
        echo "${param} = ${value}" >> "$config_file"
    fi
}

# Adicionar ou atualizar parametros no arquivo de configuração
#update_or_add_config "db_name" "$DB_NAME" "$ODOO_RC"
update_or_add_config "admin_passwd" "$ADMIN_PASS" "$ODOO_RC"
update_or_add_config "list_db" "$LIST_DB" "$ODOO_RC"

update_or_add_config "enable_redis" "$REDIS_ENABLED" "$ODOO_RC"
update_or_add_config "redis_host" "$REDIS_HOST" "$ODOO_RC"
update_or_add_config "redis_port" "$REDIS_PORT" "$ODOO_RC"
update_or_add_config "redis_pass" "$REDIS_PASS" "$ODOO_RC"
update_or_add_config "redis_dbindex" "$REDIS_DB" "$ODOO_RC"


DB_ARGS=()
function check_config() {
    param="$1"
    value="$2"
    if grep -q -E "^\s*\b${param}\b\s*=" "$ODOO_RC" ; then       
        value=$(grep -E "^\s*\b${param}\b\s*=" "$ODOO_RC" |cut -d " " -f3|sed 's/["\n\r]//g')
    fi;
    DB_ARGS+=("--${param}")
    DB_ARGS+=("${value}")
}
check_config "db_host" "$HOST"
check_config "db_port" "$PORT"
check_config "db_user" "$USER"
check_config "db_password" "$PASSWORD"

pip3 install -r /$ADDONS_DIR/requirements.txt

case "$1" in
    -- | odoo)
        shift
        if [[ "$1" == "scaffold" ]] ; then
            exec odoo "$@"
        else
            wait-for-psql.py ${DB_ARGS[@]} --timeout=30
            exec odoo "$@" "${DB_ARGS[@]}"
        fi
        ;;
    -*)
        wait-for-psql.py ${DB_ARGS[@]} --timeout=30
        exec odoo "$@" "${DB_ARGS[@]}"
        ;;
    *)
        exec "$@"
esac

exit 1
