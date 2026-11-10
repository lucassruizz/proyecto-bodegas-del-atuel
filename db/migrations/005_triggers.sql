-- Triggers

-- RN-09: valida stock disponible en INSERT y UPDATE, contemplando la restitución
-- lógica del renglón anterior cuando se modifica el vino o el comprobante.
CREATE OR REPLACE FUNCTION fn_validar_stock_venta()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_sala_new bigint;
    v_sala_old bigint;
    v_stock integer;
    v_descuento numeric(5,2);
    v_stock_efectivo integer;
BEGIN
    SELECT c.idSalaVenta, fn_descuento_cliente(c.idCliente)
      INTO v_sala_new, v_descuento
      FROM comprobante c
     WHERE c.numero = NEW.numeroComprobante;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'El comprobante % no existe', NEW.numeroComprobante;
    END IF;

    IF TG_OP = 'UPDATE' THEN
        SELECT idSalaVenta INTO v_sala_old
          FROM comprobante WHERE numero = OLD.numeroComprobante;
    END IF;

    -- Bloquea el stock destino para evitar que dos ventas consuman la misma disponibilidad.
    SELECT cantidadStock INTO v_stock
      FROM posee
     WHERE idSalaVenta = v_sala_new
       AND codigoVino = NEW.codigoVino
     FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No existe registro de stock para el vino % en la sala %',
            NEW.codigoVino, v_sala_new;
    END IF;

    v_stock_efectivo := v_stock;

    -- Si el renglón permanece en la misma sala y para el mismo vino, la cantidad
    -- anterior se libera antes de comprobar la nueva cantidad.
    IF TG_OP = 'UPDATE'
       AND OLD.codigoVino = NEW.codigoVino
       AND v_sala_old = v_sala_new THEN
        v_stock_efectivo := v_stock + OLD.cantidad;
    END IF;

    IF v_stock_efectivo < NEW.cantidad THEN
        RAISE EXCEPTION
            'Stock insuficiente del vino % en la sala % (solicitado: %, disponible incluyendo restitución: %)',
            NEW.codigoVino, v_sala_new, NEW.cantidad, v_stock_efectivo;
    END IF;

    NEW.descuento := v_descuento;
    NEW.subtotalRenglon := ROUND(
        NEW.cantidad * NEW.precioUnitario * (1 - NEW.descuento / 100.0), 2
    );
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_renglon_comprobante_stock ON renglon_comprobante;
CREATE TRIGGER trg_renglon_comprobante_stock
BEFORE INSERT OR UPDATE ON renglon_comprobante
FOR EACH ROW EXECUTE FUNCTION fn_validar_stock_venta();

-- RN-08 y RN-09: aplica el movimiento de stock y recalcula ambos comprobantes
-- cuando un UPDATE traslada el renglón de un comprobante a otro.
CREATE OR REPLACE FUNCTION fn_actualizar_venta()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_sala_old bigint;
    v_sala_new bigint;
    v_subtotal numeric(12,2);
    v_descuento numeric(12,2);
    v_total numeric(12,2);
