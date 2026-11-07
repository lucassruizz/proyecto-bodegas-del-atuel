-- BODEGAS DEL ATUEL
-- db_tests.sql

BEGIN;

-- 1. Datos base para las pruebas.
INSERT INTO localidad (nombre, provincia, codigoPostal)
VALUES ('San Rafael', 'Mendoza', '5600');

-- Encargado para cumplir con RN-02 (cada localidad tiene un encargado)
INSERT INTO encargado_regional (datosEncargado, idLocalidad)
VALUES ('Encargado principal', 1);

INSERT INTO sala_venta (calle, numero, diaCierreSemanal, idLocalidad)
VALUES ('Av. Mitre', '100', 'lunes', 1);

INSERT INTO bodega (cuit, razonSocial, domicilio)
VALUES ('20111111111', 'Bodega de prueba', 'Ruta 143');

INSERT INTO deposito (idDeposito) VALUES (1);

INSERT INTO cepa (nombre, tipo) VALUES ('Malbec', 'tinta');

INSERT INTO departamento (nombreDepartamento, provincia)
VALUES ('San Rafael', 'Mendoza');

INSERT INTO finca (nombre, superficieTotal, idDepartamento)
VALUES ('Finca de prueba', 20, 1);

INSERT INTO parcela (idFinca, numeroParcela, superficie, anioPlantacion, idCepa)
VALUES (1, 1, 10, 2010, 1);

INSERT INTO vino (
    codigoVino, nombre, volumen, graduacionAlcoholica, tipo, anada, precio, cuitBodega
) VALUES (1, 'Malbec joven', 750, 13, 'tinto', 2024, 1000, '20111111111');

-- 2. PRUEBAS RN-01: Precio positivo y unicidad de vino.
-- Prueba de precio positivo. Debería fallar.
DO $$
DECLARE
    v_fallo boolean := false;
BEGIN
    BEGIN
        INSERT INTO vino (
            codigoVino, nombre, volumen, graduacionAlcoholica, tipo, anada, precio, cuitBodega
        ) VALUES (2, 'Vino invalido', 375, 12, 'tinto', 2024, 0, '20111111111');
    EXCEPTION WHEN check_violation THEN
        v_fallo := true;
    END;

    IF NOT v_fallo THEN
        RAISE EXCEPTION 'La prueba RN-01 (precio positivo) no falló';
    END IF;
    RAISE NOTICE 'RN-01 OK: no acepta precio cero';
END;
$$;

-- Prueba de unicidad del vino (mismo nombre, añada y volumen). Debería fallar.
DO $$
DECLARE
    v_fallo boolean := false;
BEGIN
    BEGIN
        INSERT INTO vino (
            codigoVino, nombre, volumen, graduacionAlcoholica, tipo, anada, precio, cuitBodega
        ) VALUES (3, 'Malbec joven', 750, 14, 'tinto', 2024, 1200, '20111111111');
    EXCEPTION WHEN unique_violation THEN
        v_fallo := true;
    END;

    IF NOT v_fallo THEN
        RAISE EXCEPTION 'La prueba RN-01 (unicidad) no falló';
    END IF;
    RAISE NOTICE 'RN-01 OK: no acepta vinos duplicados (nombre, añada, volumen)';
END;
$$;

-- 3. PRUEBAS RN-02: Encargado regional y localidad.
-- Prueba de una localidad que intenta tener un segundo encargado regional. Debería fallar.
DO $$
DECLARE
    v_fallo boolean := false;
BEGIN
    BEGIN
        INSERT INTO encargado_regional (datosEncargado, idLocalidad)
        VALUES ('Encargado dos', 1);
    EXCEPTION WHEN unique_violation THEN
        v_fallo := true;
    END;

    IF NOT v_fallo THEN
        RAISE EXCEPTION 'La prueba RN-02 (unicidad de encargado) no falló';
    END IF;
    RAISE NOTICE 'RN-02 OK: un solo encargado por localidad';
END;
$$;

-- Prueba de existencia obligatoria de encargado por localidad (control diferido). Debería fallar.
DO $$
DECLARE
    v_fallo boolean := false;
BEGIN
    INSERT INTO localidad (nombre, provincia, codigoPostal)
    VALUES ('Malargue', 'Mendoza', '5613');

    BEGIN
        SET CONSTRAINTS trg_localidad_encargado IMMEDIATE;
    EXCEPTION WHEN raise_exception THEN
        v_fallo := true;
    END;

    IF NOT v_fallo THEN
        RAISE EXCEPTION 'La prueba RN-02 (existencia obligatoria de encargado) no falló';
    END IF;

    DELETE FROM localidad WHERE nombre = 'Malargue';
    SET CONSTRAINTS ALL DEFERRED;
    RAISE NOTICE 'RN-02 OK: toda localidad debe tener un encargado regional';
