\echo U1
-- U1. Recalcular el total de todos los comprobantes con el descuento por cliente.
BEGIN;
CREATE TEMP TABLE u1_tasas ON COMMIT DROP AS
SELECT idCliente, fn_descuento_cliente(idCliente) AS tasa FROM cliente;
CREATE TEMP VIEW u1_renglones AS
SELECT r.numeroComprobante, r.codigoVino, t.tasa,
       ROUND(r.cantidad * r.precioUnitario * (1 - t.tasa / 100.0), 2) AS neto,
       r.descuento, r.subtotalRenglon
FROM renglon_comprobante r
JOIN comprobante c ON c.numero = r.numeroComprobante
JOIN u1_tasas t ON t.idCliente = c.idCliente;
CREATE TEMP VIEW u1_totales AS
SELECT c.numero, COALESCE(a.bruto, 0) AS bruto,
       COALESCE(a.rebaja, 0) AS rebaja, COALESCE(a.neto, 0) AS neto
FROM comprobante c
LEFT JOIN (
    SELECT numeroComprobante, SUM(cantidad * precioUnitario) AS bruto,
           SUM(ROUND(cantidad * precioUnitario * descuento / 100.0, 2)) AS rebaja,
           SUM(subtotalRenglon) AS neto
    FROM renglon_comprobante
    GROUP BY numeroComprobante
) a ON a.numeroComprobante = c.numero;
CREATE TEMP VIEW u1_control AS
SELECT COUNT(*) AS comprobantes, SUM(c.total) AS monto_total,
       COUNT(*) FILTER (
           WHERE (c.subtotal, c.descuento, c.total) IS DISTINCT FROM (t.bruto, t.rebaja, t.neto)
       ) AS encabezados_inconsistentes,
       (SELECT COUNT(*) FROM u1_renglones
        WHERE (descuento, subtotalRenglon) IS DISTINCT FROM (tasa, neto)) AS renglones_inconsistentes
FROM comprobante c JOIN u1_totales t USING (numero);
SELECT 'antes' AS fase, * FROM u1_control;
UPDATE renglon_comprobante r
SET descuento = e.tasa, subtotalRenglon = e.neto
FROM u1_renglones e
WHERE (r.numeroComprobante, r.codigoVino) = (e.numeroComprobante, e.codigoVino)
  AND (r.descuento, r.subtotalRenglon) IS DISTINCT FROM (e.tasa, e.neto);
UPDATE comprobante c
SET subtotal = t.bruto, descuento = t.rebaja, total = t.neto
FROM u1_totales t
WHERE c.numero = t.numero;
SELECT 'después' AS fase, * FROM u1_control;
ROLLBACK;

\echo U2
-- U2. Aumentar 20 % el salario de empleados con más de cinco años.
BEGIN;
CREATE TEMP VIEW u2_elegibles AS
SELECT * FROM empleado WHERE fechaIngresoLaboral < CURRENT_DATE - INTERVAL '5 years';
SELECT 'antes' AS fase, COUNT(*) AS empleados, SUM(salario) AS salarios FROM u2_elegibles;
UPDATE u2_elegibles SET salario = ROUND(salario * 1.20, 2);
SELECT 'después' AS fase, COUNT(*) AS empleados, SUM(salario) AS salarios FROM u2_elegibles;
ROLLBACK;

\echo U3
-- U3. Incrementar 13 % el precio de los vinos de una bodega.
BEGIN;
CREATE TEMP VIEW u3_vinos AS
SELECT * FROM vino WHERE cuitBodega = '30000000000';
CREATE TEMP VIEW u3_control AS
SELECT COUNT(*) AS vinos, SUM(v.precio) AS precios,
       (SELECT COUNT(*) FROM auditoria_precio a JOIN u3_vinos USING (codigoVino)) AS auditorias
FROM u3_vinos v;
SELECT 'antes' AS fase, * FROM u3_control;
UPDATE u3_vinos SET precio = ROUND(precio * 1.13, 2);
SELECT 'después' AS fase, * FROM u3_control;
ROLLBACK;

\echo U4
-- U4. Cambiar lunes por miércoles y viceversa en una sentencia.
BEGIN;
SELECT 'antes' AS fase, idSalaVenta, diaCierreSemanal FROM sala_venta ORDER BY idSalaVenta;
UPDATE sala_venta
SET diaCierreSemanal = CASE diaCierreSemanal WHEN 'lunes' THEN 'miercoles' ELSE 'lunes' END
WHERE diaCierreSemanal IN ('lunes', 'miercoles');
SELECT 'después' AS fase, idSalaVenta, diaCierreSemanal FROM sala_venta ORDER BY idSalaVenta;
ROLLBACK;

\echo U5
-- U5. Reducir 15 % el precio de los diez vinos menos vendidos en toda la red.
BEGIN;
CREATE TEMP TABLE u5_elegidos ON COMMIT DROP AS
SELECT v.codigoVino, COALESCE(SUM(r.cantidad), 0) AS botellas
FROM vino v LEFT JOIN renglon_comprobante r USING (codigoVino)
GROUP BY v.codigoVino
ORDER BY botellas, v.codigoVino
LIMIT 10;
CREATE TEMP VIEW u5_control AS
SELECT e.codigoVino, e.botellas, v.precio,
       (SELECT COUNT(*) FROM auditoria_precio a WHERE a.codigoVino = e.codigoVino) AS auditorias
FROM u5_elegidos e JOIN vino v USING (codigoVino);
SELECT 'antes' AS fase, * FROM u5_control ORDER BY botellas, codigoVino;
UPDATE vino v SET precio = ROUND(v.precio * 0.85, 2)
FROM u5_elegidos e WHERE e.codigoVino = v.codigoVino;
SELECT 'después' AS fase, * FROM u5_control ORDER BY botellas, codigoVino;
ROLLBACK;

\echo U6
-- U6. Subir al 35 % el descuento de exportadores con más de tres permisos.
BEGIN;
CREATE TEMP VIEW u6_elegibles AS
SELECT e.idCliente
FROM exportador e JOIN permisos p ON p.idExportador = e.idCliente
GROUP BY e.idCliente
HAVING COUNT(*) > 3;
CREATE TEMP VIEW u6_control AS
SELECT COUNT(*) AS candidatos, MIN(c.descuento) AS minimo, MAX(c.descuento) AS maximo
FROM cliente c JOIN u6_elegibles e USING (idCliente);
SELECT 'antes' AS fase, * FROM u6_control;
DO $$
DECLARE
    v_restriccion text;
    v_filas bigint;
BEGIN
    UPDATE cliente c SET descuento = 35
    FROM u6_elegibles e WHERE e.idCliente = c.idCliente;
    GET DIAGNOSTICS v_filas = ROW_COUNT;
    RAISE NOTICE 'U6: % filas actualizadas', v_filas;
EXCEPTION WHEN check_violation THEN
    GET STACKED DIAGNOSTICS v_restriccion = CONSTRAINT_NAME;
    IF v_restriccion IS DISTINCT FROM 'ck_cliente_descuento' THEN
        RAISE;
    END IF;
    RAISE NOTICE 'U6: % rechazó el 35 %%. Filas actualizadas: 0', v_restriccion;
END
$$;
SELECT 'después' AS fase, * FROM u6_control;
ROLLBACK;
