-- S8: Ventas por sala de los últimos tres meses al cierre del dataset.
SELECT idSalaVenta, SUM(total) AS ventas
FROM comprobante
WHERE fecha >= DATE '2026-11-08' - INTERVAL '3 months'
  AND fecha < DATE '2026-11-08'
GROUP BY idSalaVenta
ORDER BY ventas DESC, idSalaVenta
