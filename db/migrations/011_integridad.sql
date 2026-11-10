BEGIN;

-- La fecha de cosecha y la campaña tienen que referirse al mismo año.
ALTER TABLE departamento ADD CONSTRAINT uq_departamento_nombre_provincia
    UNIQUE (nombreDepartamento, provincia);
ALTER TABLE lote ADD CONSTRAINT ck_lote_campania_fecha
    CHECK (campania = EXTRACT(YEAR FROM fechaCosecha));

-- RN-08. Las cabeceras empiezan en cero y el trigger guarda sus importes.
ALTER TABLE comprobante
    ALTER COLUMN subtotal SET DEFAULT 0,
    ALTER COLUMN descuento SET DEFAULT 0,
    ALTER COLUMN total SET DEFAULT 0;

-- RN-09. La validación necesita bloquear el saldo de stock de la sala.
CREATE OR REPLACE FUNCTION fn_validar_stock_venta()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
    v_sala_new bigint;
    v_sala_old bigint;
    v_stock integer;
    v_descuento numeric(5,2);
    v_stock_efectivo integer;
BEGIN
    -- Serializa los cambios de renglones de una misma venta antes de sumar.
    IF TG_OP = 'INSERT' THEN
        PERFORM 1 FROM comprobante WHERE numero = NEW.numeroComprobante FOR NO KEY UPDATE;
    ELSIF TG_OP = 'DELETE' THEN
        PERFORM 1 FROM comprobante WHERE numero = OLD.numeroComprobante FOR NO KEY UPDATE;
        RETURN OLD;
    ELSE
        PERFORM 1 FROM comprobante
         WHERE numero IN (OLD.numeroComprobante, NEW.numeroComprobante)
         ORDER BY numero FOR NO KEY UPDATE;
    END IF;

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
    NEW.subtotalRenglon := NEW.cantidad * NEW.precioUnitario
        - ROUND(NEW.cantidad * NEW.precioUnitario * NEW.descuento / 100.0, 2);
    RETURN NEW;
END;
$$;

DROP TRIGGER trg_renglon_comprobante_stock ON renglon_comprobante;
-- RN-08 y RN-09. Bloquea el comprobante también antes de quitar un renglón.
CREATE TRIGGER trg_renglon_comprobante_stock
BEFORE INSERT OR UPDATE OR DELETE ON renglon_comprobante
FOR EACH ROW EXECUTE FUNCTION fn_validar_stock_venta();

-- RN-08 y RN-09. El rol de la API no escribe directamente los saldos ni los totales.
CREATE OR REPLACE FUNCTION fn_actualizar_venta()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
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

-- RN-12. El cierre y la edición de los renglones compiten por el mismo bloqueo.
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
            SELECT estado INTO v_estado_old FROM ingresos WHERE codigoIngreso = OLD.codigoIngreso FOR NO KEY UPDATE;
            IF v_estado_old IS DISTINCT FROM 'en_confeccion' THEN
                RAISE EXCEPTION 'No se pueden modificar renglones de un ingreso no confeccionado';
            END IF;
        END IF;

        IF TG_OP IN ('INSERT', 'UPDATE') THEN
            SELECT estado INTO v_estado_new FROM ingresos WHERE codigoIngreso = NEW.codigoIngreso FOR NO KEY UPDATE;
            IF v_estado_new IS DISTINCT FROM 'en_confeccion' THEN
                RAISE EXCEPTION 'No se pueden modificar renglones de un ingreso no confeccionado';
            END IF;
        END IF;
    ELSE
        IF TG_OP IN ('UPDATE', 'DELETE') THEN
            SELECT estado INTO v_estado_old FROM transferencia WHERE numeroSolicitud = OLD.numeroSolicitud FOR NO KEY UPDATE;
            IF v_estado_old IS DISTINCT FROM 'en_confeccion' THEN
                RAISE EXCEPTION 'No se pueden modificar renglones de una transferencia no confeccionada';
            END IF;
        END IF;

        IF TG_OP IN ('INSERT', 'UPDATE') THEN
            SELECT estado INTO v_estado_new FROM transferencia WHERE numeroSolicitud = NEW.numeroSolicitud FOR NO KEY UPDATE;
            IF v_estado_new IS DISTINCT FROM 'en_confeccion' THEN
                RAISE EXCEPTION 'No se pueden modificar renglones de una transferencia no confeccionada';
            END IF;
        END IF;
    END IF;

    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$;