END;
$$;

-- 4. PRUEBA RN-03: Un empleado debe tener sala asignada obligatoriamente.
DO $$
DECLARE
    v_fallo boolean := false;
BEGIN
    BEGIN
        INSERT INTO empleado (cuit, nombre, fechaIngresoLaboral, salario, idSalaVenta)
        VALUES ('20222222222', 'Empleado sin sala', CURRENT_DATE, 1000, NULL);
    EXCEPTION WHEN not_null_violation THEN
        v_fallo := true;
    END;

    IF NOT v_fallo THEN
        RAISE EXCEPTION 'La prueba RN-03 no falló';
    END IF;
    RAISE NOTICE 'RN-03 OK: empleado con sala obligatoria';
END;
$$;

-- 5. PRUEBA RN-04: Misma parcela y campaña. Debería fallar.
INSERT INTO lote (
    numero, fechaCosecha, kilosCosechados, campania, idFinca, numeroParcela, cuitBodega
) VALUES (1, CURRENT_DATE, 1000, 2025, 1, 1, '20111111111');

DO $$
DECLARE
    v_fallo boolean := false;
BEGIN
    BEGIN
        INSERT INTO lote (
            numero, fechaCosecha, kilosCosechados, campania, idFinca, numeroParcela, cuitBodega
        ) VALUES (2, CURRENT_DATE, 900, 2025, 1, 1, '20111111111');
    EXCEPTION WHEN unique_violation THEN
        v_fallo := true;
    END;

    IF NOT v_fallo THEN
        RAISE EXCEPTION 'La prueba RN-04 no falló';
    END IF;
    RAISE NOTICE 'RN-04 OK: una cosecha por parcela y campaña';
END;
$$;

-- 6. PRUEBAS RN-05: Composición del vino igual a 100%.
-- Composición válida al 100%. Debería funcionar.
INSERT INTO componen (codigoVino, idCepa, porcentaje) VALUES (1, 1, 100);
SET CONSTRAINTS trg_componen_porcentaje IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;
DO $$ BEGIN RAISE NOTICE 'RN-05 OK: composición al 100%% aceptada'; END $$;

-- Composición que no suma 100%. Debería fallar.
DO $$
DECLARE
    v_fallo boolean := false;
BEGIN
    INSERT INTO cepa (nombre, tipo) VALUES ('Cabernet Sauvignon', 'tinta');
    INSERT INTO vino (
        codigoVino, nombre, volumen, graduacionAlcoholica, tipo, anada, precio, cuitBodega
    ) VALUES (20, 'Vino corte incompleto', 750, 13.5, 'tinto', 2024, 1500, '20111111111');

    INSERT INTO componen (codigoVino, idCepa, porcentaje)
    VALUES (20, (SELECT idCepa FROM cepa WHERE nombre = 'Cabernet Sauvignon'), 80);

    BEGIN
        SET CONSTRAINTS trg_componen_porcentaje IMMEDIATE;
    EXCEPTION WHEN raise_exception THEN
        v_fallo := true;
    END;

    IF NOT v_fallo THEN
        RAISE EXCEPTION 'La prueba RN-05 (composición <> 100) no falló';
    END IF;

    DELETE FROM componen WHERE codigoVino = 20;
    DELETE FROM vino WHERE codigoVino = 20;
    DELETE FROM cepa WHERE nombre = 'Cabernet Sauvignon';
    SET CONSTRAINTS ALL DEFERRED;
    RAISE NOTICE 'RN-05 OK: rechaza composición que no sume 100%%';
END;
$$;

-- 7. PRUEBAS RN-06: los tres descuentos, disjunción y coherencia diferida.
INSERT INTO cliente (
    apellido, nombre, tipoDocumento, numeroDocumento, direccion, idLocalidad, descuento
) VALUES
    ('Perez', 'Ana', 'DNI', '30000000', 'Calle 1', 1, 30),
    ('Lopez', 'Luis', 'DNI', '30000001', 'Calle 2', 1, 10),
    ('Gomez', 'Marta', 'DNI', '30000002', 'Calle 3', 1, 20);

INSERT INTO exportador (idCliente, paisDestinoPrincipal)
VALUES (1, 'Chile');
INSERT INTO socio_club (idCliente) VALUES (2);
INSERT INTO distribuidor (idCliente, zonaCobertura, numeroHabilitacion)
VALUES (3, 'Zona Cuyo', 'HAB-300');

