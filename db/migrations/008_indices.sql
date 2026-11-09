-- S3: igualdad por sala, luego rango por fecha. idCliente cubre el join.
CREATE INDEX idx_comprobante_sala_fecha
    ON public.comprobante (idSalaVenta, fecha) INCLUDE (idCliente);

-- S8: delimita el trimestre por fecha y cubre sala y total para la suma.
CREATE INDEX idx_comprobante_fecha_ventas
    ON public.comprobante (fecha) INCLUDE (idSalaVenta, total);

-- FK de comprobante a cliente: acelera la búsqueda de compras de un cliente
-- y la comprobación de referencias al actualizar o borrar un cliente.
CREATE INDEX idx_comprobante_cliente
    ON public.comprobante (idCliente);

-- S12: parte de los vinos de una bodega y busca sus comprobantes.
-- La PK existente comienza por numeroComprobante, no por codigoVino.
CREATE INDEX idx_renglon_comprobante_vino
    ON public.renglon_comprobante (codigoVino, numeroComprobante);

-- S5: solo interesa la cola de transferencias aún sin procesar.
CREATE INDEX idx_transferencia_pendiente_sala
    ON public.transferencia (idSalaVenta) WHERE estado <> 'procesado';
