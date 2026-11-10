-- S3: Clientes distintos por tipo en la sala 1 durante siete días.
WITH compradores AS (
    SELECT DISTINCT idCliente
    FROM comprobante
    WHERE idSalaVenta = 1
      AND fecha >= DATE '2026-11-08' - 7
      AND fecha < DATE '2026-11-08'
)
SELECT COUNT(s.idCliente) AS socios,
       COUNT(d.idCliente) AS distribuidores,
       COUNT(e.idCliente) AS exportadores
FROM compradores c
LEFT JOIN socio_club s USING (idCliente)
LEFT JOIN distribuidor d USING (idCliente)
LEFT JOIN exportador e USING (idCliente)