DO $$
BEGIN
    IF fn_descuento_cliente(1) <> 30
       OR fn_descuento_cliente(2) <> 10
       OR fn_descuento_cliente(3) <> 20 THEN
        RAISE EXCEPTION 'RN-06: los descuentos 10%%, 20%% y 30%% no coinciden con los subtipos';
    END IF;
    RAISE NOTICE 'RN-06 OK: socio 10%%, distribuidor 20%% y exportador 30%%';
END;
$$;

-- Un cliente no puede pertenecer simultáneamente a dos subtipos.
DO $$
DECLARE v_fallo boolean := false;
BEGIN
    BEGIN
        INSERT INTO distribuidor (idCliente, zonaCobertura, numeroHabilitacion)
        VALUES (1, 'Zona Cuyo', 'HAB-1234');
        SET CONSTRAINTS trg_distribuidor_subtipo_integridad IMMEDIATE;
    EXCEPTION WHEN raise_exception THEN
        v_fallo := true;
    END;
    SET CONSTRAINTS ALL DEFERRED;
    IF NOT v_fallo THEN
        RAISE EXCEPTION 'RN-06: permitió dos subtipos para el mismo cliente';
    END IF;
    RAISE NOTICE 'RN-06 OK: especialización disjunta';
END;
$$;

-- Cambiar el descuento después de asignar el subtipo debe fallar al validar la restricción diferida.
DO $$
DECLARE v_fallo boolean := false;
BEGIN
    BEGIN
        UPDATE cliente SET descuento = 20 WHERE idCliente = 2;
        SET CONSTRAINTS trg_cliente_subtipo_integridad IMMEDIATE;
    EXCEPTION WHEN raise_exception THEN
        v_fallo := true;
    END;
    SET CONSTRAINTS ALL DEFERRED;
    IF NOT v_fallo THEN
        RAISE EXCEPTION 'RN-06: permitió cambiar el descuento de un socio a 20%%';
    END IF;
    RAISE NOTICE 'RN-06 OK: descuento no puede contradecir el subtipo';
END;
$$;

-- Eliminar el subtipo tampoco puede dejar un cliente sin especialización.
DO $$
DECLARE v_fallo boolean := false;
BEGIN
    BEGIN
        DELETE FROM exportador WHERE idCliente = 1;
        SET CONSTRAINTS trg_exportador_subtipo_integridad IMMEDIATE;
    EXCEPTION WHEN raise_exception THEN
        v_fallo := true;
    END;
    SET CONSTRAINTS ALL DEFERRED;
    IF NOT v_fallo THEN
        RAISE EXCEPTION 'RN-06: permitió eliminar el único subtipo del cliente';
    END IF;
    RAISE NOTICE 'RN-06 OK: no permite eliminar el único subtipo';
END;
$$;

-- Descuento inicial incompatible con el subtipo: debe fallar al validar la restricción.
DO $$
DECLARE v_id bigint; v_fallo boolean := false;
BEGIN
    BEGIN
        INSERT INTO cliente (
            apellido, nombre, tipoDocumento, numeroDocumento, direccion, idLocalidad, descuento
        ) VALUES ('Diaz', 'Juan', 'DNI', '31000000', 'Calle 4', 1, 10)
        RETURNING idCliente INTO v_id;
        INSERT INTO distribuidor (idCliente, zonaCobertura, numeroHabilitacion)
        VALUES (v_id, 'Zona Norte', 'HAB-5678');
        SET CONSTRAINTS trg_cliente_subtipo_integridad IMMEDIATE;
    EXCEPTION WHEN raise_exception THEN
        v_fallo := true;
    END;
    SET CONSTRAINTS ALL DEFERRED;
    IF NOT v_fallo THEN
        RAISE EXCEPTION 'RN-06: aceptó distribuidor con descuento 10%%';
    END IF;
    RAISE NOTICE 'RN-06 OK: descuento inicial incompatible rechazado';
END;
$$;

-- 8. PRUEBA RN-07: Vencimiento posterior a emisión en permisos. Debería fallar.
DO $$
DECLARE
    v_fallo boolean := false;
BEGIN
    BEGIN
        INSERT INTO permisos (codigo, fechaEmision, fechaVencimiento, idExportador)
        VALUES ('PERM-1', DATE '2025-01-10', DATE '2025-01-10', 1);
    EXCEPTION WHEN check_violation THEN
        v_fallo := true;
    END;

    IF NOT v_fallo THEN
        RAISE EXCEPTION 'La prueba RN-07 no falló';
    END IF;
    RAISE NOTICE 'RN-07 OK: vencimiento posterior a emisión';
END;
$$;

