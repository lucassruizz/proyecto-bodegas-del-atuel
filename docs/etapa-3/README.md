# Carga masiva — Bodegas del Atuel

El [script de carga](../../db/seed/008_carga_masiva.py) usa los [catálogos CSV](../../db/seed/csv).
El [reporte original](reporte_carga.json) y su [verificación](verificacion.json)
documentan la ejecución de la etapa 3.

## Ejecución (PowerShell)

Usar Python 3.10 o superior y PostgreSQL 14 o superior. Crear una base de prueba
vacía y ejecutar las migraciones 001 a 005 en orden. Ejecutar el cargador
como propietario de las tablas. No usar una base con datos del grupo: el script
se detiene si encuentra cualquier tabla del proyecto con filas.

Ejecutar los comandos desde la raíz del repositorio.

```powershell
py -m pip install -r db/seed/requirements.txt
$env:DB_HOST = 'localhost'
$env:DB_PORT = '5432'
$env:DB_NAME = 'bodegas_prueba'
$env:DB_USER = 'propietario_de_la_base'
$env:DB_PASSWORD = Read-Host 'Contraseña'
py -X utf8 db/seed/008_carga_masiva.py
```

Se genera `db/seed/reporte_carga.json` al confirmar la transacción, con conteos y tiempos
reales. La comparación usa 2.000 filas idénticas en una tabla temporal: inserciones
individuales contra `executemany`, sin alterar los datos de negocio. La carga
principal usa COPY para las tablas grandes y RETURNING para obtener las claves
identity. La comparación mide esas dos técnicas, no el costo de los triggers.

## Orden y coherencia

Catálogos → encargados y salas → empleados y fincas → parcelas y bodegas → lotes
y análisis → vinos, composición, maridajes y auditoría → clientes, subtipos y
permisos → transportistas y coberturas → depósito → ingresos y renglones →
transferencias y renglones → comprobantes y renglones → saldos de stock.

Se generan 20.000 clientes, 150.000 comprobantes y 500.000 renglones, por lo que
tres tablas superan 10.000 filas y dos superan 100.000. Todas las tablas del
modelo tienen datos, incluida auditoría de precios. Los catálogos son CSV
seleccionados manualmente del anexo B (localidades: cabeceras de los departamentos).
No se crea una tabla de tipos de vino: el modelo los guarda como atributo CHECK.

La semilla es 2026, Faker tiene versión fijada y la fecha de referencia es
2026-11-07. Las cosechas abarcan 2022–2026. Los vinos comercializados son de la
campaña 2022: cosecha en marzo, precio histórico en junio, ingreso el 2 de junio,
transferencia el 3 y ventas desde el 4. No hay vínculo lote-vino en el esquema;
no se inventa uno. Los lotes posteriores representan cosechas posteriores.
Cada vino tiene una cepa compatible con su tipo al 100 % y un maridaje.
Todos los clientes tienen exactamente un subtipo y el descuento correspondiente.

Los ingresos procesados aportan 200.000 botellas por vino; cada una de las 15 salas
recibe 10.000 por vino. Las ventas consumen ese stock. No se insertan saldos
arbitrarios: se derivan en SQL de los movimientos. La auditoría representa un
cambio histórico de precio antes de todas las ventas, con usuario fijo
`carga_historica`, para conservar la reproducibilidad.

## Tratamiento de triggers

Se bloquean todas las tablas del proyecto durante la transacción para impedir
escrituras concurrentes. Solo se deshabilitan triggers de usuario, nunca los de
integridad referencial. CHECK, UNIQUE, NOT NULL y FK permanecen activos.
Se rechaza una base que ya tenga algún trigger de usuario deshabilitado o con
modo especial. Las reglas históricas se verifican explícitamente y se calculan
totales y stock en SQL, usando las fórmulas de etapa-2. Los documentos históricos
se cargan como procesados sin ejecutar los procedimientos para evitar aplicar
dos veces sus efectos. La fecha histórica de transferencia es una excepción
documentada a la asignación de CURRENT_DATE que hace el trigger en operación normal.

Al finalizar se habilitan nuevamente todos los triggers de usuario. Si falla
una operación, el rollback revierte datos y cambios de habilitación de triggers.
Rehabilitar triggers no valida retroactivamente los eventos omitidos: por eso
se controlan composición, jerarquía, descuentos, totales, fechas, origen de vinos,
encargados, stock negativo y conciliación de ambos stocks con sus movimientos.
Las filas huérfanas se impiden mediante FK activas durante toda la carga.
Esta estrategia requiere propietario y debe usarse exclusivamente para preparar
el dataset histórico en una base vacía, no como ruta de carga de producción.
