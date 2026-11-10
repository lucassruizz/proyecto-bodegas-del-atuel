-- Funciones

-- Calcula el total de un comprobante desde sus renglones.
CREATE OR REPLACE FUNCTION fn_total_comprobante(p_numero bigint)
RETURNS numeric(12,2)
LANGUAGE sql
STABLE
AS $$
    SELECT COALESCE(
        SUM(subtotalRenglon),
        0
    )::numeric(12,2)
    FROM renglon_comprobante
    WHERE numeroComprobante = p_numero;
$$;

-- Devuelve el stock disponible de vino en la sala.
CREATE OR REPLACE FUNCTION fn_stock_sala(p_sala bigint, p_vino bigint)
RETURNS integer
LANGUAGE sql
STABLE
AS $$
    SELECT COALESCE((
        SELECT cantidadStock
        FROM posee
        WHERE idSalaVenta = p_sala
          AND codigoVino = p_vino
    ), 0);
$$;

-- Devuelve el descuento según el subtipo de cliente y valida especialización disjunta.
CREATE OR REPLACE FUNCTION fn_descuento_cliente(p_cliente bigint)
RETURNS numeric(5,2)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_subtipos integer;
BEGIN
    SELECT (CASE WHEN EXISTS (SELECT 1 FROM socio_club WHERE idCliente = p_cliente) THEN 1 ELSE 0 END)
         + (CASE WHEN EXISTS (SELECT 1 FROM distribuidor WHERE idCliente = p_cliente) THEN 1 ELSE 0 END)
         + (CASE WHEN EXISTS (SELECT 1 FROM exportador WHERE idCliente = p_cliente) THEN 1 ELSE 0 END)
      INTO v_subtipos;

    IF v_subtipos > 1 THEN
        RAISE EXCEPTION 'El cliente % pertenece a más de un subtipo (la jerarquía es disjunta)', p_cliente;
    END IF;

    IF EXISTS (SELECT 1 FROM socio_club WHERE idCliente = p_cliente) THEN
        RETURN 10.00;
    ELSIF EXISTS (SELECT 1 FROM distribuidor WHERE idCliente = p_cliente) THEN
        RETURN 20.00;
    ELSIF EXISTS (SELECT 1 FROM exportador WHERE idCliente = p_cliente) THEN
        RETURN 30.00;
    END IF;

    RAISE EXCEPTION 'El cliente % no tiene un subtipo definido', p_cliente;
END;
$$;

-- Calcula la antigüedad laboral de un empleado en años.
CREATE OR REPLACE FUNCTION fn_antiguedad_anios(p_cuit dom_cuit)
RETURNS integer
LANGUAGE sql
STABLE
AS $$
    SELECT COALESCE(
        EXTRACT(YEAR FROM age(CURRENT_DATE, fechaIngresoLaboral))::integer,
        0
    )
    FROM empleado
    WHERE cuit = p_cuit;
$$;