-- 9. PRUEBAS RN-08 y RN-09: Control de stock e importes en INSERT, UPDATE y DELETE.
INSERT INTO posee (idSalaVenta, codigoVino, cantidadStock) VALUES (1, 1, 2);

INSERT INTO comprobante (numero, fecha, idCliente, idSalaVenta, subtotal, descuento, total)
VALUES (1, CURRENT_DATE, 1, 1, 0, 0, 0);

-- Intento de vender más stock del disponible en INSERT (3 > 2). Debería fallar.
DO $$
DECLARE
    v_fallo boolean := false;
BEGIN
    BEGIN
        INSERT INTO renglon_comprobante (
            numeroComprobante, codigoVino, cantidad, precioUnitario, descuento, subtotalRenglon
        ) VALUES (1, 1, 3, 1000, 0, 0);
    EXCEPTION WHEN raise_exception THEN
        v_fallo := true;
    END;

    IF NOT v_fallo THEN
        RAISE EXCEPTION 'La prueba RN-09 no falló en INSERT';
    END IF;
    RAISE NOTICE 'RN-09 OK: venta rechazada por stock insuficiente en INSERT';
END;
$$;

-- Venta válida de 1 botella en INSERT: descuenta stock (2 - 1 = 1) y actualiza importes (total = 700).
INSERT INTO renglon_comprobante (
    numeroComprobante, codigoVino, cantidad, precioUnitario, descuento, subtotalRenglon
) VALUES (1, 1, 1, 1000, 0, 0);

DO $$
BEGIN
    IF (SELECT cantidadStock FROM posee WHERE idSalaVenta = 1 AND codigoVino = 1) <> 1
       OR (SELECT total FROM comprobante WHERE numero = 1) <> 700 THEN
        RAISE EXCEPTION 'La prueba RN-08/RN-09 no actualizó correctamente en INSERT';
    END IF;
    RAISE NOTICE 'RN-08 y RN-09 OK: total y stock actualizados en INSERT';
END;
$$;

-- Intento de UPDATE de cantidad superior al stock disponible (pedir 5 cuando queda 1 en posee + 1 del renglón = 2 máx). Debería fallar.
DO $$
DECLARE
    v_fallo boolean := false;
BEGIN
    BEGIN
        UPDATE renglon_comprobante
           SET cantidad = 5
         WHERE numeroComprobante = 1 AND codigoVino = 1;
    EXCEPTION WHEN raise_exception THEN
        v_fallo := true;
    END;

    IF NOT v_fallo THEN
        RAISE EXCEPTION 'La prueba RN-09 no falló en UPDATE';
    END IF;
    RAISE NOTICE 'RN-09 OK: venta rechazada por stock insuficiente en UPDATE';
END;
$$;

-- UPDATE válido de cantidad a 2 botellas: stock pasa a 0 y total pasa a 1400.
UPDATE renglon_comprobante
   SET cantidad = 2
 WHERE numeroComprobante = 1 AND codigoVino = 1;

DO $$
BEGIN
    IF (SELECT cantidadStock FROM posee WHERE idSalaVenta = 1 AND codigoVino = 1) <> 0
       OR (SELECT total FROM comprobante WHERE numero = 1) <> 1400 THEN
        RAISE EXCEPTION 'La prueba RN-08/RN-09 no actualizó correctamente en UPDATE';
    END IF;
    RAISE NOTICE 'RN-08 y RN-09 OK: total y stock actualizados en UPDATE';
END;
$$;

-- DELETE de renglón: restaura stock a 2 y reinicia importes a 0.
DELETE FROM renglon_comprobante
 WHERE numeroComprobante = 1 AND codigoVino = 1;

DO $$
BEGIN
    IF (SELECT cantidadStock FROM posee WHERE idSalaVenta = 1 AND codigoVino = 1) <> 2
       OR (SELECT total FROM comprobante WHERE numero = 1) <> 0 THEN
        RAISE EXCEPTION 'La prueba RN-08/RN-09 no restauró stock e importes en DELETE';
    END IF;
    RAISE NOTICE 'RN-08 y RN-09 OK: total y stock restaurados en DELETE';
END;
$$;

-- Reasentamos 1 renglón válido para que el comprobante y el vino tengan operaciones asociadas.
INSERT INTO renglon_comprobante (
    numeroComprobante, codigoVino, cantidad, precioUnitario, descuento, subtotalRenglon
) VALUES (1, 1, 1, 1000, 0, 0);

