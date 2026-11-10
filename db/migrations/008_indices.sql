-- S3: igualdad por sala, luego rango por fecha. idCliente cubre el join.
CREATE INDEX idx_comprobante_sala_fecha
    ON public.comprobante (idSalaVenta, fecha) INCLUDE (idCliente);

-- S8: delimita el trimestre por fecha y cubre sala y total para la suma.
CREATE INDEX idx_comprobante_fecha_ventas
    ON public.comprobante (fecha) INCLUDE (idSalaVenta, total);

CREATE INDEX idx_comprobante_cliente
    ON public.comprobante (idCliente);

-- S12: parte de los vinos de una bodega y busca sus comprobantes.
CREATE INDEX idx_renglon_comprobante_vino
    ON public.renglon_comprobante (codigoVino, numeroComprobante);

-- S5: solo interesa la cola de transferencias aún sin procesar.
CREATE INDEX idx_transferencia_pendiente_sala
    ON public.transferencia (idSalaVenta) WHERE estado <> 'procesado';
