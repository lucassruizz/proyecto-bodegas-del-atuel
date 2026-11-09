-- Segunda parte de S12: clientes sin compras de vino tinto.
SELECT cl.idCliente
FROM cliente cl
WHERE NOT EXISTS (
    SELECT 1
    FROM comprobante c
    JOIN renglon_comprobante r ON r.numeroComprobante = c.numero
    JOIN vino v ON v.codigoVino = r.codigoVino
    WHERE c.idCliente = cl.idCliente AND v.tipo = 'tinto'
)
ORDER BY cl.idCliente