-- RN-10 y RN-11. Mover el stock y cambiar el estado en la misma sentencia.
-- Tanto CALL como un UPDATE directo pasan por este trigger.
CREATE OR REPLACE FUNCTION fn_controlar_estado_documento()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
    v_ingreso contiene%ROWTYPE;
    v_transferencia incluye%ROWTYPE;
    v_stock integer;
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.estado <> 'en_confeccion' THEN
            RAISE EXCEPTION 'Un documento debe comenzar en confección';
        END IF;
        RETURN NEW;
    END IF;

    IF OLD.estado <> 'en_confeccion'
       AND (to_jsonb(OLD) - 'estado') IS DISTINCT FROM (to_jsonb(NEW) - 'estado') THEN
        RAISE EXCEPTION 'No se pueden modificar los datos de un documento cerrado';
    END IF;

    IF NEW.estado = OLD.estado THEN
        RETURN NEW;
    END IF;

    IF OLD.estado = 'en_confeccion' AND NEW.estado = 'terminado' THEN
        IF TG_TABLE_NAME = 'ingresos' THEN
            IF NOT EXISTS (SELECT 1 FROM contiene WHERE codigoIngreso = NEW.codigoIngreso) THEN
                RAISE EXCEPTION 'El ingreso no tiene renglones';
            END IF;
        ELSIF NOT EXISTS (SELECT 1 FROM incluye WHERE numeroSolicitud = NEW.numeroSolicitud) THEN
            RAISE EXCEPTION 'La transferencia no tiene renglones';
        END IF;
        RETURN NEW;
    END IF;

    IF OLD.estado <> 'terminado' OR NEW.estado <> 'procesado' THEN
        RAISE EXCEPTION 'Transición de estado no permitida: % a %', OLD.estado, NEW.estado;
    END IF;

    IF TG_TABLE_NAME = 'ingresos' THEN
        FOR v_ingreso IN
            SELECT *
              FROM contiene
             WHERE codigoIngreso = NEW.codigoIngreso
             ORDER BY codigoVino
        LOOP
            INSERT INTO almacena (codigoVino, idDeposito, cantidadStock)
            VALUES (v_ingreso.codigoVino, 1, v_ingreso.cantidadBotellas)
            ON CONFLICT (codigoVino)
            DO UPDATE SET cantidadStock = almacena.cantidadStock + EXCLUDED.cantidadStock;
        END LOOP;
    ELSE
        FOR v_transferencia IN
            SELECT *
              FROM incluye
             WHERE numeroSolicitud = NEW.numeroSolicitud
             ORDER BY codigoVino
        LOOP
            SELECT cantidadStock
              INTO v_stock
              FROM almacena
             WHERE codigoVino = v_transferencia.codigoVino
               AND idDeposito = 1
             FOR UPDATE;

            IF NOT FOUND OR v_stock < v_transferencia.cantidad THEN
                RAISE EXCEPTION 'Stock insuficiente para el vino %', v_transferencia.codigoVino;
            END IF;

            UPDATE almacena
               SET cantidadStock = cantidadStock - v_transferencia.cantidad
             WHERE codigoVino = v_transferencia.codigoVino
               AND idDeposito = 1;

            INSERT INTO posee (idSalaVenta, codigoVino, cantidadStock)
            VALUES (NEW.idSalaVenta, v_transferencia.codigoVino, v_transferencia.cantidad)
            ON CONFLICT (idSalaVenta, codigoVino)
            DO UPDATE SET cantidadStock = posee.cantidadStock + EXCLUDED.cantidadStock;
        END LOOP;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER trg_ingresos_estado ON ingresos;
-- RN-10. Controla las transiciones e incorpora el stock del ingreso.
CREATE TRIGGER trg_ingresos_estado
BEFORE INSERT OR UPDATE ON ingresos
FOR EACH ROW EXECUTE FUNCTION fn_controlar_estado_documento();

DROP TRIGGER trg_transferencia_estado ON transferencia;
-- RN-11. Controla las transiciones y mueve el stock a la sala.
CREATE TRIGGER trg_transferencia_estado
BEFORE INSERT OR UPDATE ON transferencia
FOR EACH ROW EXECUTE FUNCTION fn_controlar_estado_documento();

-- Los procedimientos conservan su nombre y el mensaje que usa la API.
-- El UPDATE bloquea la cabecera y ejecuta el movimiento en el trigger.
CREATE OR REPLACE PROCEDURE sp_procesar_ingreso(p_codigo_ingreso bigint)
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE ingresos SET estado = 'procesado'
     WHERE codigoIngreso = p_codigo_ingreso AND estado = 'terminado';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'El ingreso % debe existir y estar terminado', p_codigo_ingreso;
    END IF;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_procesar_transferencia(p_numero_solicitud bigint)
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE transferencia SET estado = 'procesado'
     WHERE numeroSolicitud = p_numero_solicitud AND estado = 'terminado';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'La transferencia % debe existir y estar terminada', p_numero_solicitud;
    END IF;
END;
$$;

-- RN-05. También se comprueba al crear un vino que aún no tiene cepas.
CREATE OR REPLACE FUNCTION fn_validar_porcentaje_corte()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_vinos bigint[];
    v_codigo bigint;
    v_total numeric;