-- Casos adicionales RN-09: cambiar el vino y cambiar el comprobante.
-- Se usa un segundo vino para verificar que se restaura el stock anterior.
INSERT INTO vino (
    codigoVino, nombre, volumen, graduacionAlcoholica, tipo, anada, precio, cuitBodega
) VALUES (2, 'Cabernet de prueba', 750, 13, 'tinto', 2024, 1000, '20111111111');
INSERT INTO componen (codigoVino, idCepa, porcentaje) VALUES (2, 1, 100);
SET CONSTRAINTS trg_componen_porcentaje IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;
INSERT INTO posee (idSalaVenta, codigoVino, cantidadStock) VALUES (1, 2, 2);
INSERT INTO comprobante (numero, fecha, idCliente, idSalaVenta, subtotal, descuento, total)
VALUES (2, CURRENT_DATE, 1, 1, 0, 0, 0);

-- Cambiar el vino restaura el stock del vino anterior y consume el nuevo.
UPDATE renglon_comprobante
   SET codigoVino = 2
 WHERE numeroComprobante = 1 AND codigoVino = 1;
DO $$ BEGIN
    IF (SELECT cantidadStock FROM posee WHERE idSalaVenta = 1 AND codigoVino = 1) <> 2
       OR (SELECT cantidadStock FROM posee WHERE idSalaVenta = 1 AND codigoVino = 2) <> 1 THEN
        RAISE EXCEPTION 'RN-09: no restauró/consumió stock al cambiar el vino';
    END IF;
END $$;

-- Se agota el stock del segundo vino. Mover el renglón a otro comprobante
-- de la misma sala debe poder usar la cantidad que libera el renglón anterior.
UPDATE renglon_comprobante SET cantidad = 2
 WHERE numeroComprobante = 1 AND codigoVino = 2;
UPDATE renglon_comprobante SET numeroComprobante = 2
 WHERE numeroComprobante = 1 AND codigoVino = 2;
DO $$ BEGIN
    IF (SELECT cantidadStock FROM posee WHERE idSalaVenta = 1 AND codigoVino = 2) <> 0
       OR (SELECT total FROM comprobante WHERE numero = 1) <> 0
       OR (SELECT total FROM comprobante WHERE numero = 2) <> 1400 THEN
        RAISE EXCEPTION 'RN-09/RN-08: traslado entre comprobantes incorrecto';
    END IF;
END $$;

-- Se devuelve el renglón a su estado inicial para que las pruebas siguientes
-- mantengan los valores de stock esperados.
UPDATE renglon_comprobante SET codigoVino = 1
 WHERE numeroComprobante = 2 AND codigoVino = 2;
UPDATE renglon_comprobante SET numeroComprobante = 1
 WHERE numeroComprobante = 2 AND codigoVino = 1;
UPDATE renglon_comprobante SET cantidad = 1
 WHERE numeroComprobante = 1 AND codigoVino = 1;

-- 10. PRUEBAS RN-10, RN-11 y RN-12: Ingresos y Transferencias.
INSERT INTO empresas_transporte (
    codigoTransporte, razonSocial, cuit, email, telefono, domicilio
) VALUES (1, 'Transporte prueba', '20333333333', 'transporte@prueba.com', '2604000000', 'Calle 2');

INSERT INTO alcanza (codigoTransporte, idLocalidad) VALUES (1, 1);

INSERT INTO ingresos (codigoIngreso, cuitBodega, codigoTransporte, idDeposito)
VALUES (1, '20111111111', 1, 1);

INSERT INTO contiene (codigoIngreso, codigoVino, cantidadBotellas)
VALUES (1, 1, 10);

UPDATE ingresos SET estado = 'terminado' WHERE codigoIngreso = 1;

-- RN-12: Intento de INSERT en ingreso ya terminado. Debería fallar.
DO $$
DECLARE
    v_fallo boolean := false;
BEGIN
    BEGIN
        INSERT INTO contiene (codigoIngreso, codigoVino, cantidadBotellas)
        VALUES (1, 1, 1);
    EXCEPTION WHEN raise_exception THEN
        v_fallo := true;
    END;

    IF NOT v_fallo THEN
        RAISE EXCEPTION 'La prueba RN-12 no falló en INSERT';
    END IF;
    RAISE NOTICE 'RN-12 OK: renglón bloqueado en INSERT fuera de confección';
END;
$$;

-- RN-12: Intento de UPDATE en ingreso ya terminado. Debería fallar.
DO $$
DECLARE
    v_fallo boolean := false;
BEGIN
    BEGIN
        UPDATE contiene
           SET cantidadBotellas = 25
         WHERE codigoIngreso = 1 AND codigoVino = 1;
    EXCEPTION WHEN raise_exception THEN
        v_fallo := true;
    END;

    IF NOT v_fallo THEN
        RAISE EXCEPTION 'La prueba RN-12 no falló en UPDATE';
    END IF;
    RAISE NOTICE 'RN-12 OK: renglón bloqueado en UPDATE fuera de confección';
