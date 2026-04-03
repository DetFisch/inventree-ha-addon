#!/bin/bash

set -Eeuo pipefail

CONFIG_PATH="/data/options.json"
PUBLIC_CONFIG_DIR="/config"
STATE_DIR="/data/internal"
POSTGRES_DATA_DIR="${STATE_DIR}/postgres"
POSTGRES_RUN_DIR="${STATE_DIR}/postgres-run"
REDIS_DIR="${STATE_DIR}/redis"
NGINX_CONFIG="/tmp/nginx.conf"

POSTGRES_PORT="5432"
REDIS_PORT="6379"
NGINX_PORT="8000"
INVENTREE_INTERNAL_PORT="8001"

DB_NAME="inventree"
DB_USER="inventree"
DB_PASSWORD_FILE="${STATE_DIR}/db_password.txt"
ADMIN_PASSWORD_FILE="${PUBLIC_CONFIG_DIR}/admin_password.txt"

declare -a CHILD_PIDS=()

log() {
    echo "[inventree-addon] $*"
}

warn() {
    echo "[inventree-addon] WARNING: $*" >&2
}

fatal() {
    echo "[inventree-addon] ERROR: $*" >&2
    exit 1
}

cleanup_children() {
    local pid

    for pid in "${CHILD_PIDS[@]:-}"; do
        if kill -0 "${pid}" 2>/dev/null; then
            kill "${pid}" 2>/dev/null || true
        fi
    done

    wait || true
    CHILD_PIDS=()
}

on_exit() {
    local status=$?
    trap - EXIT
    cleanup_children
    exit "${status}"
}

on_term() {
    log "Received stop signal"
    exit 0
}

trap on_exit EXIT
trap on_term INT TERM

ensure_dir() {
    mkdir -p "$1"
}

json_get() {
    local key=$1
    local fallback=$2
    local value

    if [ ! -f "${CONFIG_PATH}" ]; then
        printf '%s\n' "${fallback}"
        return
    fi

    value="$(jq -r "${key} // empty" "${CONFIG_PATH}" 2>/dev/null || true)"

    if [ -z "${value}" ] || [ "${value}" = "null" ]; then
        printf '%s\n' "${fallback}"
    else
        printf '%s\n' "${value}"
    fi
}

json_bool_to_env() {
    case "${1,,}" in
        1|true|yes|on)
            printf 'True\n'
            ;;
        *)
            printf 'False\n'
            ;;
    esac
}

random_string() {
    tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "$1" || true
}

load_options() {
    SITE_URL="$(json_get '.site_url' '')"
    TIMEZONE="$(json_get '.timezone' 'UTC')"
    ADMIN_USER="$(json_get '.admin_user' 'admin')"
    ADMIN_EMAIL="$(json_get '.admin_email' 'admin@example.com')"
    ADMIN_PASSWORD="$(json_get '.admin_password' '')"
    LOG_LEVEL="$(json_get '.log_level' 'WARNING')"
    UPLOAD_LIMIT_MB="$(json_get '.upload_limit_mb' '100')"
    PLUGINS_ENABLED_RAW="$(json_get '.plugins_enabled' 'true')"
    AUTO_UPDATE_RAW="$(json_get '.auto_update' 'true')"

    if [ -z "${SITE_URL}" ]; then
        fatal "site_url must be configured with the full URL used to access InvenTree"
    fi

    case "${SITE_URL}" in
        http://*|https://*)
            ;;
        *)
            fatal "site_url must start with http:// or https://"
            ;;
    esac

    if [ -z "${TIMEZONE}" ]; then
        TIMEZONE="UTC"
    fi

    LOG_LEVEL="${LOG_LEVEL^^}"

    if [ -z "${ADMIN_USER}" ]; then
        ADMIN_USER="admin"
    fi

    if [ -z "${ADMIN_EMAIL}" ]; then
        ADMIN_EMAIL="admin@example.com"
    fi

    case "${UPLOAD_LIMIT_MB}" in
        ''|*[!0-9]*)
            UPLOAD_LIMIT_MB="100"
            ;;
    esac

    PLUGINS_ENABLED="$(json_bool_to_env "${PLUGINS_ENABLED_RAW}")"
    AUTO_UPDATE="$(json_bool_to_env "${AUTO_UPDATE_RAW}")"
}

