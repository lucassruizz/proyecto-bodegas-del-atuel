-- Procedimientos que procesan documentos terminados.

-- RN-10: incorpora al depósito el contenido de un ingreso terminado.
CREATE OR REPLACE PROCEDURE sp_procesar_ingreso(p_codigo_ingreso bigint)
LANGUAGE plpgsql
AS $$
DECLARE
    v_estado estado_documento;
    v_fila contiene%ROWTYPE;
BEGIN
    SELECT estado
      INTO v_estado
      FROM ingresos
     WHERE codigoIngreso = p_codigo_ingreso
     FOR UPDATE;

    IF NOT FOUND OR v_estado <> 'terminado' THEN
        RAISE EXCEPTION 'El ingreso % debe existir y estar terminado', p_codigo_ingreso;
    END IF;

    FOR v_fila IN
        SELECT *
          FROM contiene
         WHERE codigoIngreso = p_codigo_ingreso
    LOOP
        INSERT INTO almacena (codigoVino, idDeposito, cantidadStock)
        VALUES (v_fila.codigoVino, 1, v_fila.cantidadBotellas)
        ON CONFLICT (codigoVino)
        DO UPDATE SET cantidadStock = almacena.cantidadStock + EXCLUDED.cantidadStock;
    END LOOP;

    UPDATE ingresos
       SET estado = 'procesado'
     WHERE codigoIngreso = p_codigo_ingreso;
END;
$$;

-- RN-11: envía al stock de una sala una transferencia terminada.
CREATE OR REPLACE PROCEDURE sp_procesar_transferencia(p_numero_solicitud bigint)
LANGUAGE plpgsql
AS $$
DECLARE
    v_estado estado_documento;
    v_sala bigint;
    v_fila incluye%ROWTYPE;
    v_stock integer;
BEGIN
    SELECT estado, idSalaVenta
      INTO v_estado, v_sala
      FROM transferencia
     WHERE numeroSolicitud = p_numero_solicitud
     FOR UPDATE;

    IF NOT FOUND OR v_estado <> 'terminado' THEN
        RAISE EXCEPTION 'La transferencia % debe existir y estar terminada', p_numero_solicitud;
    END IF;

    FOR v_fila IN
        SELECT *
          FROM incluye
         WHERE numeroSolicitud = p_numero_solicitud
         ORDER BY codigoVino
    LOOP
        SELECT cantidadStock
          INTO v_stock
          FROM almacena
         WHERE codigoVino = v_fila.codigoVino
           AND idDeposito = 1
         FOR UPDATE;

        IF NOT FOUND OR v_stock < v_fila.cantidad THEN
            RAISE EXCEPTION 'Stock insuficiente para el vino %', v_fila.codigoVino;
        END IF;

        UPDATE almacena
           SET cantidadStock = cantidadStock - v_fila.cantidad
         WHERE codigoVino = v_fila.codigoVino
           AND idDeposito = 1;

        INSERT INTO posee (idSalaVenta, codigoVino, cantidadStock)
        VALUES (v_sala, v_fila.codigoVino, v_fila.cantidad)
        ON CONFLICT (idSalaVenta, codigoVino)
        DO UPDATE SET cantidadStock = posee.cantidadStock + EXCLUDED.cantidadStock;
    END LOOP;

    UPDATE transferencia
       SET estado = 'procesado'
     WHERE numeroSolicitud = p_numero_solicitud;
END;
$$;

