#!/bin/bash

set -Eeuo pipefail

# ==========================================
# CONFIG BACKUP
# ==========================================

BASE_DIR="$HOME/project_backup"
BACKUP_DIR="$BASE_DIR/backups"
LOG_DIR="$BASE_DIR/logs"

DB_NAME="sakila"

CONTAINER_A="mysql-production"
CONTAINER_B="mysql-backup"

PASS_A="RootDemo_A_2026!"
PASS_B="RootDemo_B_2026!"

FECHA=$(date '+%Y-%m-%d_%H-%M-%S')

ARCHIVO="$BACKUP_DIR/${DB_NAME}_${FECHA}.sql"
LOG="$LOG_DIR/backup.log"

mkdir -p "$BACKUP_DIR" "$LOG_DIR"

# ==========================================
# FUNCTIONS
# ==========================================

registrar() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"
}

error() {
    registrar "ERROR: $*"
    exit 1
}

# ==========================================
# START OD BACKUP AND RESTORE
# ==========================================

registrar "=========================================="
registrar "START OF BACKUP AND RESTORE"
registrar "Database: $DB_NAME"

# Check that the servers exist and are active.

docker inspect "$CONTAINER_A" >/dev/null 2>&1 \
    || error "Production container does not exist."

docker inspect "$CONTAINER_B" >/dev/null 2>&1 \
    || error "Backup container does not exist."

docker exec "$CONTAINER_A" \
    mysqladmin ping -h 127.0.0.1 \
    --silent >/dev/null 2>&1 \
    || error "The production server is not responding."

docker exec "$CONTAINER_B" \
    mysqladmin ping -h 127.0.0.1 \
    --silent >/dev/null 2>&1 \
    || error "The backup server is not responding."

registrar "Both servers are available."

# ==========================================
# 1. GENERAR RESPALDO
# ==========================================

registrar "Generating backup from Database A."

docker exec "$CONTAINER_A" \
    mysqldump \
    --user=root \
    --password="$PASS_A" \
    --single-transaction \
    --routines \
    --events \
    --triggers \
    "$DB_NAME" > "$ARCHIVO" \
    || error "Backup generation failed."

# Check that the file exists and is not empty.

[ -s "$ARCHIVO" ] \
    || error "The backup file is empty."

registrar "Backup generated: $ARCHIVO"

# ==========================================
# 2. RESTORE INTO DATABASE B
# ==========================================

registrar "Preparing restore into Database B."

# Para una base de datos de laboratorio:
# se elimina el esquema de destino y se crea nuevamente.
#
# No ejecutar este procedimiento en produccion
# sin una estrategia de recuperacion aprobada.

docker exec "$CONTAINER_B" \
    mysql \
    --user=root \
    --password="$PASS_B" \
    -e "DROP DATABASE IF EXISTS \`$DB_NAME\`;
        CREATE DATABASE \`$DB_NAME\`;" \
    || error "The destination database could not be prepared."

registrar "Destination database prepared."

# Import the SQL file.

docker exec -i "$CONTAINER_B" \
    mysql \
    --user=root \
    --password="$PASS_B" \
    "$DB_NAME" < "$ARCHIVO" \
    || error "Restore of the backup failed."

registrar "Restore completed."

# ==========================================
# 3. VALIDATE THE RESTORE
# ==========================================

TABLAS=$(docker exec "$CONTAINER_B" \
    mysql \
    --user=root \
    --password="$PASS_B" \
    --batch \
    --skip-column-names \
    -e "SELECT COUNT(*)
        FROM information_schema.tables
        WHERE table_schema = '$DB_NAME'
        AND table_type = 'BASE TABLE';")

[ "$TABLAS" -gt 0 ] \
    || error "The restored database does not contain tables."

PELICULAS=$(docker exec "$CONTAINER_B" \
    mysql \
    --user=root \
    --password="$PASS_B" \
    --batch \
    --skip-column-names \
    -e "SELECT COUNT(*) FROM sakila.film;")

CLIENTES=$(docker exec "$CONTAINER_B" \
    mysql \
    --user=root \
    --password="$PASS_B" \
    --batch \
    --skip-column-names \
    -e "SELECT COUNT(*) FROM sakila.customer;")

registrar "Restored tables: $TABLAS"
registrar "Movies in destination: $PELICULAS"
registrar "Customers in destination: $CLIENTES"

[ "$PELICULAS" -gt 0 ] \
    || error "Movie validation failed."

[ "$CLIENTES" -gt 0 ] \
    || error "Customer validation failed."

registrar "VALIDATION SUCCESSFUL."
registrar "PROCESS COMPLETED SUCCESSFULLY."
registrar "=========================================="