prepare_layout() {
    ensure_dir "${STATE_DIR}"
    ensure_dir "${POSTGRES_DATA_DIR}"
    ensure_dir "${POSTGRES_RUN_DIR}"
    ensure_dir "${REDIS_DIR}"
    ensure_dir "/data/static"
    ensure_dir "/data/media"
    ensure_dir "/data/backup"
    ensure_dir "/data/plugins"
    ensure_dir "${PUBLIC_CONFIG_DIR}"

    # Allow service users to traverse into their owned subdirectories below /data/internal.
    # Sensitive files inside remain protected by their own file modes.
    chmod 711 "${STATE_DIR}"
}

prepare_passwords() {
    if [ ! -s "${DB_PASSWORD_FILE}" ]; then
        random_string 32 > "${DB_PASSWORD_FILE}"
        chmod 600 "${DB_PASSWORD_FILE}"
    fi

    DB_PASSWORD="$(tr -d '\r\n' < "${DB_PASSWORD_FILE}")"

    if [ -n "${ADMIN_PASSWORD}" ]; then
        unset INVENTREE_ADMIN_PASSWORD_FILE || true
        export INVENTREE_ADMIN_PASSWORD="${ADMIN_PASSWORD}"
        rm -f "${ADMIN_PASSWORD_FILE}"
    else
        unset INVENTREE_ADMIN_PASSWORD || true
        if [ ! -s "${ADMIN_PASSWORD_FILE}" ]; then
            random_string 24 > "${ADMIN_PASSWORD_FILE}"
            chmod 600 "${ADMIN_PASSWORD_FILE}"
            log "Generated initial admin password at /config/admin_password.txt"
        fi
        export INVENTREE_ADMIN_PASSWORD_FILE="${ADMIN_PASSWORD_FILE}"
    fi
}

detect_worker_counts() {
    local cores

    cores="$(nproc)"

    if [ "${cores}" -lt 2 ]; then
        GUNICORN_WORKERS="2"
    elif [ "${cores}" -gt 4 ]; then
        GUNICORN_WORKERS="4"
    else
        GUNICORN_WORKERS="${cores}"
    fi

    BACKGROUND_WORKERS="${GUNICORN_WORKERS}"
}

export_inventree_env() {
    detect_worker_counts

    export TZ="${TIMEZONE}"
    export INVENTREE_SITE_URL="${SITE_URL}"
    export INVENTREE_TIMEZONE="${TIMEZONE}"
    export INVENTREE_LOG_LEVEL="${LOG_LEVEL}"
    export INVENTREE_PLUGINS_ENABLED="${PLUGINS_ENABLED}"
    export INVENTREE_AUTO_UPDATE="${AUTO_UPDATE}"
    export INVENTREE_ADMIN_USER="${ADMIN_USER}"
    export INVENTREE_ADMIN_EMAIL="${ADMIN_EMAIL}"
    export INVENTREE_DB_ENGINE="postgresql"
    export INVENTREE_DB_NAME="${DB_NAME}"
    export INVENTREE_DB_HOST="127.0.0.1"
    export INVENTREE_DB_PORT="${POSTGRES_PORT}"
    export INVENTREE_DB_USER="${DB_USER}"
    export INVENTREE_DB_PASSWORD="${DB_PASSWORD}"
    export INVENTREE_CACHE_ENABLED="True"
    export INVENTREE_CACHE_HOST="127.0.0.1"
    export INVENTREE_CACHE_PORT="${REDIS_PORT}"
    export INVENTREE_USE_X_FORWARDED_HOST="True"
    export INVENTREE_USE_X_FORWARDED_PORT="True"
    export INVENTREE_USE_X_FORWARDED_PROTO="True"
    export INVENTREE_WEB_ADDR="127.0.0.1"
    export INVENTREE_WEB_PORT="${INVENTREE_INTERNAL_PORT}"
    export INVENTREE_GUNICORN_TIMEOUT="120"
    export INVENTREE_GUNICORN_WORKERS="${GUNICORN_WORKERS}"
    export INVENTREE_BACKGROUND_WORKERS="${BACKGROUND_WORKERS}"
}