BEGIN
    IF TG_OP = 'INSERT' THEN
        v_vinos := ARRAY[NEW.codigoVino];
    ELSIF TG_OP = 'DELETE' THEN
        v_vinos := ARRAY[OLD.codigoVino];
    ELSE
        v_vinos := ARRAY[OLD.codigoVino, NEW.codigoVino];
    END IF;

    FOR v_codigo IN
        SELECT DISTINCT codigo FROM unnest(v_vinos) AS vinos(codigo) ORDER BY codigo
    LOOP
        PERFORM 1 FROM vino WHERE codigoVino = v_codigo FOR NO KEY UPDATE;
        IF NOT FOUND THEN
            CONTINUE;
        END IF;

        SELECT COALESCE(SUM(porcentaje), 0) INTO v_total
          FROM componen WHERE codigoVino = v_codigo;
        IF v_total <> 100 THEN
            RAISE EXCEPTION 'RN-05: los porcentajes del vino % deben sumar 100 (suma actual: %)',
                v_codigo, v_total;
        END IF;
    END LOOP;
    RETURN NULL;
END;
$$;

-- RN-05. La ficha nueva debe quedar con un corte completo al confirmar.
CREATE CONSTRAINT TRIGGER trg_vino_corte
AFTER INSERT ON vino DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION fn_validar_porcentaje_corte();

-- El escenario pide al menos un maridaje por vino y un análisis por lote.
-- Se comprueban al cierre para poder guardar primero la ficha y luego el detalle.
CREATE FUNCTION fn_validar_maridaje_vino()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF EXISTS (SELECT 1 FROM vino WHERE codigoVino = NEW.codigoVino)
           AND NOT EXISTS (SELECT 1 FROM tienen WHERE codigoVino = NEW.codigoVino) THEN
            RAISE EXCEPTION 'El vino % debe tener al menos un maridaje', NEW.codigoVino;
        END IF;
    ELSE
        PERFORM 1 FROM vino WHERE codigoVino = OLD.codigoVino FOR NO KEY UPDATE;
        IF FOUND AND NOT EXISTS (SELECT 1 FROM tienen WHERE codigoVino = OLD.codigoVino) THEN
            RAISE EXCEPTION 'El vino % debe tener al menos un maridaje', OLD.codigoVino;
        END IF;
    END IF;
    RETURN NULL;
END;
$$;

-- Participación mínima de vino en maridajes (sección 3.3).
CREATE CONSTRAINT TRIGGER trg_vino_maridaje
AFTER INSERT ON vino DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION fn_validar_maridaje_vino();

-- Participación mínima de vino en maridajes (sección 3.3).
CREATE CONSTRAINT TRIGGER trg_tienen_maridaje
AFTER DELETE OR UPDATE OF codigoVino ON tienen DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION fn_validar_maridaje_vino();

CREATE FUNCTION fn_validar_analisis_lote()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_numero bigint;
BEGIN
    IF TG_OP = 'INSERT' THEN
        v_numero := NEW.numero;
    ELSE
        v_numero := OLD.numeroLote;
    END IF;
    PERFORM 1 FROM lote WHERE numero = v_numero FOR NO KEY UPDATE;
    IF FOUND AND NOT EXISTS (SELECT 1 FROM analisis_calidad WHERE numeroLote = v_numero) THEN
        RAISE EXCEPTION 'El lote % debe tener al menos un análisis de calidad', v_numero;
    END IF;
    RETURN NULL;
END;
$$;

-- Participación mínima de lote en análisis de calidad (sección 3.2).
CREATE CONSTRAINT TRIGGER trg_lote_analisis
AFTER INSERT ON lote DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION fn_validar_analisis_lote();

-- Participación mínima de lote en análisis de calidad (sección 3.2).
CREATE CONSTRAINT TRIGGER trg_analisis_lote
AFTER DELETE OR UPDATE OF numeroLote ON analisis_calidad DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION fn_validar_analisis_lote();

ALTER FUNCTION fn_validar_maridaje_vino() OWNER TO bodega_owner;
ALTER FUNCTION fn_validar_analisis_lote() OWNER TO bodega_owner;
REVOKE EXECUTE ON FUNCTION fn_validar_maridaje_vino(), fn_validar_analisis_lote() FROM PUBLIC;

-- La API conserva las operaciones que usa. Stock y auditoría son de lectura.
REVOKE INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public FROM bodega_api;
GRANT INSERT, UPDATE, DELETE ON vino, componen, tienen, cliente, socio_club,
    distribuidor, exportador TO bodega_api;
GRANT INSERT (numero, idCliente, idSalaVenta, fecha) ON comprobante TO bodega_api;
GRANT INSERT ON renglon_comprobante, contiene, incluye TO bodega_api;
GRANT INSERT (numeroSolicitud, idSalaVenta), UPDATE (estado) ON transferencia TO bodega_api;
GRANT INSERT (codigoIngreso, cuitBodega, codigoTransporte, idDeposito, fecha),
    UPDATE (estado) ON ingresos TO bodega_api;
ALTER DEFAULT PRIVILEGES FOR ROLE bodega_owner IN SCHEMA public
    REVOKE INSERT, UPDATE, DELETE ON TABLES FROM bodega_api;

COMMIT;
