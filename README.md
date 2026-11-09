# Proyecto Bodegas del Atuel

Trabajo práctico integrador de Bases de Datos de la UTN San Rafael, 2026.

**Integrantes**

- Lucas Ruiz
- Ramiro Juarez
- Joaquin Spotorno

## Etapas integradas

| Etapa | Contenido |
| --- | --- |
| 1. Diseño | [DER](docs/der/), [esquema relacional](docs/esquema-relacional/), [normalización](docs/normalizacion/), [diccionario de datos](docs/diccionario-datos/) y [decisiones de diseño](docs/decisiones-dise%C3%B1o/) |
| 2. Implementación | [Migraciones SQL](db/migrations/) y [pruebas de integridad](db/tests/db_tests.sql) |
| 3. Carga masiva | [Script y catálogos](db/seed/) y [guía de carga](docs/etapa-3/README.md) |
| 4. Rendimiento | [Consultas y mediciones](db/rendimiento/) e [informe con planes de ejecución](docs/etapa-4/README.md) |
| 5. Consultas SQL | [Scripts de consultas](consultas/) e [informe con evidencia](docs/etapa-5/README.md) |

Las carpetas [`api/`](api/) y [`front/`](front/) están reservadas para las etapas 6 y 7.

## PostgreSQL local

1. Copiar `.env.example` a `.env` y completar `POSTGRES_PASSWORD`. Si el puerto 5432 está ocupado, cambiar `POSTGRES_PORT`.
2. Ejecutar `docker compose up -d`. PostgreSQL aplica las migraciones 001 a 008 en orden al inicializar el volumen.
3. Con los valores de ejemplo, abrir una sesión con `docker compose exec db psql -U postgres -d bodegas`. Ajustar el usuario y la base si se cambiaron en `.env`.

Para cargar datos históricos o reproducir las mediciones, seguir las guías de las etapas 3 y 4 sobre una base de prueba.
