# Bodegas del Atuel · Etapa 4

## Base y método

El cargador completo de esa rama se ejecutó con semilla 2026 y sus controles de stock, totales e integridad finalizaron
correctamente. Se obtuvieron 20.000 clientes, 150.000 comprobantes, 500.000
renglones, 900 transferencias y 15 salas.

La prueba se ejecutó en PostgreSQL 16.15 (Linux ARM64 en Docker Desktop,
`shared_buffers = 128 MB`, `work_mem = 4 MB`). Se hizo un `VACUUM (ANALYZE)`
de las dos tablas grandes al terminar la carga y un `ANALYZE` antes de cada
ronda. La línea de base tenía solo índices de PK y UNIQUE. La ronda final usó
las mismas filas y consultas con los cinco índices de la migración 008.

Cada consulta se ejecutó una vez para obtener y calentar su resultado, y luego
siete veces con `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)`. La tabla usa la mediana
de **Execution Time** e identifica el recorrido del mismo plan mediano. El
script compara el resultado completo y ordenado en ambas rondas. Las mediciones
representan esta carga y el estado de caché del ensayo.

S3 toma la sala 1 y los últimos siete días del historial. S8 toma los últimos
tres meses móviles. Ambas usan el 8 de noviembre de 2026 como límite exclusivo
porque la última venta de la carga es del día anterior. S12a elige la bodega
`30000000000`, que tiene 30 vinos. S12b mide la segunda parte de la misma
consigna. S5 y S1 permiten observar un predicado selectivo y un recorrido de
toda la tabla, respectivamente.

## Comparación de consultas

| Consulta y tabla | Antes (ms) | Después (ms) | Cambio | Recorrido y filas antes | Recorrido y filas después | Bloques compartidos antes → después |
|---|---:|---:|---:|---|---|---:|
| S3 · `comprobante` | 3,954 | 0,093 | −97,6 % | Seq Scan paralelo · 150.000 | Index Only Scan · 43 | 3.245 → 263 |
| S8 · `comprobante` | 6,149 | 1,340 | −78,2 % | Seq Scan · 150.000 | Index Only Scan · 8.529 | 2.949 → 46 |
| S12a · `renglon_comprobante` | 75,056 | 48,170 | −35,8 % | Seq Scan · 500.000 | Index Only Scan · ≈50.340 | 11.287 → 3.237 |
| S12b · `renglon_comprobante` | 86,843 | 66,467 | −23,5 % | Seq Scan · 500.000 | Index Only Scan · ≈124.950 | 11.344 → 3.716 |
| S5 · `transferencia` | 0,033 | 0,014 | −57,6 % | Seq Scan · 900 | Index Only Scan · 0 | 9 → 2 |
| S1 · `renglon_comprobante` | 34,065 | 43,074 | +26,4 % | Seq Scan paralelo · ≈500.000 | Seq Scan paralelo · ≈500.000 | 8.355 → 8.355 |

Los números de filas se refieren al recorrido de la tabla indicada. Cuando
hay bucles, PostgreSQL muestra un promedio redondeado por bucle y el producto
es aproximado. En el escaneo secuencial se cuentan tanto las filas emitidas
como las eliminadas por el filtro. Los bloques son la suma de aciertos en caché compartida y bloques leídos por el plan
completo. Las filas de salida se incluyen en el resumen del anexo.
S12a devuelve cero clientes que hayan comprado los 30 vinos de la bodega.
S12b devuelve 22 clientes que nunca compraron tintos. S5 devuelve las 15 salas
empatadas en cero pendientes, porque la carga histórica tiene todas las
transferencias procesadas.

## Índices elegidos

- **`idx_comprobante_sala_fecha`** (5.968 KiB). En S3 se fija primero `idSalaVenta` por igualdad y luego se acota el rango de `fecha` dentro de esa sala. El orden permite buscar un tramo contiguo del B-tree. `INCLUDE (idCliente)` aporta el dato del join sin incorporarlo al orden de búsqueda.

- **`idx_comprobante_fecha_ventas`** (5.960 KiB). En S8 el rango de `fecha` abarca todas las salas. `INCLUDE (idSalaVenta, total)` permite agrupar y sumar con los valores del índice. En el plan mediano hubo cero accesos al heap.

- **`idx_comprobante_cliente`** (1.504 KiB). B-tree sobre la FK `idCliente`. Permite buscar los comprobantes de un cliente y localizar sus referencias al actualizar o borrar un cliente. La PK de comprobante está ordenada por número y el índice de S3 solo incluye el cliente como dato de cobertura.

- **`idx_renglon_comprobante_vino`** (15.424 KiB). B-tree sobre la FK `codigoVino` seguido de `numeroComprobante`. S12 busca por vino y obtiene del índice el número para el join. La PK de renglón tiene el orden inverso.

- **`idx_transferencia_pendiente_sala`** (8 KiB). B-tree parcial para S5. Indexa por sala las filas que cumplen `estado <> 'procesado'`. El conjunto indexado está vacío en la carga histórica y la consulta encuentra cero pendientes sin visitar las 900 filas.

### Índice evaluado y descartado

Se probó un BRIN de 32 páginas por rango sobre `comprobante(fecha)` antes de
instalar 008. Ocupó 24 KiB y bajó los bloques compartidos de 2.949 a 1.255, pero
su `Bitmap Heap Scan` revalidó 112.940 filas que quedaron fuera del rango. La
mediana subió de 6,149 ms a 7,053 ms. Un BRIN conserva mínimos y máximos por
rango físico. En esta carga quedaron muchas páginas candidatas aunque solo
8.529 filas pertenecían al trimestre. El B-tree con cobertura ocupa más
espacio y resolvió el mismo resultado en 1,340 ms con 46 bloques compartidos.
Por eso se retiró el BRIN de prueba y se conservó el B-tree.

