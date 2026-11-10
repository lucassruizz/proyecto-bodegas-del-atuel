#!/usr/bin/env bash
set -euo pipefail

: "${DB_API_PASSWORD:?Completar DB_API_PASSWORD en .env}"
psql -X --set=ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<'SQL'
\getenv clave_api DB_API_PASSWORD
SELECT format('ALTER ROLE bodega_api PASSWORD %L', :'clave_api') \gexec
SQL
