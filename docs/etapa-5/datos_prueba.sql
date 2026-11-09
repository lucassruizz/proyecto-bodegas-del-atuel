-- Datos auxiliares para probar ramas con cero candidatos en la carga original.
-- Ejecutar únicamente en una copia desechable llamada bodegas_etapa5_pruebas.
BEGIN;
DO $$
BEGIN
    IF current_database() <> 'bodegas_etapa5_pruebas' THEN
        RAISE EXCEPTION 'Usar la copia desechable bodegas_etapa5_pruebas';
    END IF;
END
$$;

-- I1: quitar la cobertura que el transportista 1 debería recuperar.
DELETE FROM alcanza a USING localidad l
WHERE a.idLocalidad = l.idLocalidad AND a.codigoTransporte = 1
  AND l.nombre = 'General Alvear' AND l.provincia = 'Mendoza';

-- D1: hacer que un comprobante de un socio supere los cinco años.
-- U1: simular una discrepancia en el total de ese mismo comprobante.
UPDATE comprobante SET fecha = (CURRENT_DATE - INTERVAL '6 years')::date, total = 0
WHERE numero = 1 AND idCliente IN (SELECT idCliente FROM socio_club);

-- D2: crear una cepa sin referencias.
INSERT INTO cepa (nombre, tipo) VALUES ('Cepa de prueba etapa 5', 'tinta');

-- D3: antigüedad de un año para un empleado de la sala dada de baja.
UPDATE empleado SET fechaIngresoLaboral = (CURRENT_DATE - INTERVAL '1 year')::date
WHERE cuit = '20000000001' AND idSalaVenta = 2;

-- D4 y D6: crear un socio antiguo sin compras en San Rafael.
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