END;
$$;

-- RN-12: Intento de DELETE en ingreso ya terminado. Debería fallar.
DO $$
DECLARE
    v_fallo boolean := false;
BEGIN
    BEGIN
        DELETE FROM contiene
         WHERE codigoIngreso = 1 AND codigoVino = 1;
    EXCEPTION WHEN raise_exception THEN
        v_fallo := true;
    END;

    IF NOT v_fallo THEN
        RAISE EXCEPTION 'La prueba RN-12 no falló en DELETE';
    END IF;
    RAISE NOTICE 'RN-12 OK: renglón bloqueado en DELETE fuera de confección';
END;
$$;

-- RN-10: Procesar ingreso terminado.
CALL sp_procesar_ingreso(1);
DO $$
BEGIN
    IF (SELECT estado FROM ingresos WHERE codigoIngreso = 1) <> 'procesado'
       OR (SELECT cantidadStock FROM almacena WHERE codigoVino = 1) <> 10 THEN
        RAISE EXCEPTION 'La prueba RN-10 no procesó el ingreso';
    END IF;
    RAISE NOTICE 'RN-10 OK: ingreso procesado y stock incorporado al depósito';
END;
$$;

-- RN-11: Transferencia de depósito a sala de venta.
INSERT INTO transferencia (numeroSolicitud, idSalaVenta)
VALUES (1, 1);

INSERT INTO incluye (numeroSolicitud, codigoVino, cantidad)
VALUES (1, 1, 2);

UPDATE transferencia SET estado = 'terminado' WHERE numeroSolicitud = 1;

CALL sp_procesar_transferencia(1);
DO $$
BEGIN
    IF (SELECT estado FROM transferencia WHERE numeroSolicitud = 1) <> 'procesado'
       OR (SELECT cantidadStock FROM almacena WHERE codigoVino = 1) <> 8
       OR (SELECT cantidadStock FROM posee WHERE idSalaVenta = 1 AND codigoVino = 1) <> 3 THEN
        RAISE EXCEPTION 'La prueba RN-11 no procesó la transferencia';
    END IF;
    RAISE NOTICE 'RN-11 OK: transferencia procesada y stock transferido a sala';
END;
$$;

-- RN-12: Los renglones de una transferencia terminada tampoco se pueden
-- insertar, modificar ni eliminar.
INSERT INTO transferencia (numeroSolicitud, idSalaVenta)
VALUES (3, 1);

INSERT INTO incluye (numeroSolicitud, codigoVino, cantidad)
VALUES (3, 1, 1);

UPDATE transferencia
   SET estado = 'terminado'
 WHERE numeroSolicitud = 3;

-- Intento de INSERT en transferencia terminada. Debería fallar.
DO $$
DECLARE
    v_fallo boolean := false;
BEGIN
    BEGIN
        INSERT INTO incluye (numeroSolicitud, codigoVino, cantidad)
        VALUES (3, 1, 1);
    EXCEPTION WHEN raise_exception THEN
        v_fallo := true;
    END;

    IF NOT v_fallo THEN
        RAISE EXCEPTION 'La prueba RN-12 no falló en INSERT de transferencia';
    END IF;
    RAISE NOTICE 'RN-12 OK: renglón de transferencia bloqueado en INSERT fuera de confección';
END;
$$;

-- Intento de UPDATE en transferencia terminada. Debería fallar.
DO $$
DECLARE
    v_fallo boolean := false;
BEGIN
    BEGIN
        UPDATE incluye
           SET cantidad = 2
         WHERE numeroSolicitud = 3 AND codigoVino = 1;
    EXCEPTION WHEN raise_exception THEN
        v_fallo := true;
    END;

    IF NOT v_fallo THEN
        RAISE EXCEPTION 'La prueba RN-12 no falló en UPDATE de transferencia';
    END IF;
    RAISE NOTICE 'RN-12 OK: renglón de transferencia bloqueado en UPDATE fuera de confección';
END;
$$;

-- Intento de DELETE en transferencia terminada. Debería fallar.
DO $$
DECLARE
    v_fallo boolean := false;
BEGIN
    BEGIN
        DELETE FROM incluye
         WHERE numeroSolicitud = 3 AND codigoVino = 1;
    EXCEPTION WHEN raise_exception THEN
        v_fallo := true;
    END;

    IF NOT v_fallo THEN
        RAISE EXCEPTION 'La prueba RN-12 no falló en DELETE de transferencia';
    END IF;
    RAISE NOTICE 'RN-12 OK: renglón de transferencia bloqueado en DELETE fuera de confección';
