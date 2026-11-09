-- Bodegas del Atuel · Etapa 5 · Consultas de lectura.
-- Ejecutar con psql. Con -v 'plan=EXPLAIN (ANALYZE, BUFFERS)' se miden
-- las consultas reutilizadas de etapa 4 y las avanzadas S9–S12.
\if :{?plan}
\else
\set plan ''
\endif

\echo S1
-- S1. Ranking de los 10 vinos con más botellas vendidas en toda la red.
-- Agrupar los renglones por vino antes de unir al catálogo.
:plan
WITH ventas AS (
    SELECT codigoVino, SUM(cantidad) AS botellas
    FROM renglon_comprobante
    GROUP BY codigoVino
)
SELECT v.codigoVino, v.nombre, ventas.botellas
FROM ventas JOIN vino v USING (codigoVino)
ORDER BY ventas.botellas DESC, v.codigoVino
LIMIT 10;

\echo S2
-- S2. Códigos y nombres de los vinos vendidos en todas las salas.
-- División por conteo: comparar salas distintas con el tamaño de la red.
WITH salas_por_vino AS (
    SELECT r.codigoVino, COUNT(DISTINCT c.idSalaVenta) AS salas
    FROM renglon_comprobante r
    JOIN comprobante c ON c.numero = r.numeroComprobante
    GROUP BY r.codigoVino
)
SELECT v.codigoVino, v.nombre
FROM vino v
LEFT JOIN salas_por_vino s USING (codigoVino)
WHERE COALESCE(s.salas, 0) = (SELECT COUNT(*) FROM sala_venta)
ORDER BY v.codigoVino;

\echo S3
-- S3. Clientes de cada tipo que compraron en una sala en la última semana.
-- Cambiar idSalaVenta = 1 para otra sala. Contar compradores distintos.
:plan
WITH compradores AS (
    SELECT DISTINCT idCliente
    FROM comprobante
    WHERE idSalaVenta = 1
      AND fecha BETWEEN CURRENT_DATE - 6 AND CURRENT_DATE
)
SELECT COUNT(s.idCliente) AS socios,
       COUNT(d.idCliente) AS distribuidores,
       COUNT(e.idCliente) AS exportadores
FROM compradores c
LEFT JOIN socio_club s USING (idCliente)
LEFT JOIN distribuidor d USING (idCliente)
LEFT JOIN exportador e USING (idCliente);

\echo S4
-- S4. Cinco salas que más botellas solicitaron de un vino en 15 días.
-- Cambiar codigoVino = 1 (Vino Atuel 1). Agrupar solicitudes por sala.
SELECT t.idSalaVenta, SUM(i.cantidad) AS botellas_solicitadas
FROM transferencia t
JOIN incluye i USING (numeroSolicitud)
WHERE i.codigoVino = 1
  AND t.fechaConfeccion BETWEEN CURRENT_DATE - 14 AND CURRENT_DATE
GROUP BY t.idSalaVenta
ORDER BY botellas_solicitadas DESC, t.idSalaVenta
LIMIT 5;

\echo S5
-- S5. Salas con menor número de transferencias pendientes.
-- Conservar salas sin solicitudes, contar cero y mostrar todos los empates.
:plan
WITH pendientes AS (
    SELECT idSalaVenta, COUNT(*) AS cantidad
    FROM transferencia
    WHERE estado <> 'procesado'
    GROUP BY idSalaVenta
), por_sala AS (
    SELECT s.idSalaVenta, COALESCE(p.cantidad, 0) AS cantidad
    FROM sala_venta s LEFT JOIN pendientes p USING (idSalaVenta)
)
SELECT idSalaVenta, cantidad
FROM por_sala
WHERE cantidad = (SELECT MIN(cantidad) FROM por_sala)
ORDER BY idSalaVenta;

\echo S6
-- S6. Vinos sin stock en una sala y con stock en el depósito central.
-- Cambiar s.idSalaVenta = 1. Una fila de stock ausente equivale a cero.
SELECT v.codigoVino, v.nombre, a.cantidadStock AS stock_deposito
FROM almacena a
JOIN vino v USING (codigoVino)
JOIN sala_venta s ON s.idSalaVenta = 1
LEFT JOIN posee p ON p.codigoVino = v.codigoVino AND p.idSalaVenta = s.idSalaVenta
WHERE a.idDeposito = 1 AND a.cantidadStock > 0 AND COALESCE(p.cantidadStock, 0) = 0
ORDER BY v.codigoVino;

\echo S7
-- S7. Empresa de transporte con mayor actividad en el último mes.
-- Contar ingresos procesados. Si hay empate en el máximo, devolver todos.
WITH actividad AS (
    SELECT e.codigoTransporte, e.razonSocial, COUNT(*) AS envios
    FROM ingresos i
    JOIN empresas_transporte e USING (codigoTransporte)
    WHERE i.estado = 'procesado'
      AND i.fecha >= CURRENT_DATE - INTERVAL '1 month'
      AND i.fecha <= CURRENT_DATE
    GROUP BY e.codigoTransporte, e.razonSocial
)
SELECT codigoTransporte, razonSocial, envios
FROM actividad
WHERE envios = (SELECT MAX(envios) FROM actividad)
ORDER BY codigoTransporte;

\echo S8
-- S8. Monto total de ventas por sala en el último trimestre, de mayor a menor.
-- Acotar un trimestre móvil y agrupar los comprobantes por sala.
:plan
SELECT idSalaVenta, SUM(total) AS ventas
FROM comprobante
WHERE fecha >= CURRENT_DATE - INTERVAL '3 months'
  AND fecha <= CURRENT_DATE
