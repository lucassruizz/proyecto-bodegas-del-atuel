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
| 6. API REST | [Arranque y pruebas](api/README.md), [guía de estudio](docs/etapa-6/README.md) y Swagger en `/docs` |

La carpeta [`front/`](front/) está reservada para la etapa 7.

## Arranque local

1. Copiar `.env.example` a `.env` y completar `POSTGRES_PASSWORD` y `DB_API_PASSWORD`.
2. Ejecutar `docker compose up --build`. En un volumen nuevo se aplican las migraciones y se configura el rol de la API.
3. Abrir [Swagger](http://localhost:8000/docs). Si ya tenés un volumen de la etapa 5, seguir los [pasos para actualizarlo](api/README.md#volumen-existente-de-la-etapa-5).

Para cargar datos históricos o reproducir las mediciones, seguir las guías de las etapas 3 y 4 sobre una base de prueba.
