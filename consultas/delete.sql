\echo D1
-- D1. Borrar comprobantes de socios con más de cinco años de antigüedad.
BEGIN;
CREATE TEMP TABLE d1_elegidos ON COMMIT DROP AS
SELECT c.numero FROM comprobante c JOIN socio_club s USING (idCliente)
WHERE c.fecha < CURRENT_DATE - INTERVAL '5 years';
CREATE TEMP VIEW d1_control AS
SELECT (SELECT COUNT(*) FROM comprobante c JOIN d1_elegidos e USING (numero)) AS comprobantes,
       (SELECT COUNT(*) FROM renglon_comprobante r JOIN d1_elegidos e
        ON r.numeroComprobante = e.numero) AS renglones,
       (SELECT SUM(cantidadStock) FROM posee) AS botellas_en_salas;
SELECT 'antes' AS fase, * FROM d1_control;
DELETE FROM renglon_comprobante r USING d1_elegidos e WHERE r.numeroComprobante = e.numero;
DELETE FROM comprobante c USING d1_elegidos e WHERE c.numero = e.numero;
SELECT 'después' AS fase, * FROM d1_control;
ROLLBACK;

\echo D2
-- D2. Eliminar cepas ausentes de vinos y parcelas.
BEGIN;
CREATE TEMP VIEW d2_elegidas AS
SELECT * FROM cepa c
WHERE NOT EXISTS (SELECT 1 FROM componen co WHERE co.idCepa = c.idCepa)
  AND NOT EXISTS (SELECT 1 FROM parcela p WHERE p.idCepa = c.idCepa);
SELECT 'antes' AS fase, COUNT(*) AS cepas_sin_uso FROM d2_elegidas;
DELETE FROM d2_elegidas RETURNING idCepa, nombre;
SELECT 'después' AS fase, COUNT(*) AS cepas_sin_uso FROM d2_elegidas;
ROLLBACK;

\echo D3
-- D3. Eliminar empleados con menos de dos años en la sala dada de baja.
BEGIN;
CREATE TEMP TABLE d3_elegidos ON COMMIT DROP AS
SELECT e.cuit
FROM empleado e JOIN sala_venta s USING (idSalaVenta)
JOIN localidad l USING (idLocalidad)
WHERE s.idSalaVenta = 2 AND l.nombre = 'General Alvear' AND l.provincia = 'Mendoza'
  AND e.fechaIngresoLaboral > CURRENT_DATE - INTERVAL '2 years'
  AND e.fechaIngresoLaboral <= CURRENT_DATE;
SELECT 'antes' AS fase, COUNT(*) AS empleados FROM empleado JOIN d3_elegidos USING (cuit);
DELETE FROM empleado e USING d3_elegidos d WHERE d.cuit = e.cuit
RETURNING e.cuit, e.idSalaVenta;
SELECT 'después' AS fase, COUNT(*) AS empleados FROM empleado JOIN d3_elegidos USING (cuit);
ROLLBACK;

\echo D4
-- D4. Borrar socios sin compras dados de alta hace más de cinco años.
BEGIN;
CREATE TEMP TABLE d4_elegidos ON COMMIT DROP AS
SELECT cl.idCliente
FROM cliente cl JOIN socio_club s USING (idCliente)
WHERE cl.fechaAlta < CURRENT_DATE - INTERVAL '5 years'
  AND NOT EXISTS (SELECT 1 FROM comprobante c WHERE c.idCliente = cl.idCliente);
CREATE TEMP VIEW d4_control AS
SELECT (SELECT COUNT(*) FROM cliente JOIN d4_elegidos USING (idCliente)) AS clientes,
       (SELECT COUNT(*) FROM socio_club JOIN d4_elegidos USING (idCliente)) AS socios;
SELECT 'antes' AS fase, * FROM d4_control;
DELETE FROM socio_club s USING d4_elegidos d WHERE d.idCliente = s.idCliente;
DELETE FROM cliente cl USING d4_elegidos d WHERE d.idCliente = cl.idCliente;
SET CONSTRAINTS ALL IMMEDIATE;
SELECT 'después' AS fase, * FROM d4_control;
ROLLBACK;

\echo D5
-- D5. Borrar ingresos procesados con más de 365 días.
BEGIN;
CREATE TEMP TABLE d5_elegidos ON COMMIT DROP AS
SELECT codigoIngreso FROM ingresos WHERE estado = 'procesado' AND fecha < CURRENT_DATE - 365;
CREATE TEMP VIEW d5_control AS
SELECT (SELECT COUNT(*) FROM ingresos JOIN d5_elegidos USING (codigoIngreso)) AS ingresos,
       (SELECT COUNT(*) FROM contiene JOIN d5_elegidos USING (codigoIngreso)) AS renglones,
       (SELECT SUM(cantidadStock) FROM almacena) AS botellas_en_deposito;
SELECT 'antes' AS fase, * FROM d5_control;
DO $$
DECLARE
    v_renglones bigint;
    v_ingresos bigint;
BEGIN
    DELETE FROM contiene r USING d5_elegidos d WHERE d.codigoIngreso = r.codigoIngreso;
    GET DIAGNOSTICS v_renglones = ROW_COUNT;
    DELETE FROM ingresos i USING d5_elegidos d WHERE d.codigoIngreso = i.codigoIngreso;
    GET DIAGNOSTICS v_ingresos = ROW_COUNT;
    RAISE NOTICE 'D5: % ingresos y % renglones borrados', v_ingresos, v_renglones;
EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'No se pueden modificar renglones de un ingreso no confeccionado' THEN
        RAISE;
    END IF;
    RAISE NOTICE 'D5: RN-12 bloqueó el borrado. Ingresos y renglones borrados: 0';
END
$$;
SELECT 'después' AS fase, * FROM d5_control;
ROLLBACK;

\echo D6
-- D6. Borrar socios sin compras de una localidad específica.
BEGIN;
CREATE TEMP TABLE d6_elegidos ON COMMIT DROP AS
SELECT cl.idCliente
FROM cliente cl JOIN socio_club s USING (idCliente)
JOIN localidad l USING (idLocalidad)
WHERE l.nombre = 'San Rafael' AND l.provincia = 'Mendoza'
  AND NOT EXISTS (SELECT 1 FROM comprobante c WHERE c.idCliente = cl.idCliente);
CREATE TEMP VIEW d6_control AS
SELECT (SELECT COUNT(*) FROM cliente JOIN d6_elegidos USING (idCliente)) AS clientes,
       (SELECT COUNT(*) FROM socio_club JOIN d6_elegidos USING (idCliente)) AS socios;
SELECT 'antes' AS fase, * FROM d6_control;
DELETE FROM socio_club s USING d6_elegidos d WHERE d.idCliente = s.idCliente;
DELETE FROM cliente cl USING d6_elegidos d WHERE d.idCliente = cl.idCliente;
SET CONSTRAINTS ALL IMMEDIATE;
SELECT 'después' AS fase, * FROM d6_control;
ROLLBACK;
