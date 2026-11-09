#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."

# Proyecto y volumen aislados del entorno de desarrollo.
proyecto="bodegas-api-test-$$"
export POSTGRES_DB=bodegas
export POSTGRES_USER=postgres
export POSTGRES_PASSWORD="$(openssl rand -hex 24)"
export DB_API_PASSWORD="$(openssl rand -hex 24)"
export POSTGRES_PORT="${TEST_POSTGRES_PORT:-15487}"
export API_PORT="${TEST_API_PORT:-18087}"
compose=(docker compose -p "$proyecto")
trap '"${compose[@]}" down -v --remove-orphans' EXIT

"${compose[@]}" up -d --build --wait
"${compose[@]}" exec -T db psql -X -v ON_ERROR_STOP=1 -U postgres -d bodegas < api/tests/datos.sql
"${compose[@]}" run --rm --no-deps -T --user root -v "$PWD/api/tests:/pruebas:ro" api sh -ec '
    pip install --quiet -r /pruebas/requirements.txt
    python -m pytest -q -s -p no:cacheprovider /pruebas
'