GROUP BY idSalaVenta
ORDER BY ventas DESC, idSalaVenta;

\echo S9
-- S9. Ficha de un vino con cepas, bodega, maridajes y stock total.
-- Cambiar v.codigoVino = 1. Agregar cepas y maridajes por separado evita
-- el producto entre ambos conjuntos. Usar la vista para el stock.
:plan
SELECT v.codigoVino, v.nombre, b.razonSocial AS bodega,
       COALESCE(c.cepas, '[]'::jsonb) AS cepas,
       COALESCE(m.maridajes, '[]'::jsonb) AS maridajes,
       st.stock_deposito, st.stock_salas, st.stock_total
FROM vino v
JOIN bodega b ON b.cuit = v.cuitBodega
JOIN vw_stock_total_vino st USING (codigoVino)
LEFT JOIN LATERAL (
    SELECT jsonb_agg(jsonb_build_object('cepa', ce.nombre, 'porcentaje', co.porcentaje)
                     ORDER BY ce.nombre, ce.idCepa) AS cepas
    FROM componen co JOIN cepa ce USING (idCepa)
    WHERE co.codigoVino = v.codigoVino
) c ON TRUE
LEFT JOIN LATERAL (
    SELECT jsonb_agg(ma.nombre ORDER BY ma.nombre, ma.idMaridaje) AS maridajes
    FROM tienen t JOIN maridaje ma USING (idMaridaje)
    WHERE t.codigoVino = v.codigoVino
) m ON TRUE
WHERE v.codigoVino = 1;

\echo S10
-- S10. Rendimiento por parcela y campaña y comparación con su finca.
-- CTE de kg/ha y subconsulta correlacionada de promedio por finca y campaña.
:plan
WITH rendimiento AS (
    SELECT p.idFinca, p.numeroParcela, l.campania,
           l.kilosCosechados / p.superficie AS kg_por_hectarea
    FROM parcela p JOIN lote l USING (idFinca, numeroParcela)
)
SELECT r.idFinca, r.numeroParcela, r.campania,
       ROUND(r.kg_por_hectarea, 2) AS kg_por_hectarea,
       ROUND(f.promedio, 2) AS promedio_finca,
       r.kg_por_hectarea < f.promedio AS bajo_promedio
FROM rendimiento r
CROSS JOIN LATERAL (
    SELECT AVG(otra.kg_por_hectarea) AS promedio
    FROM rendimiento otra
    WHERE otra.idFinca = r.idFinca AND otra.campania = r.campania
) f
ORDER BY r.idFinca, r.campania, r.numeroParcela;

\echo S11a
-- S11a. Ranking de vinos por botellas vendidas dentro de cada sala.
-- Agrupar primero por sala y vino. RANK conserva empates en cantidad.
:plan
WITH ventas AS (
    SELECT c.idSalaVenta, r.codigoVino, SUM(r.cantidad) AS botellas
    FROM comprobante c
    JOIN renglon_comprobante r ON r.numeroComprobante = c.numero
    GROUP BY c.idSalaVenta, r.codigoVino
)
SELECT ve.idSalaVenta, ve.codigoVino, v.nombre, ve.botellas,
       RANK() OVER (PARTITION BY ve.idSalaVenta ORDER BY ve.botellas DESC) AS puesto
FROM ventas ve JOIN vino v USING (codigoVino)
ORDER BY ve.idSalaVenta, puesto, ve.codigoVino;

\echo S11b
-- S11b. Ventas acumuladas mensuales por sala en orden cronológico.
-- La vista da un monto por mes con ventas. La ventana suma desde el primer mes.
:plan
SELECT idSalaVenta, mes, total_vendido,
       SUM(total_vendido) OVER (
           PARTITION BY idSalaVenta ORDER BY mes
           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
       ) AS ventas_acumuladas
FROM vw_ventas_mensuales_sala
ORDER BY idSalaVenta, mes;

\echo S12a
-- S12a. Clientes que compraron todos los vinos de una bodega.
-- Cambiar el CUIT de la bodega. Materializar por cliente el conjunto de
-- vinos comprados de esa bodega. La división busca si queda algún vino faltante.
:plan
WITH bodega_elegida AS (
    SELECT cuit FROM bodega WHERE cuit = '30000000000'
), catalogo AS (
    SELECT v.codigoVino FROM vino v JOIN bodega_elegida b ON b.cuit = v.cuitBodega
), compras AS (
    SELECT c.idCliente, array_agg(DISTINCT r.codigoVino) AS vinos
    FROM catalogo v
    JOIN renglon_comprobante r USING (codigoVino)
    JOIN comprobante c ON c.numero = r.numeroComprobante
    GROUP BY c.idCliente
)
SELECT cl.idCliente
FROM cliente cl LEFT JOIN compras co USING (idCliente)
WHERE EXISTS (SELECT 1 FROM bodega_elegida)
  AND NOT EXISTS (
      SELECT 1 FROM catalogo v
      WHERE NOT (v.codigoVino = ANY(COALESCE(co.vinos, ARRAY[]::bigint[])))
  )
ORDER BY cl.idCliente;

\echo S12b
-- S12b. Clientes que nunca compraron ningún vino tinto.
-- Anti-join con NOT EXISTS. Incluye clientes sin compras.
:plan
SELECT cl.idCliente
FROM cliente cl
WHERE NOT EXISTS (
    SELECT 1
    FROM comprobante c
    JOIN renglon_comprobante r ON r.numeroComprobante = c.numero
    JOIN vino v ON v.codigoVino = r.codigoVino
    WHERE c.idCliente = cl.idCliente AND v.tipo = 'tinto'
)
ORDER BY cl.idCliente;