END;
$$;

-- 11. PRUEBAS RN-14: Protección contra borrado por claves foráneas (RESTRICT).
-- Intento de borrar bodega con referencias. Debería fallar.
DO $$
DECLARE
    v_fallo boolean := false;
BEGIN
    BEGIN
        DELETE FROM bodega WHERE cuit = '20111111111';
    EXCEPTION WHEN foreign_key_violation THEN
        v_fallo := true;
    END;

    IF NOT v_fallo THEN
        RAISE EXCEPTION 'La prueba RN-14 (bodega) no falló';
    END IF;
    RAISE NOTICE 'RN-14 OK: borrado de bodega protegido por FK RESTRICT';
END;
$$;

-- Intento de borrar vino con referencias (posee, comprobante, almacena). Debería fallar.
DO $$
DECLARE
    v_fallo boolean := false;
BEGIN
    BEGIN
        DELETE FROM vino WHERE codigoVino = 1;
    EXCEPTION WHEN foreign_key_violation THEN
        v_fallo := true;
    END;

    IF NOT v_fallo THEN
        RAISE EXCEPTION 'La prueba RN-14 (vino) no falló';
    END IF;
    RAISE NOTICE 'RN-14 OK: borrado de vino protegido por FK RESTRICT';
END;
$$;

-- Intento de borrar empresa de transporte con referencias (ingresos, alcanza). Debería fallar.
DO $$
DECLARE
    v_fallo boolean := false;
BEGIN
    BEGIN
        DELETE FROM empresas_transporte WHERE codigoTransporte = 1;
    EXCEPTION WHEN foreign_key_violation THEN
        v_fallo := true;
    END;

    IF NOT v_fallo THEN
        RAISE EXCEPTION 'La prueba RN-14 (transporte) no falló';
    END IF;
    RAISE NOTICE 'RN-14 OK: borrado de transportista protegido por FK RESTRICT';
END;
$$;

-- 12. PRUEBAS RN-15: cantidades, superficies, kilos y precios positivos;
-- graduación alcohólica entre 5 y 20. Cada INSERT inválido debe fallar por CHECK.

-- Superficie de finca igual a cero.
DO $$ DECLARE v_fallo boolean := false; BEGIN
    BEGIN
        INSERT INTO finca (nombre, superficieTotal, idDepartamento)
        VALUES ('Finca superficie cero', 0, 1);
    EXCEPTION WHEN check_violation THEN v_fallo := true; END;
    IF NOT v_fallo THEN RAISE EXCEPTION 'RN-15: aceptó superficie de finca cero'; END IF;
END $$;

-- Superficie de parcela negativa.
DO $$ DECLARE v_fallo boolean := false; BEGIN
    BEGIN
        INSERT INTO parcela (idFinca, numeroParcela, superficie, anioPlantacion, idCepa)
        VALUES (1, 2, -1, 2015, 1);
    EXCEPTION WHEN check_violation THEN v_fallo := true; END;
    IF NOT v_fallo THEN RAISE EXCEPTION 'RN-15: aceptó superficie de parcela negativa'; END IF;
END $$;

-- Kilos cosechados iguales a cero.
DO $$ DECLARE v_fallo boolean := false; BEGIN
    BEGIN
        INSERT INTO lote (numero, fechaCosecha, kilosCosechados, campania, idFinca, numeroParcela, cuitBodega)
        VALUES (3, CURRENT_DATE, 0, 2026, 1, 1, '20111111111');
    EXCEPTION WHEN check_violation THEN v_fallo := true; END;
    IF NOT v_fallo THEN RAISE EXCEPTION 'RN-15: aceptó kilos cosechados cero'; END IF;
END $$;

-- Cantidad de botellas de un ingreso negativa (ingreso de prueba aún en confección).
INSERT INTO ingresos (codigoIngreso, cuitBodega, codigoTransporte, idDeposito)
VALUES (2, '20111111111', 1, 1);
DO $$ DECLARE v_fallo boolean := false; BEGIN
    BEGIN
        INSERT INTO contiene (codigoIngreso, codigoVino, cantidadBotellas)
        VALUES (2, 1, -1);
    EXCEPTION WHEN check_violation THEN v_fallo := true; END;
    IF NOT v_fallo THEN RAISE EXCEPTION 'RN-15: aceptó cantidad de botellas negativa'; END IF;
END $$;

