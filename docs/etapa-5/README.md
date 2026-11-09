# Bodegas del Atuel · Etapa 5

Las 30 consignas de la sección 8 están en cuatro archivos. S11 y S12 tienen
dos consultas cada una. Se usó PostgreSQL 16.15 con la carga histórica de
etapa 3, los cinco índices de etapa 4 y las reglas de integridad activas.
En la sesión de prueba, `CURRENT_DATE` fue el 9 de noviembre de 2026.

## Ejecución

Desde la raíz del repositorio, apuntar `psql` a una base de prueba ya cargada
y con las migraciones 001–006 y 008 aplicadas. Usar el propietario para poder
ejecutar el bloqueo de catálogo de I2 y las operaciones de auditoría. En el
ejemplo, la base se llama `bodegas`. Configurar conexión y autenticación según
el entorno. El [informe de etapa 4](../etapa-4/README.md) describe cómo preparar
y cargar la base.

```sh
psql -X -v ON_ERROR_STOP=1 -d bodegas -f consultas/update.sql
psql -X -v ON_ERROR_STOP=1 -d bodegas -f consultas/insert.sql
psql -X -v ON_ERROR_STOP=1 -d bodegas -f consultas/delete.sql
psql -X -v ON_ERROR_STOP=1 -d bodegas -f consultas/select.sql
psql -X -v ON_ERROR_STOP=1 -d bodegas -v 'plan=EXPLAIN (ANALYZE, BUFFERS)' -f consultas/select.sql
```

Los parámetros de negocio están indicados junto a cada consulta. Los períodos
relativos usan `CURRENT_DATE` y excluyen fechas futuras. Las pruebas de
escritura muestran el estado antes y después de cada consigna y terminan con
`ROLLBACK`. Las secuencias de PostgreSQL pueden avanzar al generar IDs durante
una prueba, aun cuando se reviertan las filas.

## Modificaciones e inserciones

| Código | Filas afectadas durante la prueba | Resultado en la carga original |
|---|---:|---|
| U1 | 150.000 comprobantes, 0 renglones | Se recalcularon todos los encabezados. El monto total se mantuvo en 5.196.342.157,00 porque los renglones y encabezados ya coincidían. |
| U2 | 90 empleados | Suma de salarios de 85.005.000,00 a 102.006.000,00. |
| U3 | 30 vinos y 30 entradas de auditoría | Suma de precios de 193.800,00 a 218.994,00 para Bodega Atuel 0. |
| U4 | 10 salas | Cinco pasaron de lunes a miércoles y cinco hicieron el cambio inverso. |
| U5 | 10 vinos y 10 entradas de auditoría | Los precios quedaron al 85 % de su valor original. |
| U6 | 0 de 1.666 candidatos | El CHECK rechazó el 35 %. Todos conservaron el 30 %. |
| I1 | 0 coberturas nuevas | Ganó el transportista 1 por desempate. Ya tenía cobertura de General Alvear. |
| I2 | 1 maridaje y 75 asociaciones | Se creó «cordero al disco» para los 75 tintos elegibles. |
| I3 | 1 comprobante y 3 renglones | Total de 27.117,00. El stock bajó 2, 1 y 3 botellas respectivamente. |
| I4 | 1 bodega | Se insertó el CUIT de prueba 30999999999. |
| I5 | 1 sala | Se insertó en General Alvear y se obtuvo un ID de la secuencia. |
| I6 | 1 ingreso y 1 renglón | Quedó en confección con 120 botellas de Vino Atuel 1. El procedimiento de procesamiento se deja para el flujo posterior. |

## Borrados

| Código | Carga original | Copia con datos de prueba |
|---|---|---|
| D1 | 0. Ningún comprobante de socio tenía más de cinco años. | 1 comprobante y 4 renglones borrados. El trigger restituyó 8 botellas al stock de sala. |
| D2 | 0. Todas las cepas estaban referenciadas. | 1 cepa sin referencias borrada. |
| D3 | 0. La sala 2 carecía de empleados con menos de dos años. | 1 empleado borrado. |
| D4 | 0. Los socios tenían compras. | 1 socio y su fila de cliente borrados. |
| D5 | 0 de 600 ingresos candidatos. RN-12 bloqueó el borrado de sus renglones. | Se reprodujo el mismo bloqueo. |
| D6 | 0. Los socios de San Rafael tenían compras. | 1 socio y su fila de cliente borrados. |