### Cuándo el planificador prefiere un recorrido secuencial

S1 necesita la cantidad de botellas de los 500.000 renglones. El índice de
renglones por vino existe, pero no cubre `cantidad` y la consulta no tiene un
predicado selectivo. El plan final usa un recorrido secuencial paralelo y
agrega los datos antes del ranking. El total de bloques compartidos
consultados coincide con el del plan inicial. La diferencia en tiempos entre
las dos rondas de S1 no se atribuye a los índices nuevos.

## Costo de escritura

Se cargaron los mismos datos con un `INSERT INTO ... SELECT ... ORDER BY ...`
sobre dos copias ordinarias de cada tabla grande. Ambas conservan los CHECK
y los índices de las restricciones. La segunda agrega los índices de la
migración 008 correspondientes a esa tabla. La prueba aísla el mantenimiento
de índices durante la sentencia. Las copias carecen de FK y triggers, y la
medición excluye la creación de tablas, `TRUNCATE` y el tiempo de confirmación
de la transacción. Se vació cada copia antes de insertar y se alternó qué
variante se ejecutaba primero. Se muestran las medianas de siete intentos y el
WAL del plan mediano.

| Tabla | Filas cargadas | Antes (ms) | Después (ms) | Aumento | WAL antes → después (MiB) |
|---|---:|---:|---:|---:|---:|
| `comprobante` | 150.000 | 197,057 | 576,539 | +192,6 % | 24,7 → 63,5 |
| `renglon_comprobante` | 500.000 | 662,596 | 1.198,813 | +80,9 % | 79,3 → 120,1 |

La copia de comprobante mantiene tres índices adicionales por fila. La de
renglones mantiene uno adicional. En ambos casos aumentaron el tiempo de carga
y el WAL generado. El tamaño agregado de los cinco índices es de 28,2 MiB.

## Anexo · Planes completos

- [Resumen con las siete mediciones por variante](planes/resumen.json)
- S3 · [Antes](planes/S3_antes.json) · [Después](planes/S3_despues.json)
- S8 · [Antes](planes/S8_antes.json) · [BRIN descartado](planes/S8_descarte.json) · [Después](planes/S8_despues.json)
- S12a · [Antes](planes/S12a_antes.json) · [Después](planes/S12a_despues.json)
- S12b · [Antes](planes/S12b_antes.json) · [Después](planes/S12b_despues.json)
- S5 · [Antes](planes/S5_antes.json) · [Después](planes/S5_despues.json)
- S1 · [Antes](planes/S1_antes.json) · [Después](planes/S1_despues.json)
- Carga de comprobantes · [Antes](planes/carga_comprobante_antes.json) · [Después](planes/carga_comprobante_despues.json)
- Carga de renglones · [Antes](planes/carga_renglon_comprobante_antes.json) · [Después](planes/carga_renglon_comprobante_despues.json)

## Reproducción

Se necesita Python 3.10 o superior y PostgreSQL. Usar una base vacía y aislada,
conectarse como su propietario y ejecutar los comandos desde la raíz del
proyecto. El ejemplo supone que PostgreSQL ya está iniciado y que el usuario
puede crear la base.

```bash
export PGHOST=localhost PGPORT=5432 PGUSER=postgres PGDATABASE=bodegas_etapa4
printf 'Contraseña de PostgreSQL: '
read -rs PGPASSWORD
printf '\n'
export PGPASSWORD
createdb "$PGDATABASE" || exit 1
for migracion in db/migrations/00[1-6]*.sql; do
  psql -X -v ON_ERROR_STOP=1 -f "$migracion" || exit 1
done

python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r db/seed/requirements.txt

DB_HOST="$PGHOST" DB_PORT="$PGPORT" DB_NAME="$PGDATABASE" \
  DB_USER="$PGUSER" DB_PASSWORD="$PGPASSWORD" \
  python db/seed/carga.py || exit 1

python db/rendimiento/medir.py mediciones-etapa-4
```

El cargador escribe su reporte de tiempos y controles junto al script. Para
Windows, su [guía de carga](../etapa-3/README.md)
incluye los comandos de PowerShell. La migración 007 se reserva para la
configuración de permisos. La medición usa al propietario de la base local,
porque necesita cargar el historial, crear índices y preparar tablas de prueba.

El script verifica que la base comience únicamente con índices de PK y UNIQUE.
Aplica 008 después de obtener la línea de base, deja instalados los cinco
índices y genera los planes en la carpeta indicada. Para repetir la comparación,
usar otra base recién cargada. Para instalar solamente los índices sobre una
base que ya tiene los datos, ejecutar
`psql -X -v ON_ERROR_STOP=1 -1 -f db/migrations/008_indices.sql` con el
propietario y luego `ANALYZE`.

## Prueba histórica de compatibilidad

Se ejecutó `db/tests/db_tests.sql` en dos bases limpias, una con las migraciones
001–006 y otra con 001–006 y 008. Ambas alcanzaron las pruebas de ventas y
fallaron en el mismo punto, al validar una composición pendiente del vino 20
en RN-05. La falla se reproduce en la versión de etapa 2 por sí sola. La carga
histórica de etapa 3 y el ensayo de rendimiento sí finalizaron correctamente.

Para ejecutar la suite SQL actual se necesita una base vacía con las migraciones 001 a 011. La prueba de rendimiento anterior conserva su entorno de medición, separado de la suite de integridad.
