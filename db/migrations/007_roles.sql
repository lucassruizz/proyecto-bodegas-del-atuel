-- Roles

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

REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL PROCEDURES IN SCHEMA public FROM PUBLIC;

GRANT USAGE, CREATE ON SCHEMA public TO bodega_owner;

DO $$
DECLARE
    objeto text;
BEGIN
    FOR objeto IN
        SELECT format('%s %I.%I',
            CASE c.relkind WHEN 'v' THEN 'VIEW' ELSE 'TABLE' END,
            n.nspname, c.relname)
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' AND c.relkind IN ('r', 'v')
          AND c.relowner = current_user::regrole
        UNION ALL
        SELECT format('ROUTINE %I.%I(%s)',
            n.nspname, p.proname, pg_get_function_identity_arguments(p.oid))
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.prokind IN ('f', 'p')
          AND p.proowner = current_user::regrole
        UNION ALL
        SELECT format('%s %I.%I',
            CASE t.typtype WHEN 'd' THEN 'DOMAIN' ELSE 'TYPE' END,
            n.nspname, t.typname)
        FROM pg_type t
        JOIN pg_namespace n ON n.oid = t.typnamespace
        WHERE n.nspname = 'public' AND t.typtype IN ('d', 'e')
          AND t.typowner = current_user::regrole
    LOOP
        EXECUTE format('ALTER %s OWNER TO bodega_owner', objeto);
    END LOOP;
END;
$$;

GRANT USAGE ON SCHEMA public TO bodega_api;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO bodega_api;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO bodega_api;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO bodega_api;
GRANT EXECUTE ON ALL PROCEDURES IN SCHEMA public TO bodega_api;

REVOKE INSERT, UPDATE, DELETE ON TABLE auditoria_precio FROM bodega_api;
GRANT SELECT ON TABLE auditoria_precio TO bodega_api;

GRANT USAGE ON SCHEMA public TO bodega_reportes;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO bodega_reportes;

ALTER DEFAULT PRIVILEGES FOR ROLE bodega_owner IN SCHEMA public
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO bodega_api;
ALTER DEFAULT PRIVILEGES FOR ROLE bodega_owner IN SCHEMA public
    GRANT USAGE, SELECT ON SEQUENCES TO bodega_api;
ALTER DEFAULT PRIVILEGES FOR ROLE bodega_owner IN SCHEMA public
    GRANT EXECUTE ON FUNCTIONS TO bodega_api;

ALTER DEFAULT PRIVILEGES FOR ROLE bodega_owner IN SCHEMA public
    GRANT SELECT ON TABLES TO bodega_reportes;
