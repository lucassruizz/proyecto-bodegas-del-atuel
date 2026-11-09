-- Catálogos y saldos pequeños para una base de pruebas recién inicializada.
BEGIN;
INSERT INTO localidad (nombre, provincia, codigopostal) VALUES ('San Rafael', 'Mendoza', '5600');
INSERT INTO encargado_regional (datosencargado, idlocalidad) VALUES ('Encargado de prueba', 1);
INSERT INTO sala_venta (calle, numero, diacierresemanal, idlocalidad) VALUES ('Mitre', '100', 'lunes', 1);
INSERT INTO bodega VALUES ('20111111111', 'Bodega de prueba', 'San Rafael');
INSERT INTO cepa (nombre, tipo) VALUES ('Malbec', 'tinta'), ('Chardonnay', 'blanca');
INSERT INTO maridaje (nombre, temperatura) VALUES ('Asado', 16);
INSERT INTO deposito VALUES (1);
INSERT INTO empresas_transporte VALUES (1, 'Transporte de prueba', '20222222222',
    'prueba@example.test', '1000', 'San Rafael');
INSERT INTO vino VALUES
    (1, 'Malbec de prueba', 750, 13, 'tinto', 2024, 100, '20111111111'),
    (2, 'Chardonnay de prueba', 750, 12, 'blanco', 2025, 150, '20111111111');
INSERT INTO componen VALUES (1, 1, 100), (2, 2, 100);
INSERT INTO tienen VALUES (1, 1);
INSERT INTO almacena VALUES (1, 1, 100), (2, 1, 100);
INSERT INTO posee VALUES (1, 1, 10), (1, 2, 0);
COMMIT;
