-- S12: clientes que compraron todos los vinos de la bodega.
-- Contar vinos distintos evita duplicar el aporte de las compras repetidas.
WITH vinos_bodega AS (
    SELECT codigoVino
    FROM vino
    WHERE cuitBodega = '30000000000'
)
SELECT c.idCliente
FROM vinos_bodega v
JOIN renglon_comprobante r USING (codigoVino)
JOIN comprobante c ON c.numero = r.numeroComprobante
GROUP BY c.idCliente
HAVING COUNT(DISTINCT r.codigoVino) = (SELECT COUNT(*) FROM vinos_bodega)
ORDER BY c.idCliente
