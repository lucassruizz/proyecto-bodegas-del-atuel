BEGIN;
DO $$
BEGIN
    IF current_database() <> 'bodegas_etapa5_pruebas' THEN
        RAISE EXCEPTION 'Usar la copia desechable bodegas_etapa5_pruebas';
    END IF;
END
$$;

DELETE FROM alcanza a USING localidad l
WHERE a.idLocalidad = l.idLocalidad AND a.codigoTransporte = 1
  AND l.nombre = 'General Alvear' AND l.provincia = 'Mendoza';

UPDATE comprobante SET fecha = (CURRENT_DATE - INTERVAL '6 years')::date, total = 0
WHERE numero = 1 AND idCliente IN (SELECT idCliente FROM socio_club);

INSERT INTO cepa (nombre, tipo) VALUES ('Cepa de prueba etapa 5', 'tinta');

UPDATE empleado SET fechaIngresoLaboral = (CURRENT_DATE - INTERVAL '1 year')::date
WHERE cuit = '20000000001' AND idSalaVenta = 2;

WITH nuevo AS (
    INSERT INTO cliente (nombre, apellido, tipoDocumento, numeroDocumento,
                         direccion, idLocalidad, fechaAlta, descuento)
    SELECT 'Socio', 'Prueba etapa 5', 'DNI', '99000001', 'Domicilio de prueba',
           idLocalidad, (CURRENT_DATE - INTERVAL '6 years')::date, 10
    FROM localidad WHERE nombre = 'San Rafael' AND provincia = 'Mendoza'
    RETURNING idCliente
)
INSERT INTO socio_club (idCliente) SELECT idCliente FROM nuevo;
SET CONSTRAINTS ALL IMMEDIATE;
COMMIT;
