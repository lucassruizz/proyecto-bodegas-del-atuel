-- BODEGAS DEL ATUEL
-- 007_roles.sql
-- Ejecutar con un usuario administrador de PostgreSQL.
-- Para crear objetos futuros como propietario, utilizar: SET ROLE bodega_owner;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'bodega_owner') THEN
        CREATE ROLE bodega_owner NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'bodega_api') THEN
        CREATE ROLE bodega_api LOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'bodega_reportes') THEN
        CREATE ROLE bodega_reportes LOGIN;
    END IF;
END;
$$;

-- El esquema deja de ser accesible por PUBLIC.
REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL PROCEDURES IN SCHEMA public FROM PUBLIC;

GRANT USAGE, CREATE ON SCHEMA public TO bodega_owner;

-- Reasigna a bodega_owner los objetos creados previamente por el usuario ejecutor.
-- REASSIGN OWNED requiere permisos de administrador/propietario de los roles implicados.
REASSIGN OWNED BY CURRENT_USER TO bodega_owner;

-- Permisos sobre objetos que ya existen.
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO bodega_api;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO bodega_api;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO bodega_api;
GRANT EXECUTE ON ALL PROCEDURES IN SCHEMA public TO bodega_api;

-- La API puede consultar auditoría, pero no alterarla.
REVOKE INSERT, UPDATE, DELETE ON TABLE auditoria_precio FROM bodega_api;
GRANT SELECT ON TABLE auditoria_precio TO bodega_api;

-- Rol de reportes: únicamente lectura.
GRANT USAGE ON SCHEMA public TO bodega_reportes;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO bodega_reportes;

-- CLAVE: los privilegios por defecto se declaran PARA EL ROL QUE CREARÁ LOS OBJETOS,
-- no para CURRENT_USER. Crear futuras tablas/secuencias usando SET ROLE bodega_owner.
ALTER DEFAULT PRIVILEGES FOR ROLE bodega_owner IN SCHEMA public
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO bodega_api;
ALTER DEFAULT PRIVILEGES FOR ROLE bodega_owner IN SCHEMA public
    GRANT USAGE, SELECT ON SEQUENCES TO bodega_api;
ALTER DEFAULT PRIVILEGES FOR ROLE bodega_owner IN SCHEMA public
    GRANT EXECUTE ON FUNCTIONS TO bodega_api;
-- En PostgreSQL, el grupo de privilegios por defecto FUNCTIONS abarca rutinas.

ALTER DEFAULT PRIVILEGES FOR ROLE bodega_owner IN SCHEMA public
    GRANT SELECT ON TABLES TO bodega_reportes;

-- No se otorgan privilegios por defecto a PUBLIC. Los objetos nuevos heredan
-- los grants anteriores solamente cuando bodega_owner es su rol creador efectivo.
