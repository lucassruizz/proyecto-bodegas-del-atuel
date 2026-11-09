-- Bodegas del Atuel · Etapa 5 · Pruebas de inserción con ROLLBACK.

\echo I1
-- I1. Dar cobertura a General Alvear con el transportista de menos envíos
-- del último trimestre. LEFT JOIN incluye empresas con cero ingresos procesados.
-- La PK permite repetir el intento si el par ya existe.
BEGIN;
CREATE TEMP TABLE i1_elegido ON COMMIT DROP AS
SELECT t.codigoTransporte, l.idLocalidad, t.envios
FROM localidad l
CROSS JOIN (
    SELECT e.codigoTransporte, COUNT(i.codigoIngreso) AS envios
    FROM empresas_transporte e
    LEFT JOIN ingresos i ON i.codigoTransporte = e.codigoTransporte
      AND i.estado = 'procesado'
      AND i.fecha >= CURRENT_DATE - INTERVAL '3 months' AND i.fecha <= CURRENT_DATE
    GROUP BY e.codigoTransporte
    ORDER BY envios, e.codigoTransporte
    LIMIT 1
) t
WHERE l.nombre = 'General Alvear' AND l.provincia = 'Mendoza';
CREATE TEMP VIEW i1_control AS
SELECT e.*, a.codigoTransporte IS NOT NULL AS cobertura
FROM i1_elegido e LEFT JOIN alcanza a USING (codigoTransporte, idLocalidad);
SELECT 'antes' AS fase, * FROM i1_control;
INSERT INTO alcanza (codigoTransporte, idLocalidad)
SELECT codigoTransporte, idLocalidad FROM i1_elegido
ON CONFLICT (codigoTransporte, idLocalidad) DO NOTHING;
SELECT 'después' AS fase, * FROM i1_control;
ROLLBACK;

\echo I2
-- I2. Crear «cordero al disco» si hay tintos de 14° o más y asociarlos.
-- Reutilizar el maridaje si existe. El esquema no tiene UNIQUE por nombre:
-- bloquear escrituras concurrentes sobre el catálogo al buscar o crear el nombre.
BEGIN;
LOCK TABLE maridaje IN SHARE ROW EXCLUSIVE MODE;
CREATE TEMP VIEW i2_vinos AS
SELECT codigoVino FROM vino WHERE tipo = 'tinto' AND graduacionAlcoholica >= 14;
CREATE TEMP VIEW i2_control AS
SELECT (SELECT COUNT(*) FROM i2_vinos) AS vinos_elegibles,
       COUNT(DISTINCT m.idMaridaje) AS maridajes,
       COUNT(v.codigoVino) AS asociaciones
FROM maridaje m LEFT JOIN tienen t USING (idMaridaje)
LEFT JOIN i2_vinos v ON v.codigoVino = t.codigoVino
WHERE lower(btrim(m.nombre)) = 'cordero al disco';
SELECT 'antes' AS fase, * FROM i2_control;
INSERT INTO maridaje (nombre, temperatura)
SELECT 'cordero al disco', 16
WHERE EXISTS (SELECT 1 FROM i2_vinos)
  AND NOT EXISTS (SELECT 1 FROM maridaje WHERE lower(btrim(nombre)) = 'cordero al disco');
INSERT INTO tienen (codigoVino, idMaridaje)
SELECT v.codigoVino, m.idMaridaje
FROM i2_vinos v
CROSS JOIN (
    SELECT MIN(idMaridaje) AS idMaridaje FROM maridaje WHERE lower(btrim(nombre)) = 'cordero al disco'
) m
WHERE m.idMaridaje IS NOT NULL
ON CONFLICT (codigoVino, idMaridaje) DO NOTHING;
SELECT 'después' AS fase, * FROM i2_control;
ROLLBACK;