BEGIN
    IF TG_OP = 'INSERT' THEN
        SELECT idSalaVenta INTO v_sala_new
          FROM comprobante WHERE numero = NEW.numeroComprobante;
        UPDATE posee
           SET cantidadStock = cantidadStock - NEW.cantidad
         WHERE idSalaVenta = v_sala_new AND codigoVino = NEW.codigoVino;

    ELSIF TG_OP = 'DELETE' THEN
        SELECT idSalaVenta INTO v_sala_old
          FROM comprobante WHERE numero = OLD.numeroComprobante;
        UPDATE posee
           SET cantidadStock = cantidadStock + OLD.cantidad
         WHERE idSalaVenta = v_sala_old AND codigoVino = OLD.codigoVino;

    ELSE
        SELECT idSalaVenta INTO v_sala_old
          FROM comprobante WHERE numero = OLD.numeroComprobante;
        SELECT idSalaVenta INTO v_sala_new
          FROM comprobante WHERE numero = NEW.numeroComprobante;

        IF v_sala_old = v_sala_new AND OLD.codigoVino = NEW.codigoVino THEN
            UPDATE posee
               SET cantidadStock = cantidadStock - (NEW.cantidad - OLD.cantidad)
             WHERE idSalaVenta = v_sala_new AND codigoVino = NEW.codigoVino;
        ELSE
            UPDATE posee
               SET cantidadStock = cantidadStock + OLD.cantidad
             WHERE idSalaVenta = v_sala_old AND codigoVino = OLD.codigoVino;
            UPDATE posee
               SET cantidadStock = cantidadStock - NEW.cantidad
             WHERE idSalaVenta = v_sala_new AND codigoVino = NEW.codigoVino;
        END IF;
    END IF;

    -- Recalcula el comprobante nuevo (o el único comprobante afectado).
    IF TG_OP <> 'DELETE' THEN
        SELECT COALESCE(SUM(cantidad * precioUnitario), 0),
               COALESCE(SUM(ROUND(cantidad * precioUnitario * descuento / 100.0, 2)), 0),
               COALESCE(SUM(subtotalRenglon), 0)
          INTO v_subtotal, v_descuento, v_total
          FROM renglon_comprobante
         WHERE numeroComprobante = NEW.numeroComprobante;
        UPDATE comprobante
           SET subtotal = v_subtotal, descuento = v_descuento, total = v_total
         WHERE numero = NEW.numeroComprobante;
    END IF;

    -- DELETE y traslado entre comprobantes también afectan al comprobante anterior.
    IF TG_OP = 'DELETE'
       OR (TG_OP = 'UPDATE' AND OLD.numeroComprobante <> NEW.numeroComprobante) THEN
        SELECT COALESCE(SUM(cantidad * precioUnitario), 0),
               COALESCE(SUM(ROUND(cantidad * precioUnitario * descuento / 100.0, 2)), 0),
               COALESCE(SUM(subtotalRenglon), 0)
          INTO v_subtotal, v_descuento, v_total
          FROM renglon_comprobante
         WHERE numeroComprobante = OLD.numeroComprobante;
        UPDATE comprobante
           SET subtotal = v_subtotal, descuento = v_descuento, total = v_total
         WHERE numero = OLD.numeroComprobante;
    END IF;

    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$;

DROP TRIGGER IF EXISTS trg_renglon_comprobante_actualizar ON renglon_comprobante;
CREATE TRIGGER trg_renglon_comprobante_actualizar
AFTER INSERT OR UPDATE OR DELETE ON renglon_comprobante
FOR EACH ROW EXECUTE FUNCTION fn_actualizar_venta();

-- RN-10 y RN-11: Controla las transiciones de estado de documentos.
CREATE OR REPLACE FUNCTION fn_controlar_estado_documento()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.estado <> 'en_confeccion' THEN
            RAISE EXCEPTION 'Un documento debe comenzar en confección';
        END IF;
        RETURN NEW;
    END IF;

    IF NEW.estado = OLD.estado THEN
        RETURN NEW;
    END IF;

    IF (OLD.estado = 'en_confeccion' AND NEW.estado = 'terminado')
       OR (OLD.estado = 'terminado' AND NEW.estado = 'procesado') THEN
        RETURN NEW;
    END IF;

    RAISE EXCEPTION 'Transición de estado no permitida: % a %',
        OLD.estado, NEW.estado;
END;
$$;

DROP TRIGGER IF EXISTS trg_ingresos_estado ON ingresos;
CREATE TRIGGER trg_ingresos_estado
BEFORE INSERT OR UPDATE OF estado ON ingresos
FOR EACH ROW EXECUTE FUNCTION fn_controlar_estado_documento();

DROP TRIGGER IF EXISTS trg_transferencia_estado ON transferencia;
CREATE TRIGGER trg_transferencia_estado
BEFORE INSERT OR UPDATE OF estado ON transferencia
FOR EACH ROW EXECUTE FUNCTION fn_controlar_estado_documento();

