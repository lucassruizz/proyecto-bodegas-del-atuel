-- S5: Salas empatadas en la menor cantidad de transferencias pendientes.
WITH pendientes AS (
    SELECT idSalaVenta, COUNT(*) AS cantidad
    FROM transferencia
    WHERE estado <> 'procesado'
    GROUP BY idSalaVenta
),
por_sala AS (
    SELECT s.idSalaVenta, COALESCE(p.cantidad, 0) AS cantidad
    FROM sala_venta s LEFT JOIN pendientes p USING (idSalaVenta)
)
SELECT idSalaVenta, cantidad
FROM por_sala
WHERE cantidad = (SELECT MIN(cantidad) FROM por_sala)
ORDER BY idSalaVenta
