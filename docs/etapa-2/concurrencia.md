# Venta de la última botella

Usamos dos sesiones de PostgreSQL con aislamiento `READ COMMITTED` y un solo saldo disponible. La prueba requiere una base desechable con las migraciones 001 a 011 aplicadas.

## Preparación

Cargar [api/tests/datos.sql](../../api/tests/datos.sql) en la base de prueba. Como administrador, dejar una botella del vino 1 en la sala 1 y crear un socio:

```sql
UPDATE posee SET cantidadStock = 1 WHERE idSalaVenta = 1 AND codigoVino = 1;

BEGIN;
INSERT INTO cliente (idLocalidad, nombre, apellido, tipoDocumento, numeroDocumento, direccion, descuento)
VALUES (1, 'Ana', 'Prueba', 'DNI', '33000000', 'Mitre 100', 10);
INSERT INTO socio_club VALUES (1);
COMMIT;
```

## Lectura sin bloqueo

Ejecutar en ambas sesiones antes de vender:

```sql
SELECT cantidadStock FROM posee WHERE idSalaVenta = 1 AND codigoVino = 1;
```

A y B ven una botella. La consulta lee el último saldo confirmado y no lo reserva. Si la validación terminara en esa lectura, los dos compradores podrían recibir una confirmación basada en el mismo saldo.

## Venta con bloqueo

Ejecutar en la sesión A y dejar la transacción abierta:

```sql
BEGIN ISOLATION LEVEL READ COMMITTED;
INSERT INTO comprobante (numero, idCliente, idSalaVenta) VALUES (101, 1, 1);
INSERT INTO renglon_comprobante VALUES (101, 1, 1, 100, 10, 0);
```

Ejecutar en la sesión B:

```sql
BEGIN ISOLATION LEVEL READ COMMITTED;
INSERT INTO comprobante (numero, idCliente, idSalaVenta) VALUES (102, 1, 1);
INSERT INTO renglon_comprobante VALUES (102, 1, 1, 100, 10, 0);
```

El `FOR UPDATE` del trigger hace que el segundo renglón espere. Ejecutar `COMMIT` en A. La sesión B vuelve a leer el saldo actualizado, rechaza la venta por stock insuficiente y debe terminar con `ROLLBACK`. El comprobante 102 se revierte junto con su transacción. Comprobar el resultado:

```sql
SELECT cantidadStock FROM posee WHERE idSalaVenta = 1 AND codigoVino = 1;
SELECT numero FROM comprobante WHERE numero IN (101, 102) ORDER BY numero;
```

Queda stock cero y solo existe la venta 101.

## Resultado registrado

En la prueba local con dos conexiones `psql` y el rol `bodega_api`, PostgreSQL mostró la espera de B en `pg_stat_activity`. El resumen de la salida fue:

```text
A sin bloqueo: 1
B sin bloqueo: 1
B esperando: Lock/transactionid
ERROR: Stock insuficiente del vino 1 en la sala 1 (solicitado: 1, disponible incluyendo restitución: 0)
stock=0
ventas=101
```