find_postgres_binary_dir() {
    local postgres_bin

    postgres_bin="$(command -v postgres || true)"

    if [ -z "${postgres_bin}" ]; then
        postgres_bin="$(find /usr/lib/postgresql -type f -name postgres | sort | tail -n1)"
    fi

    if [ -z "${postgres_bin}" ]; then
        fatal "Could not locate postgres binary"
    fi

    dirname "${postgres_bin}"
}

init_postgres() {
    local pg_bin_dir

    pg_bin_dir="$(find_postgres_binary_dir)"
    INITDB_BIN="${pg_bin_dir}/initdb"
    POSTGRES_BIN="${pg_bin_dir}/postgres"
    PG_ISREADY_BIN="${pg_bin_dir}/pg_isready"
    PSQL_BIN="${pg_bin_dir}/psql"

    chown -R postgres:postgres "${POSTGRES_DATA_DIR}" "${POSTGRES_RUN_DIR}"

    if [ ! -s "${POSTGRES_DATA_DIR}/PG_VERSION" ]; then
        log "Initializing PostgreSQL data directory"
        gosu postgres "${INITDB_BIN}" -D "${POSTGRES_DATA_DIR}" --auth-local=trust --auth-host=scram-sha-256 >/dev/stdout
    fi
}

start_postgres() {
    log "Starting PostgreSQL"

    gosu postgres "${POSTGRES_BIN}" \
        -D "${POSTGRES_DATA_DIR}" \
        -c "listen_addresses=127.0.0.1" \
        -c "port=${POSTGRES_PORT}" \
        -c "unix_socket_directories=${POSTGRES_RUN_DIR}" \
        -c "logging_collector=off" \
        &

    CHILD_PIDS+=("$!")
}

wait_for_postgres() {
    local attempt

    for attempt in $(seq 1 60); do
        if gosu postgres "${PG_ISREADY_BIN}" -h 127.0.0.1 -p "${POSTGRES_PORT}" -U postgres >/dev/null 2>&1; then
            log "PostgreSQL is ready"
            return
        fi
        sleep 1
    done

    fatal "PostgreSQL did not become ready in time"
}

ensure_database() {
    local role_exists
    local db_exists

    role_exists="$(
        gosu postgres "${PSQL_BIN}" -h "${POSTGRES_RUN_DIR}" -p "${POSTGRES_PORT}" -tAc "SELECT 1 FROM pg_roles WHERE rolname='${DB_USER}'" postgres \
            | tr -d '[:space:]'
    )"

    if [ "${role_exists}" != "1" ]; then
        log "Creating PostgreSQL role ${DB_USER}"
        gosu postgres "${PSQL_BIN}" -h "${POSTGRES_RUN_DIR}" -p "${POSTGRES_PORT}" -v ON_ERROR_STOP=1 postgres \
            -c "CREATE ROLE ${DB_USER} WITH LOGIN PASSWORD '${DB_PASSWORD}';"
    fi

    db_exists="$(
        gosu postgres "${PSQL_BIN}" -h "${POSTGRES_RUN_DIR}" -p "${POSTGRES_PORT}" -tAc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" postgres \
            | tr -d '[:space:]'
    )"

    if [ "${db_exists}" != "1" ]; then
        log "Creating PostgreSQL database ${DB_NAME}"
        gosu postgres "${PSQL_BIN}" -h "${POSTGRES_RUN_DIR}" -p "${POSTGRES_PORT}" -v ON_ERROR_STOP=1 postgres \
            -c "CREATE DATABASE ${DB_NAME} OWNER ${DB_USER};"
    fi
}

write_redis_config() {
    cat > "${REDIS_DIR}/redis.conf" <<EOF
bind 127.0.0.1
port ${REDIS_PORT}
dir ${REDIS_DIR}
appendonly yes
daemonize no
protected-mode no
save 900 1
save 300 10
save 60 10000
loglevel notice
logfile ""
EOF
}

start_redis() {
    write_redis_config

    log "Starting Redis"
    redis-server "${REDIS_DIR}/redis.conf" &
    CHILD_PIDS+=("$!")
}

wait_for_redis() {
    local attempt

    for attempt in $(seq 1 30); do
        if redis-cli -h 127.0.0.1 -p "${REDIS_PORT}" ping 2>/dev/null | grep -q PONG; then
            log "Redis is ready"
            return
        fi
        sleep 1
    done

    fatal "Redis did not become ready in time"
}