-- RN-12: No permite modificar renglones si el documento ya no está en confección (INSERT, UPDATE y DELETE).
CREATE OR REPLACE FUNCTION fn_bloquear_renglones_documento()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_estado_old estado_documento;
    v_estado_new estado_documento;
BEGIN
    IF TG_TABLE_NAME = 'contiene' THEN
        IF TG_OP IN ('UPDATE', 'DELETE') THEN
            SELECT estado INTO v_estado_old FROM ingresos WHERE codigoIngreso = OLD.codigoIngreso;
            IF v_estado_old IS DISTINCT FROM 'en_confeccion' THEN
                RAISE EXCEPTION 'No se pueden modificar renglones de un ingreso no confeccionado';
            END IF;
        END IF;

        IF TG_OP IN ('INSERT', 'UPDATE') THEN
            SELECT estado INTO v_estado_new FROM ingresos WHERE codigoIngreso = NEW.codigoIngreso;
            IF v_estado_new IS DISTINCT FROM 'en_confeccion' THEN
                RAISE EXCEPTION 'No se pueden modificar renglones de un ingreso no confeccionado';
            END IF;
        END IF;
    ELSE
        IF TG_OP IN ('UPDATE', 'DELETE') THEN
            SELECT estado INTO v_estado_old FROM transferencia WHERE numeroSolicitud = OLD.numeroSolicitud;
            IF v_estado_old IS DISTINCT FROM 'en_confeccion' THEN
                RAISE EXCEPTION 'No se pueden modificar renglones de una transferencia no confeccionada';
            END IF;
        END IF;

        IF TG_OP IN ('INSERT', 'UPDATE') THEN
            SELECT estado INTO v_estado_new FROM transferencia WHERE numeroSolicitud = NEW.numeroSolicitud;
            IF v_estado_new IS DISTINCT FROM 'en_confeccion' THEN
                RAISE EXCEPTION 'No se pueden modificar renglones de una transferencia no confeccionada';
            END IF;
        END IF;
    END IF;

    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$;

DROP TRIGGER IF EXISTS trg_contiene_bloqueo ON contiene;
CREATE TRIGGER trg_contiene_bloqueo
BEFORE INSERT OR UPDATE OR DELETE ON contiene
FOR EACH ROW EXECUTE FUNCTION fn_bloquear_renglones_documento();

DROP TRIGGER IF EXISTS trg_incluye_bloqueo ON incluye;
CREATE TRIGGER trg_incluye_bloqueo
BEFORE INSERT OR UPDATE OR DELETE ON incluye
FOR EACH ROW EXECUTE FUNCTION fn_bloquear_renglones_documento();

-- RN-11: Asigna la fecha actual y evita que se cambie.
CREATE OR REPLACE FUNCTION fn_fecha_transferencia()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        NEW.fechaConfeccion := CURRENT_DATE;
    ELSIF NEW.fechaConfeccion <> OLD.fechaConfeccion THEN
        RAISE EXCEPTION 'La fecha de confección no se puede modificar';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_transferencia_fecha ON transferencia;
CREATE TRIGGER trg_transferencia_fecha
BEFORE INSERT OR UPDATE ON transferencia
FOR EACH ROW EXECUTE FUNCTION fn_fecha_transferencia();

-- RN-13: Registra los cambios de precio.
CREATE OR REPLACE FUNCTION fn_auditar_precio_vino()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.precio IS DISTINCT FROM OLD.precio THEN
        INSERT INTO auditoria_precio (
            codigoVino, precioAnterior, precioNuevo, fechaHora, usuario
        )
        VALUES (
            NEW.codigoVino, OLD.precio, NEW.precio, CURRENT_TIMESTAMP, CURRENT_USER
        );
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_vino_auditar_precio ON vino;
CREATE TRIGGER trg_vino_auditar_precio
AFTER UPDATE OF precio ON vino
FOR EACH ROW EXECUTE FUNCTION fn_auditar_precio_vino();

