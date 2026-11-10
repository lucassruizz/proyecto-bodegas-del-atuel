BEGIN;

-- El rol de la API conserva solo lectura sobre auditoría. El trigger escribe con los permisos de su dueño y registra el usuario real de la conexión.
CREATE OR REPLACE FUNCTION public.fn_auditar_precio_vino()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    IF NEW.precio IS DISTINCT FROM OLD.precio THEN
        INSERT INTO public.auditoria_precio (
            codigoVino, precioAnterior, precioNuevo, fechaHora, usuario
        )
        VALUES (
            NEW.codigoVino, OLD.precio, NEW.precio, CURRENT_TIMESTAMP, SESSION_USER
        );
    END IF;

    RETURN NEW;
END;
$$;

-- Un vino eliminado no necesita conservar composición. 
CREATE OR REPLACE FUNCTION public.fn_validar_porcentaje_corte()
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
        IF v_total <> 100 AND EXISTS (SELECT 1 FROM public.vino WHERE codigoVino = v_vino_old) THEN
            RAISE EXCEPTION
                'RN-05: los porcentajes del vino % deben sumar 100 (suma actual: %)',
                v_vino_old, v_total;
        END IF;
    END IF;

    IF TG_OP <> 'DELETE' THEN
        v_vino_new := NEW.codigoVino;
        IF TG_OP <> 'UPDATE' OR v_vino_new IS DISTINCT FROM v_vino_old THEN
            SELECT COALESCE(SUM(porcentaje), 0)
              INTO v_total
              FROM componen
             WHERE codigoVino = v_vino_new;
            IF v_total <> 100 AND EXISTS (SELECT 1 FROM public.vino WHERE codigoVino = v_vino_new) THEN
                RAISE EXCEPTION
                    'RN-05: los porcentajes del vino % deben sumar 100 (suma actual: %)',
                    v_vino_new, v_total;
            END IF;
        END IF;
    END IF;

    RETURN NULL;
END;
$$;

COMMIT;