El esquema vigente tiene FK `RESTRICT`, por lo que D1, D4 y D6 borran las
filas dependientes primero. D1 conserva el encabezado mientras los triggers
restituyen stock. D4 y D6 adelantan la validación de los triggers diferidos
después de borrar tanto el subtipo como el cliente.

### Conflictos con reglas de negocio

**U6.** RN-06 fija el descuento de exportadores en 30 %. El primer rechazo
lo produjo `ck_cliente_descuento`. La validación diferida y
`fn_descuento_cliente` también esperan 30 %. Para admitir 35 % habría que
acordar la excepción y cambiar coherentemente los tres mecanismos, incluida la
política para ventas futuras.

**D5.** Los 600 ingresos antiguos procesados tienen 6.000 renglones. La FK
impide borrar primero el encabezado y RN-12 impide borrar primero el detalle.
Una política de eliminación o archivo de ingresos procesados requiere definir
qué historial se conserva para conciliar el stock. El script registra el
rechazo y verifica que los ingresos, renglones y stock siguen presentes.

## Consultas de lectura y planes

S9 usa la vista de stock y agrega cepas y maridajes por separado. S10 compara
el rendimiento de cada parcela con el promedio de su finca en la misma
campaña. S11 usa ventanas para el ranking por sala y el acumulado por mes con
ventas. S12 usa `NOT EXISTS` para comprobar que no falte ningún vino de la
bodega y excluir a quienes compraron tintos.

Se ejecutaron todas las consultas de lectura. Los resultados vacíos de S4
y S7 se explican por las fechas históricas de las transferencias y los
ingresos. S6 tampoco tuvo coincidencias porque la sala 1 conservaba stock.
S12a no encontró un cliente que hubiera comprado los 30 vinos de la bodega
elegida, y S12b encontró 22 clientes que nunca compraron tintos.

Se guardaron diez planes completos con `EXPLAIN (ANALYZE, BUFFERS)` para
S1, S3, S5, S8, S9, S10 y las dos partes de S11 y S12. Los tiempos corresponden
a una ejecución con los índices instalados. S3 y S8 usan la fecha actual en
esta etapa, de modo que su período puede diferir del ensayo de etapa 4.

## Evidencia y reproducción adicional

- Carga original · [UPDATE](evidencia/update.txt), [INSERT](evidencia/insert.txt) y [DELETE](evidencia/delete.txt)
- Copia de prueba · [UPDATE](evidencia/update_con_datos_prueba.txt), [INSERT](evidencia/insert_con_datos_prueba.txt) y [DELETE](evidencia/delete_con_datos_prueba.txt)
- Lecturas · [Filas y tiempos](evidencia/select_resumen.txt) y [planes completos](evidencia/planes.txt)
- Reversión · [Huella de los datos antes y después](evidencia/rollback.txt)

Para reproducir los casos adicionales, crear una copia desechable de la base
cargada, ejecutar el script de datos de prueba y repetir las tres pruebas de
escritura sobre esa copia. La carga auxiliar altera intencionalmente un
comprobante para verificar U1, retira una cobertura para verificar I1 y
prepara candidatos para D1, D2, D3, D4 y D6.

```sh
createdb -T bodegas bodegas_etapa5_pruebas
psql -X -v ON_ERROR_STOP=1 -d bodegas_etapa5_pruebas -f docs/etapa-5/datos_prueba.sql
psql -X -v ON_ERROR_STOP=1 -d bodegas_etapa5_pruebas -f consultas/update.sql
psql -X -v ON_ERROR_STOP=1 -d bodegas_etapa5_pruebas -f consultas/insert.sql
psql -X -v ON_ERROR_STOP=1 -d bodegas_etapa5_pruebas -f consultas/delete.sql
```