-- RN-05: al cerrar la transacción, cada vino afectado debe conservar
-- una composición existente cuya suma sea exactamente 100%.
CREATE OR REPLACE FUNCTION fn_validar_porcentaje_corte()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_vino_old bigint;
    v_vino_new bigint;
    v_total numeric(9,2);
BEGIN
    IF TG_OP <> 'INSERT' THEN
        v_vino_old := OLD.codigoVino;
        SELECT COALESCE(SUM(porcentaje), 0)
          INTO v_total
          FROM componen
         WHERE codigoVino = v_vino_old;
        IF v_total <> 100 THEN
            RAISE EXCEPTION
                'RN-05: los porcentajes del vino % deben sumar 100 (suma actual: %)',
                v_vino_old, v_total;
        END IF;
    END IF;

    IF TG_OP <> 'DELETE' THEN
        v_vino_new := NEW.codigoVino;
        -- Si OLD y NEW refieren al mismo vino, ya se comprobó el estado final.
        IF TG_OP <> 'UPDATE' OR v_vino_new IS DISTINCT FROM v_vino_old THEN
            SELECT COALESCE(SUM(porcentaje), 0)
              INTO v_total
              FROM componen
             WHERE codigoVino = v_vino_new;
            IF v_total <> 100 THEN
                RAISE EXCEPTION
                    'RN-05: los porcentajes del vino % deben sumar 100 (suma actual: %)',
                    v_vino_new, v_total;
            END IF;
        END IF;
    END IF;

    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_componen_porcentaje ON componen;
CREATE CONSTRAINT TRIGGER trg_componen_porcentaje
AFTER INSERT OR UPDATE OR DELETE ON componen
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION fn_validar_porcentaje_corte();

-- RN-02: Garantiza que cada localidad tenga exactamente un encargado regional al cerrar la transacción.
CREATE OR REPLACE FUNCTION fn_validar_encargado_localidad()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_localidad bigint;
BEGIN
    IF TG_OP = 'UPDATE' AND OLD.idLocalidad <> NEW.idLocalidad THEN
        IF NOT EXISTS (SELECT 1 FROM encargado_regional WHERE idLocalidad = OLD.idLocalidad) THEN
            RAISE EXCEPTION 'La localidad % no tiene encargado regional asignado', OLD.idLocalidad;
        END IF;
    END IF;

    v_localidad := CASE WHEN TG_OP = 'DELETE' THEN OLD.idLocalidad ELSE NEW.idLocalidad END;

    IF NOT EXISTS (SELECT 1 FROM encargado_regional WHERE idLocalidad = v_localidad) THEN
        RAISE EXCEPTION 'La localidad % no tiene encargado regional asignado', v_localidad;
    END IF;

    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_localidad_encargado ON localidad;
CREATE CONSTRAINT TRIGGER trg_localidad_encargado
AFTER INSERT ON localidad
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION fn_validar_encargado_localidad();

DROP TRIGGER IF EXISTS trg_encargado_localidad_existencia ON encargado_regional;
CREATE CONSTRAINT TRIGGER trg_encargado_localidad_existencia
AFTER UPDATE OR DELETE ON encargado_regional
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION fn_validar_encargado_localidad();

-- Elimina los triggers de la versión anterior para evitar validaciones duplicadas.
DROP TRIGGER IF EXISTS trg_socio_club_subtipo ON socio_club;
DROP TRIGGER IF EXISTS trg_distribuidor_subtipo ON distribuidor;
DROP TRIGGER IF EXISTS trg_exportador_subtipo ON exportador;
DROP TRIGGER IF EXISTS trg_cliente_subtipo_existencia ON cliente;

