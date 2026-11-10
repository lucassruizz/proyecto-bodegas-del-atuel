# API REST · Etapa 6

API de Bodegas del Atuel implementada con FastAPI y psycopg. Usa el esquema, los triggers, los procedimientos y las vistas de PostgreSQL de las etapas anteriores.

## Arranque local

Desde la raíz del repositorio, copiar `.env.example` a `.env`, completar `POSTGRES_PASSWORD` y `DB_API_PASSWORD` con claves distintas y ejecutar:

```sh
docker compose up --build
```

Con los puertos del ejemplo, Swagger está en [localhost:8000/docs](http://localhost:8000/docs), el contrato en [localhost:8000/openapi.json](http://localhost:8000/openapi.json) y la comprobación de conexión en [localhost:8000/salud](http://localhost:8000/salud). Ambos servicios publican sus puertos en la interfaz local. Si cambiaste `API_PORT`, usá ese puerto en las URL.

La base nueva arranca con el esquema vacío. Para probar con datos históricos, seguir la [guía de carga](../docs/etapa-3/README.md). Los reportes de mes y trimestre usan `CURRENT_DATE`, así que una carga histórica puede quedar fuera del período. Las pruebas usan datos sintéticos de fecha actual.

### Volumen existente

Docker aplica las migraciones automáticamente al inicializar un volumen nuevo. Si el volumen ya tiene la etapa 6, aplicá 011 antes de reconstruir la API:

```sh
docker compose up -d db
docker compose exec -T db sh -c 'psql -X -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f /docker-entrypoint-initdb.d/011_integridad.sql'
docker compose up -d --build
```

Si el volumen todavía está en la etapa 5 (001–008), primero aplicá 009 y ejecutá 010:

```sh
docker compose exec -T db sh -c 'psql -X -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f /docker-entrypoint-initdb.d/009_compatibilidad_api.sql'
docker compose exec -T db bash /docker-entrypoint-initdb.d/010_configurar_api.sh
```

Luego aplicá 011 con el comando anterior. Cada migración se aplica una sola vez. Si 011 rechaza un departamento duplicado o una campaña que difiere del año de cosecha, corregí esos datos antes de volver a ejecutarla. La migración se revierte completa ante un error.

Si se cambia `DB_API_PASSWORD` después de inicializar la base, volver a ejecutar el script 010 y recrear el servicio API con Compose para que lea el nuevo valor.

## Pruebas automáticas

```sh
bash api/tests/probar.sh
```

El script crea una base y una API de prueba en un proyecto Compose separado, carga [datos pequeños](tests/datos.sql), ejecuta [las pruebas HTTP](tests/test_api.py) y elimina el volumen temporal. Usa los puertos 15487 y 18087 por defecto. Se pueden cambiar con `TEST_POSTGRES_PORT` y `TEST_API_PORT`.

La [guía de estudio](../docs/etapa-6/README.md) explica las rutas, las transacciones y cómo reproducir la prueba de inyección.
