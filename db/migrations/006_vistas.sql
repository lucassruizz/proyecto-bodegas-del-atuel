-- Vistas

-- Stock total por vino, sumando depósito y salas.
CREATE OR REPLACE VIEW vw_stock_total_vino AS
SELECT v.codigoVino,
       v.nombre,
       COALESCE(d.stock_deposito, 0) AS stock_deposito,
       COALESCE(s.stock_salas, 0) AS stock_salas,
       COALESCE(d.stock_deposito, 0) + COALESCE(s.stock_salas, 0) AS stock_total
FROM vino v
LEFT JOIN (
    SELECT codigoVino, SUM(cantidadStock) AS stock_deposito
    FROM almacena
    GROUP BY codigoVino
) d ON d.codigoVino = v.codigoVino
LEFT JOIN (
    SELECT codigoVino, SUM(cantidadStock) AS stock_salas
    FROM posee
    GROUP BY codigoVino
) s ON s.codigoVino = v.codigoVino;

-- Ventas mensuales agrupadas por sala.
CREATE OR REPLACE VIEW vw_ventas_mensuales_sala AS
SELECT c.idSalaVenta,
       date_trunc('month', c.fecha)::date AS mes,
       COUNT(*) AS cantidad_comprobantes,
       SUM(c.total) AS total_vendido
FROM comprobante c
GROUP BY c.idSalaVenta, date_trunc('month', c.fecha)::date;

-- Ingresos y transferencias que todavía no fueron procesados.
CREATE OR REPLACE VIEW vw_documentos_pendientes AS
SELECT 'ingreso'::varchar AS tipo_documento,
       codigoIngreso AS numero,
       fecha,
       estado
FROM ingresos
WHERE estado <> 'procesado'
UNION ALL
SELECT 'transferencia'::varchar AS tipo_documento,
       numeroSolicitud AS numero,
       fechaConfeccion AS fecha,
       estado
FROM transferencia
WHERE estado <> 'procesado';