-- RN-06: especialización disjunta y total; el descuento debe coincidir
-- con el subtipo incluso si se modifica cliente.descuento o se elimina un subtipo.
CREATE OR REPLACE FUNCTION fn_validar_integridad_subtipo_cliente()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_id_cliente bigint;
    v_candidatos bigint[];
    v_id bigint;
    v_cantidad integer;
    v_descuento numeric(5,2);
    v_esperado numeric(5,2);
BEGIN
    IF TG_TABLE_NAME = 'cliente' THEN
        IF TG_OP = 'DELETE' THEN
            RETURN NULL;
        END IF;
        v_candidatos := ARRAY[NEW.idCliente];
    ELSIF TG_OP = 'INSERT' THEN
        v_candidatos := ARRAY[NEW.idCliente];
    ELSIF TG_OP = 'DELETE' THEN
        v_candidatos := ARRAY[OLD.idCliente];
    ELSE
        v_candidatos := ARRAY[OLD.idCliente, NEW.idCliente];
    END IF;

    FOREACH v_id IN ARRAY v_candidatos LOOP
        IF v_id IS NULL OR NOT EXISTS (
            SELECT 1 FROM cliente WHERE idCliente = v_id
        ) THEN
            CONTINUE;
        END IF;

        SELECT
            (CASE WHEN EXISTS (SELECT 1 FROM socio_club WHERE idCliente = v_id) THEN 1 ELSE 0 END)
          + (CASE WHEN EXISTS (SELECT 1 FROM distribuidor WHERE idCliente = v_id) THEN 1 ELSE 0 END)
          + (CASE WHEN EXISTS (SELECT 1 FROM exportador WHERE idCliente = v_id) THEN 1 ELSE 0 END),
            CASE
                WHEN EXISTS (SELECT 1 FROM socio_club WHERE idCliente = v_id) THEN 10.00
                WHEN EXISTS (SELECT 1 FROM distribuidor WHERE idCliente = v_id) THEN 20.00
                WHEN EXISTS (SELECT 1 FROM exportador WHERE idCliente = v_id) THEN 30.00
                ELSE NULL
            END
          INTO v_cantidad, v_esperado;

        IF v_cantidad <> 1 THEN
            RAISE EXCEPTION
                'RN-06: el cliente % debe pertenecer a exactamente un subtipo; se encontraron %',
                v_id, v_cantidad;
        END IF;

        SELECT descuento INTO v_descuento
          FROM cliente WHERE idCliente = v_id;
        IF v_descuento IS DISTINCT FROM v_esperado THEN
            RAISE EXCEPTION
                'RN-06: descuento incorrecto para cliente %: actual %, esperado %',
                v_id, v_descuento, v_esperado;
        END IF;
    END LOOP;

    RETURN NULL;
END;
$$;

-- La comprobación diferida permite crear primero el cliente y luego su subtipo
-- dentro de la misma transacción, pero impide confirmar estados inconsistentes.
DROP TRIGGER IF EXISTS trg_cliente_subtipo_integridad ON cliente;
CREATE CONSTRAINT TRIGGER trg_cliente_subtipo_integridad
AFTER INSERT OR UPDATE ON cliente
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION fn_validar_integridad_subtipo_cliente();

DROP TRIGGER IF EXISTS trg_socio_club_subtipo_integridad ON socio_club;
CREATE CONSTRAINT TRIGGER trg_socio_club_subtipo_integridad
AFTER INSERT OR UPDATE OR DELETE ON socio_club
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION fn_validar_integridad_subtipo_cliente();

DROP TRIGGER IF EXISTS trg_distribuidor_subtipo_integridad ON distribuidor;
CREATE CONSTRAINT TRIGGER trg_distribuidor_subtipo_integridad
AFTER INSERT OR UPDATE OR DELETE ON distribuidor
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION fn_validar_integridad_subtipo_cliente();

DROP TRIGGER IF EXISTS trg_exportador_subtipo_integridad ON exportador;
CREATE CONSTRAINT TRIGGER trg_exportador_subtipo_integridad
AFTER INSERT OR UPDATE OR DELETE ON exportador
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION fn_validar_integridad_subtipo_cliente();