\echo I3
-- I3. Crear un comprobante en la sala 1, con tres renglones, para el cliente 1.
-- Cambiar el número de prueba, cliente, sala, vinos y cantidades. La función
-- de descuento y los triggers calculan los importes y actualizan el stock.
BEGIN;
SELECT 'antes' AS fase, COUNT(*) AS comprobantes FROM comprobante WHERE numero = 900001;
SELECT 'antes' AS fase, codigoVino, fn_stock_sala(1, codigoVino) AS stock
FROM vino WHERE codigoVino IN (1, 2, 3) ORDER BY codigoVino;
INSERT INTO comprobante (numero, idCliente, idSalaVenta, subtotal, descuento, total)
VALUES (900001, 1, 1, 0, 0, 0);
INSERT INTO renglon_comprobante (
    numeroComprobante, codigoVino, cantidad, precioUnitario, descuento, subtotalRenglon
)
SELECT 900001, v.codigoVino, p.cantidad, v.precio, fn_descuento_cliente(c.idCliente), 0
FROM (VALUES (1, 2), (2, 1), (3, 3)) p(codigoVino, cantidad)
JOIN vino v USING (codigoVino)
JOIN comprobante c ON c.numero = 900001
ORDER BY v.codigoVino;
SELECT 'después' AS fase, numero, subtotal, descuento, total,
       fn_total_comprobante(numero) AS total_calculado,
       (SELECT COUNT(*) FROM renglon_comprobante WHERE numeroComprobante = c.numero) AS renglones
FROM comprobante c WHERE numero = 900001;
SELECT 'después' AS fase, codigoVino, fn_stock_sala(1, codigoVino) AS stock
FROM vino WHERE codigoVino IN (1, 2, 3) ORDER BY codigoVino;
ROLLBACK;

\echo I4
-- I4. Insertar una nueva bodega. Cambiar CUIT y demás datos del VALUES.
-- La PK rechaza un CUIT duplicado y el dominio valida el formato.
BEGIN;
SELECT 'antes' AS fase, COUNT(*) AS bodegas FROM bodega WHERE cuit = '30999999999';
INSERT INTO bodega (cuit, razonSocial, domicilio)
VALUES ('30999999999', 'Bodega de prueba etapa 5', 'Ruta 143, San Rafael');
SELECT 'después' AS fase, cuit, razonSocial, domicilio FROM bodega WHERE cuit = '30999999999';
ROLLBACK;

\echo I5
-- I5. Insertar una nueva sala de venta en General Alvear.
-- Buscar la localidad del catálogo. RETURNING entrega el ID generado.
BEGIN;
CREATE TEMP VIEW i5_control AS
SELECT COUNT(*) AS salas
FROM sala_venta s JOIN localidad l USING (idLocalidad)
WHERE l.nombre = 'General Alvear' AND l.provincia = 'Mendoza'
  AND s.calle = 'Calle de prueba etapa 5' AND s.numero = '500';
SELECT 'antes' AS fase, * FROM i5_control;
INSERT INTO sala_venta (calle, numero, diaCierreSemanal, idLocalidad)
SELECT 'Calle de prueba etapa 5', '500', 'lunes', idLocalidad
FROM localidad WHERE nombre = 'General Alvear' AND provincia = 'Mendoza'
RETURNING idSalaVenta, idLocalidad;
SELECT 'después' AS fase, * FROM i5_control;
ROLLBACK;

\echo I6
-- I6. Crear un ingreso en confección de 120 botellas de un vino dado.
-- Cambiar los códigos 900001 (ingreso), 1 (vino y transporte) y el CUIT
-- de la bodega. El JOIN comprueba que la bodega elegida elabora ese vino.
BEGIN;
CREATE TEMP VIEW i6_control AS
SELECT COUNT(DISTINCT i.codigoIngreso) AS ingresos,
       COUNT(r.codigoVino) AS renglones, COALESCE(SUM(r.cantidadBotellas), 0) AS botellas
FROM ingresos i LEFT JOIN contiene r USING (codigoIngreso)
WHERE i.codigoIngreso = 900001;
SELECT 'antes' AS fase, * FROM i6_control;
INSERT INTO ingresos (codigoIngreso, estado, cuitBodega, codigoTransporte, idDeposito)
VALUES (
    900001, 'en_confeccion',
    (SELECT cuitBodega FROM vino WHERE codigoVino = 1 AND cuitBodega = '30000000000'),
    1, 1
);
INSERT INTO contiene (codigoIngreso, codigoVino, cantidadBotellas)
SELECT i.codigoIngreso, v.codigoVino, 120
FROM ingresos i JOIN vino v ON v.cuitBodega = i.cuitBodega
WHERE i.codigoIngreso = 900001 AND v.codigoVino = 1;
SELECT 'después' AS fase, * FROM i6_control;
SELECT estado, cuitBodega, codigoTransporte FROM ingresos WHERE codigoIngreso = 900001;
ROLLBACK;