-- Cantidad solicitada en transferencia igual a cero.
INSERT INTO transferencia (numeroSolicitud, idSalaVenta) VALUES (2, 1);
DO $$ DECLARE v_fallo boolean := false; BEGIN
    BEGIN
        INSERT INTO incluye (numeroSolicitud, codigoVino, cantidad)
        VALUES (2, 1, 0);
    EXCEPTION WHEN check_violation THEN v_fallo := true; END;
    IF NOT v_fallo THEN RAISE EXCEPTION 'RN-15: aceptó cantidad de transferencia cero'; END IF;
END $$;

-- Cantidad vendida negativa.
DO $$ DECLARE v_fallo boolean := false; BEGIN
    BEGIN
        INSERT INTO renglon_comprobante
            (numeroComprobante, codigoVino, cantidad, precioUnitario, descuento, subtotalRenglon)
        VALUES (1, 1, -1, 1000, 0, 0);
    EXCEPTION WHEN check_violation THEN v_fallo := true; END;
    IF NOT v_fallo THEN RAISE EXCEPTION 'RN-15: aceptó cantidad vendida negativa'; END IF;
END $$;

-- Precio unitario de venta igual a cero.
DO $$ DECLARE v_fallo boolean := false; BEGIN
    BEGIN
        INSERT INTO renglon_comprobante
            (numeroComprobante, codigoVino, cantidad, precioUnitario, descuento, subtotalRenglon)
        VALUES (1, 1, 1, 0, 0, 0);
    EXCEPTION WHEN check_violation THEN v_fallo := true; END;
    IF NOT v_fallo THEN RAISE EXCEPTION 'RN-15: aceptó precio unitario cero'; END IF;
END $$;

-- Volumen de presentación igual a cero.
DO $$ DECLARE v_fallo boolean := false; BEGIN
    BEGIN
        INSERT INTO vino
            (codigoVino, nombre, volumen, graduacionAlcoholica, tipo, anada, precio, cuitBodega)
        VALUES (7, 'Vino volumen cero', 0, 12, 'tinto', 2024, 1000, '20111111111');
    EXCEPTION WHEN check_violation THEN v_fallo := true; END;
    IF NOT v_fallo THEN RAISE EXCEPTION 'RN-15: aceptó volumen cero'; END IF;
END $$;

-- Precio del vino igual a cero.
DO $$ DECLARE v_fallo boolean := false; BEGIN
    BEGIN
        INSERT INTO vino
            (codigoVino, nombre, volumen, graduacionAlcoholica, tipo, anada, precio, cuitBodega)
        VALUES (5, 'Vino precio cero', 750, 12, 'tinto', 2024, 0, '20111111111');
    EXCEPTION WHEN check_violation THEN v_fallo := true; END;
    IF NOT v_fallo THEN RAISE EXCEPTION 'RN-15: aceptó precio de vino cero'; END IF;
END $$;

-- Graduación alcohólica fuera del rango permitido (> 20).
DO $$ DECLARE v_fallo boolean := false; BEGIN
    BEGIN
        INSERT INTO vino
            (codigoVino, nombre, volumen, graduacionAlcoholica, tipo, anada, precio, cuitBodega)
        VALUES (6, 'Vino hiperalcoholico', 750, 25, 'tinto', 2024, 1000, '20111111111');
    EXCEPTION WHEN check_violation THEN v_fallo := true; END;
    IF NOT v_fallo THEN RAISE EXCEPTION 'RN-15: aceptó graduación alcohólica mayor a 20'; END IF;
END $$;


-- Graduación alcohólica fuera del rango permitido (< 5).
DO $$ DECLARE v_fallo boolean := false; BEGIN
    BEGIN
        INSERT INTO vino
            (codigoVino, nombre, volumen, graduacionAlcoholica, tipo, anada, precio, cuitBodega)
        VALUES (8, 'Vino baja graduacion', 750, 4, 'tinto', 2024, 1000, '20111111111');
    EXCEPTION WHEN check_violation THEN v_fallo := true; END;
    IF NOT v_fallo THEN RAISE EXCEPTION 'RN-15: aceptó graduación alcohólica menor a 5'; END IF;
END $$;

DO $$ BEGIN
    RAISE NOTICE 'RN-15 OK: probadas superficies, kilos, cantidades, precios y graduación menor y mayor al rango';
END $$;

-- 13. PRUEBA RN-13: Auditoría automática en cambio de precio.
UPDATE vino SET precio = 1100 WHERE codigoVino = 1;
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM auditoria_precio WHERE codigoVino = 1 AND precioNuevo = 1100) THEN
        RAISE EXCEPTION 'La prueba RN-13 no generó auditoría';
    END IF;
    RAISE NOTICE 'RN-13 OK: precio auditado automáticamente';
END;
$$;

ROLLBACK;
