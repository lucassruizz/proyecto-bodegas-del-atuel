-- BODEGAS DEL ATUEL
-- Etapa 2: restricciones declarativas adicionales.
-- Este archivo se ejecuta después de 001_esquema_corregido.sql.

-- RN-04: una parcela se cosecha, como máximo, una vez por campaña.
ALTER TABLE lote
    ADD CONSTRAINT uq_lote_parcela_campania
    UNIQUE (idFinca, numeroParcela, campania);

-- RN-07: un permiso vence después de la fecha en que fue emitido.
ALTER TABLE permisos
    ADD CONSTRAINT ck_permisos_fecha_vencimiento
    CHECK (fechaVencimiento > fechaEmision);

-- Identificación comercial requerida para los vinos.
ALTER TABLE vino
    ADD CONSTRAINT uq_vino_nombre_anada_volumen
    UNIQUE (nombre, anada, volumen);
