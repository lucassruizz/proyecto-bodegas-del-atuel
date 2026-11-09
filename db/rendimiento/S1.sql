-- Diez vinos con más botellas vendidas en toda la red.
WITH ventas AS (
    SELECT codigoVino, SUM(cantidad) AS botellas
    FROM renglon_comprobante
    GROUP BY codigoVino
)
SELECT v.codigoVino, v.nombre, ventas.botellas
FROM ventas JOIN vino v USING (codigoVino)
ORDER BY ventas.botellas DESC, v.codigoVino
LIMIT 10