bootstrap_inventree() {
    log "Running InvenTree bootstrap tasks"

    cd /home/inventree/src/backend/InvenTree

    python manage.py wait_for_db
    python manage.py migrate --noinput --run-syncdb
    python manage.py remove_stale_contenttypes --include-stale-apps --no-input || warn "remove_stale_contenttypes failed"
    python manage.py collectstatic --noinput --clear

    if [ "${PLUGINS_ENABLED}" = "True" ]; then
        python manage.py collectplugins || warn "collectplugins failed"
    fi

    python manage.py rebuild_models || warn "rebuild_models failed"
    python manage.py rebuild_thumbnails || warn "rebuild_thumbnails failed"
}

write_nginx_config() {
    cat > "${NGINX_CONFIG}" <<EOF
worker_processes auto;
pid /tmp/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    sendfile on;
    tcp_nopush on;
    keepalive_timeout 65;
    access_log /dev/stdout;
    error_log /dev/stderr info;
    client_max_body_size ${UPLOAD_LIMIT_MB}m;

    map \$http_upgrade \$connection_upgrade {
        default upgrade;
        '' close;
    }

    map \$http_x_forwarded_proto \$inventree_forwarded_proto {
        default \$scheme;
        ~.+ \$http_x_forwarded_proto;
    }

    map \$http_x_forwarded_host \$inventree_forwarded_host {
        default \$host;
        ~.+ \$http_x_forwarded_host;
    }

    map \$http_x_forwarded_port \$inventree_forwarded_port {
        default \$server_port;
        ~.+ \$http_x_forwarded_port;
    }

    upstream inventree_backend {
        server 127.0.0.1:${INVENTREE_INTERNAL_PORT};
        keepalive 16;
    }

    server {
        listen 0.0.0.0:${NGINX_PORT};
        server_name _;

        location = /_inventree_auth {
            internal;
            proxy_pass http://inventree_backend/auth/;
            proxy_pass_request_body off;
            proxy_set_header Content-Length "";
            proxy_set_header Host \$inventree_forwarded_host;
            proxy_set_header X-Forwarded-Host \$inventree_forwarded_host;
            proxy_set_header X-Forwarded-Port \$inventree_forwarded_port;
            proxy_set_header X-Forwarded-Proto \$inventree_forwarded_proto;
        }

        location /static/ {
            alias /data/static/;
            expires 7d;
            add_header Cache-Control "public, max-age=604800, immutable";
        }

        location /media/ {
            auth_request /_inventree_auth;
            alias /data/media/;
            expires off;
            add_header Cache-Control "private, no-store";
        }

        location / {
            proxy_pass http://inventree_backend;
            proxy_http_version 1.1;
            proxy_redirect off;
            proxy_buffering off;
            proxy_set_header Host \$inventree_forwarded_host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Host \$inventree_forwarded_host;
            proxy_set_header X-Forwarded-Port \$inventree_forwarded_port;
            proxy_set_header X-Forwarded-Proto \$inventree_forwarded_proto;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection \$connection_upgrade;
        }
    }
}
EOF
}

start_gunicorn() {
    log "Starting InvenTree web server"

    cd /home/inventree
    gunicorn \
        -c /home/inventree/gunicorn.conf.py \
        InvenTree.wsgi \
        -b "127.0.0.1:${INVENTREE_INTERNAL_PORT}" \
        --chdir /home/inventree/src/backend/InvenTree \
        &

    CHILD_PIDS+=("$!")
}

start_worker() {
    log "Starting InvenTree worker"

    cd /home/inventree
    invoke worker &
    CHILD_PIDS+=("$!")
}

start_nginx() {
    write_nginx_config

    log "Starting Nginx reverse proxy"
    nginx -g "daemon off;" -c "${NGINX_CONFIG}" &
    CHILD_PIDS+=("$!")
}

main() {
    load_options
    prepare_layout
    prepare_passwords
    export_inventree_env

    init_postgres
    start_postgres
    wait_for_postgres
    ensure_database

    start_redis
    wait_for_redis

    bootstrap_inventree

    start_gunicorn
    start_worker
    start_nginx

    log "InvenTree is starting on port ${NGINX_PORT}"
    wait -n "${CHILD_PIDS[@]}"
}

main "$@"
