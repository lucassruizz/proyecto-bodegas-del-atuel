# Proyecto Bodegas del Atuel

Trabajo práctico integrador de Bases de Datos de la UTN San Rafael, 2026. El sistema registra la producción, el stock y las ventas de una bodega con varias salas. PostgreSQL controla las reglas de negocio y la API REST permite operar sobre la base.

**Integrantes**

- Lucas Ruiz
- Ramiro Juarez
- Joaquin Spotorno

## Etapas integradas

| Etapa | Contenido |
| --- | --- |
| 1. Diseño | [DER](docs/der/), [esquema relacional](docs/esquema-relacional/), [normalización](docs/normalizacion/), [diccionario de datos](docs/diccionario-datos/) y [decisiones de diseño](docs/decisiones-dise%C3%B1o/) |
| 2. Implementación | [Migraciones SQL](db/migrations/), [pruebas de integridad](db/tests/db_tests.sql) y [trazabilidad de reglas](docs/etapa-2/trazabilidad.md) |
| 3. Carga masiva | [Script y catálogos](db/seed/) y [guía de carga](docs/etapa-3/README.md) |
| 4. Rendimiento | [Consultas y mediciones](db/rendimiento/) e [informe con planes de ejecución](docs/etapa-4/README.md) |
| 5. Consultas SQL | [Scripts de consultas](consultas/) e [informe con evidencia](docs/etapa-5/README.md) |
| 6. API REST | [Arranque y pruebas](api/README.md), [guía de estudio](docs/etapa-6/README.md) y Swagger en `/docs` |

La carpeta [`front/`](front/) contiene los bocetos del frontend de la etapa 7.

## Requisitos y arranque local

Se necesita Docker con Docker Compose. PostgreSQL 16 y la API se ejecutan en contenedores. Para los scripts de carga y medición fuera de Docker se necesita Python 3.10 o posterior.

1. Copiar `.env.example` a `.env` y completar `POSTGRES_PASSWORD` y `DB_API_PASSWORD` con claves distintas.
2. Ejecutar `docker compose up --build`.
3. Abrir Swagger en [localhost:8000/docs](http://localhost:8000/docs) y consultar [localhost:8000/salud](http://localhost:8000/salud). Si cambiaste `API_PORT`, usá el puerto de tu `.env`.

## Migraciones y carga

En un volumen nuevo, PostgreSQL ejecuta los archivos de `db/migrations/` en orden. Si ya tenés datos, seguí los [pasos para actualizar el volumen](api/README.md#volumen-existente).

Para generar los datos de prueba, seguí la [guía de carga](docs/etapa-3/README.md) sobre una base vacía con las migraciones aplicadas. La [guía de rendimiento](docs/etapa-4/README.md) explica cómo medir los índices sobre una base aparte.

## Pruebas

En una base recién migrada, antes de ejecutar la carga, corré desde la raíz:

```sh
docker compose exec -T db sh -c 'psql -X -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"' < db/tests/db_tests.sql
bash api/tests/probar.sh
```

El primer comando usa IDs fijos y revierte las filas al terminar. Usá una base nueva con secuencias recién inicializadas para repetirlo. El segundo levanta su propio entorno y lo elimina al terminar. Las [consultas de etapa 5](docs/etapa-5/README.md) se prueban sobre una base cargada.

El [informe final](docs/informe-final.md) reúne las decisiones de diseño, las pruebas y la evidencia de cada etapa trabajada.
