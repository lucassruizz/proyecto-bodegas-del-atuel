-- BODEGAS DEL ATUEL
-- 001_esquema.sql

-- 1. TIPOS ENUMERADOS

CREATE TYPE estado_documento AS ENUM (
    'en_confeccion',
    'terminado',
    'procesado'
);

-- 2. DOMINIOS

CREATE DOMAIN dom_cuit AS varchar(11)
CHECK (VALUE ~ '^[0-9]{11}$');

--3. TABLAS

-- Localidad

CREATE TABLE localidad (
    idLocalidad bigint GENERATED ALWAYS AS IDENTITY,
    nombre varchar(150) NOT NULL,
    provincia varchar(100) NOT NULL,
    codigoPostal varchar(10) NOT NULL,

    CONSTRAINT pk_localidad
        PRIMARY KEY (idLocalidad),

    CONSTRAINT ck_localidad_nombre
        CHECK (btrim(nombre) <> ''),

    CONSTRAINT ck_localidad_provincia
        CHECK (btrim(provincia) <> ''),

    CONSTRAINT ck_localidad_codigo_postal
        CHECK (btrim(codigoPostal) <> '')
);

-- Encargado regional

CREATE TABLE encargado_regional (
    idEncargado bigint GENERATED ALWAYS AS IDENTITY,
    datosEncargado varchar(200) NOT NULL,
    idLocalidad bigint NOT NULL,

    CONSTRAINT pk_encargado_regional
        PRIMARY KEY (idEncargado),

    CONSTRAINT fk_encargado_localidad FOREIGN KEY (idLocalidad) REFERENCES localidad (idLocalidad)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT,

    CONSTRAINT uq_encargado_localidad
        UNIQUE (idLocalidad),

    CONSTRAINT ck_encargado_datos
        CHECK (btrim(datosEncargado) <> '')
);

-- Sala venta

CREATE TABLE sala_venta(
    idSalaVenta bigint GENERATED ALWAYS AS IDENTITY,
    calle varchar(150) NOT NULL,
    numero varchar(20) NOT NULL,
    diaCierreSemanal varchar(9) NOT NULL,
    idLocalidad bigint NOT NULL,

    CONSTRAINT pk_sala_venta
        PRIMARY KEY (idSalaVenta),

    CONSTRAINT fk_sala_venta_localidad FOREIGN KEY (idLocalidad) REFERENCES localidad (idLocalidad)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT,

    CONSTRAINT ck_sala_venta_calle
        CHECK (btrim(calle) <> ''),

    CONSTRAINT ck_sala_venta_numero
        CHECK (btrim(numero) <> ''),

    CONSTRAINT ck_sala_venta_dia_cierre_semanal
        CHECK (diaCierreSemanal IN ('lunes', 'martes', 'miercoles', 'jueves', 'viernes', 'sabado', 'domingo'))
);

-- Empleado

CREATE TABLE empleado(
    cuit dom_cuit NOT NULL,
    nombre varchar(150) NOT NULL,
    fechaIngresoLaboral date NOT NULL,
    salario numeric(12,2) NOT NULL,
    idSalaVenta bigint NOT NULL,

    CONSTRAINT pk_empleado
        PRIMARY KEY (cuit),

    CONSTRAINT fk_empleado_sala_venta FOREIGN KEY (idSalaVenta) REFERENCES sala_venta (idSalaVenta)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT,

    CONSTRAINT ck_empleado_nombre
        CHECK (btrim(nombre) <> ''),

    CONSTRAINT ck_salario
        CHECK (salario > 0)
);

-- Departamento

CREATE TABLE departamento(
    idDepartamento bigint GENERATED ALWAYS AS IDENTITY,
    nombreDepartamento varchar(100) NOT NULL,
    provincia varchar(100) NOT NULL,

    CONSTRAINT pk_departamento
        PRIMARY KEY (idDepartamento),

    CONSTRAINT ck_departamento_nombre
        CHECK (btrim(nombreDepartamento) <> ''),

    CONSTRAINT uq_nombre_departamento_provincia
        UNIQUE (nombreDepartamento, provincia),

    CONSTRAINT ck_departamento_provincia
        CHECK (btrim(provincia) <> '')
);

-- Finca

CREATE TABLE finca(
    id bigint GENERATED ALWAYS AS IDENTITY,
    nombre varchar(150) NOT NULL,
    superficieTotal numeric(12,2) NOT NULL,
    idDepartamento bigint NOT NULL,

    CONSTRAINT pk_finca
        PRIMARY KEY (id),

    CONSTRAINT fk_finca_idDepartamento FOREIGN KEY (idDepartamento) REFERENCES departamento (idDepartamento)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT,

    CONSTRAINT ck_finca_nombre
        CHECK (btrim(nombre) <> ''),

    CONSTRAINT ck_finca_superficie_total
        CHECK (superficieTotal > 0)
);

-- Cepa

CREATE TABLE cepa(
    idCepa bigint GENERATED ALWAYS AS IDENTITY,
    nombre varchar(100) NOT NULL,
    tipo varchar(6) NOT NULL,

    CONSTRAINT pk_idCepa
        PRIMARY KEY (idCepa),

    CONSTRAINT ck_cepa_nombre
        CHECK (btrim(nombre) <> ''),

    CONSTRAINT ck_cepa_tipo
        CHECK (tipo IN ('tinta', 'blanca'))
);

-- Parcelas

CREATE TABLE parcela(
    idFinca bigint NOT NULL,
    numeroParcela integer NOT NULL,
    superficie numeric(12,2) NOT NULL,
    anioPlantacion smallint NOT NULL,
    idCepa bigint NOT NULL,

    CONSTRAINT pk_parcelas
        PRIMARY KEY (idFinca, numeroParcela),

    CONSTRAINT fk_parcelas_finca FOREIGN KEY (idFinca) REFERENCES finca (id)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT,

    CONSTRAINT fk_parcelas_cepa FOREIGN KEY (idCepa) REFERENCES cepa (idCepa)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT,

    CONSTRAINT ck_parcelas_numero
        CHECK (numeroParcela > 0),

    CONSTRAINT ck_parcelas_superficie
        CHECK (superficie > 0),

    CONSTRAINT ck_parcelas_anio_plantacion
        CHECK (anioPlantacion BETWEEN 1 AND 9999)
);

-- Bodega

CREATE TABLE bodega(
    cuit dom_cuit NOT NULL,
    razonSocial varchar(200) NOT NULL,
    domicilio varchar(250) NOT NULL,

    CONSTRAINT pk_bodega_cuit
        PRIMARY KEY (cuit),

    CONSTRAINT ck_bodega_razon_social
        CHECK (btrim(razonSocial) <> ''),

    CONSTRAINT ck_bodega_domicilio
        CHECK (btrim(domicilio) <> '')
);

-- Lote

CREATE TABLE lote(
    numero bigint NOT NULL,
    fechaCosecha date NOT NULL,
    kilosCosechados numeric(12,2) NOT NULL,
    campania smallint NOT NULL,
    idFinca bigint NOT NULL,
    numeroParcela integer NOT NULL,
    cuitBodega dom_cuit NOT NULL,

    CONSTRAINT pk_lote_numero
        PRIMARY KEY(numero),

    CONSTRAINT fk_lote_finca FOREIGN KEY (idFinca) REFERENCES finca (id)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT,

    CONSTRAINT fk_lote_parcelas FOREIGN KEY (idFinca, numeroParcela) REFERENCES parcela (idFinca, numeroParcela)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT,

    CONSTRAINT fk_lote_bodega FOREIGN KEY (cuitBodega) REFERENCES bodega (cuit)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,

    CONSTRAINT uq_idFInca_numero_parcela_campania
        UNIQUE (idFinca, numeroParcela, campania),

    CONSTRAINT ck_lote_kilos_cosechados
        CHECK (kilosCosechados > 0),

    CONSTRAINT ck_lote_campania
        CHECK (campania BETWEEN 1 AND 9999)
);

-- Analisis calidad

CREATE TABLE analisis_calidad(
    idAnalisis bigint GENERATED ALWAYS AS IDENTITY,
    fecha date NOT NULL,
    gradoBrix numeric(5,2) NOT NULL,
    ph numeric(4,2) NOT NULL,
    acidezTotal numeric(8,2) NOT NULL,
    numeroLote bigint NOT NULL,

    CONSTRAINT pk_analisis_calidad
        PRIMARY KEY (idAnalisis),

    CONSTRAINT fk_analisis_calidad_lote FOREIGN KEY (numeroLote) REFERENCES lote (numero)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT,

    CONSTRAINT ck_analisis_grado_brix
        CHECK (gradoBrix BETWEEN 0 AND 100),

    CONSTRAINT ck_analisis_ph
        CHECK (ph BETWEEN 0 AND 14),

    CONSTRAINT ck_analisis_acidez_total
        CHECK (acidezTotal > 0)
);

-- Vino

CREATE TABLE vino(
    codigoVino bigint NOT NULL,
    nombre varchar(150) NOT NULL,
    volumen numeric(10,2) NOT NULL,
    graduacionAlcoholica numeric(5,2) NOT NULL,
    tipo varchar(10) NOT NULL,
    anada smallint NOT NULL,
    precio numeric(12,2) NOT NULL,
    cuitBodega dom_cuit NOT NULL,

    CONSTRAINT pk_vino
        PRIMARY KEY (codigoVino),

    CONSTRAINT fk_vino_bodega FOREIGN KEY (cuitBodega) REFERENCES bodega (cuit)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,

    CONSTRAINT ck_vino_codigo
        CHECK (codigoVino > 0),

    CONSTRAINT ck_vino_nombre
        CHECK (btrim(nombre) <> ''),

    CONSTRAINT ck_vino_volumen
        CHECK (volumen > 0),

    CONSTRAINT ck_vino_graduacion
        CHECK (graduacionAlcoholica BETWEEN 5 AND 20),

    CONSTRAINT ck_vino_tipo
        CHECK (tipo IN ('tinto', 'blanco', 'rosado', 'espumante')),

    CONSTRAINT ck_vino_anada
        CHECK (anada BETWEEN 1 AND 9999),

    CONSTRAINT ck_vino_precio
        CHECK (precio > 0)
);

-- Componen

CREATE TABLE componen(
    codigoVino bigint NOT NULL,
    idCepa bigint NOT NULL,
    porcentaje numeric(5,2) NOT NULL,

    CONSTRAINT pk_componen
        PRIMARY KEY (codigoVino, idCepa),

    CONSTRAINT fk_componen_vino FOREIGN KEY (codigoVino) REFERENCES vino (codigoVino)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT,

    CONSTRAINT fk_componen_cepa FOREIGN KEY (idCepa) REFERENCES cepa (idCepa)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT,

    CONSTRAINT ck_componen_porcentaje
        CHECK (porcentaje > 0 AND porcentaje <= 100)
);

-- Maridaje

CREATE TABLE maridaje(
    idMaridaje bigint GENERATED ALWAYS AS IDENTITY,
    nombre varchar(150) NOT NULL,
    temperatura numeric(5,2) NOT NULL,

    CONSTRAINT pk_maridaje
        PRIMARY KEY (idMaridaje),

    CONSTRAINT ck_maridaje_nombre
        CHECK (btrim(nombre) <> '')
);

-- Tienen

CREATE TABLE tienen(
    codigoVino bigint NOT NULL,
    idMaridaje bigint NOT NULL,

    CONSTRAINT pk_tienen
        PRIMARY KEY (codigoVino, idMaridaje),

    CONSTRAINT fk_tienen_vino FOREIGN KEY (codigoVino) REFERENCES vino (codigoVino)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT,

    CONSTRAINT fk_tienen_maridaje FOREIGN KEY (idMaridaje) REFERENCES maridaje (idMaridaje)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT
);

-- Auditoria_precio

CREATE TABLE auditoria_precio(
    idAuditoria bigint GENERATED ALWAYS AS IDENTITY,
    codigoVino bigint NOT NULL,
    precioAnterior numeric(12,2) NOT NULL,
    precioNuevo numeric(12,2) NOT NULL,
    fechaHora timestamp without time zone NOT NULL,
    usuario varchar(100) NOT NULL,

    CONSTRAINT pk_auditoria_precio
        PRIMARY KEY (idAuditoria),

    CONSTRAINT fk_auditoria_precio_vino FOREIGN KEY (codigoVino) REFERENCES vino (codigoVino)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT,

    CONSTRAINT ck_auditoria_precio_anterior
        CHECK (precioAnterior > 0),

    CONSTRAINT ck_auditoria_precio_nuevo
        CHECK (precioNuevo > 0),

    CONSTRAINT ck_auditoria_precio_diferente
        CHECK (precioAnterior <> precioNuevo)
);

-- Cliente

CREATE TABLE cliente(
    idCliente bigint GENERATED ALWAYS AS IDENTITY,
    apellido varchar(150),
    nombre varchar(150),
    razonSocial varchar(200),
    tipoDocumento varchar(20) NOT NULL,
    numeroDocumento varchar(30) NOT NULL,
    direccion varchar(250) NOT NULL,
    idLocalidad bigint NOT NULL,
    fechaAlta date NOT NULL DEFAULT CURRENT_DATE,
    descuento numeric(5,2) NOT NULL,

    CONSTRAINT pk_cliente
        PRIMARY KEY (idCliente),

    CONSTRAINT fk_cliente_localidad FOREIGN KEY (idLocalidad) REFERENCES localidad (idLocalidad)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT,

    CONSTRAINT uq_cliente_documento
        UNIQUE (tipoDocumento, numeroDocumento),

    CONSTRAINT ck_cliente_apellido
        CHECK (
            apellido IS NULL OR btrim(apellido) <> ''
        ),

    CONSTRAINT ck_cliente_nombre
        CHECK (
            nombre IS NULL OR btrim(nombre) <> ''
        ),

    CONSTRAINT ck_cliente_razon_social
        CHECK (
            razonSocial IS NULL OR btrim(razonSocial) <> ''
        ),

    CONSTRAINT ck_cliente_tipo_documento
        CHECK (btrim(tipoDocumento) <> ''),

    CONSTRAINT ck_cliente_numero_documento
        CHECK (btrim(numeroDocumento) <> ''),

    CONSTRAINT ck_cliente_direccion
        CHECK (btrim(direccion) <> ''),

    CONSTRAINT ck_cliente_identificacion
        CHECK (
            (
                nombre IS NOT NULL
                AND apellido IS NOT NULL
                AND razonSocial IS NULL
            )
            OR
            (
                nombre IS NULL
                AND apellido IS NULL
                AND razonSocial IS NOT NULL
            )
        ),

    CONSTRAINT ck_cliente_descuento
        CHECK (descuento IN (10.00, 20.00, 30.00))
);

-- Socio_club

CREATE TABLE socio_club(
    idCliente bigint NOT NULL,

    CONSTRAINT pk_socio_club
        PRIMARY KEY (idCliente),

    CONSTRAINT fk_socio_club_cliente FOREIGN KEY (idCliente) REFERENCES cliente (idCliente)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT
);

-- Distribuidor

CREATE TABLE distribuidor(
    idCliente bigint NOT NULL,
    zonaCobertura varchar(250) NOT NULL,
    numeroHabilitacion varchar(50) NOT NULL,

    CONSTRAINT pk_distribuidor
        PRIMARY KEY (idCliente),

    CONSTRAINT fk_distribuidor_cliente FOREIGN KEY (idCliente) REFERENCES cliente (idCliente)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT,

    CONSTRAINT ck_distribuidor_zona
        CHECK (btrim(zonaCobertura) <> ''),

    CONSTRAINT ck_distribuidor_habilitacion
        CHECK (btrim(numeroHabilitacion) <> '')
);

-- Exportador

CREATE TABLE exportador(
    idCliente bigint NOT NULL,
    paisDestinoPrincipal varchar(100) NOT NULL,

    CONSTRAINT pk_exportador
        PRIMARY KEY (idCliente),

    CONSTRAINT fk_exportador_cliente FOREIGN KEY (idCliente) REFERENCES cliente (idCliente)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT,

    CONSTRAINT ck_exportador_pais
        CHECK (btrim(paisDestinoPrincipal) <> '')
);

-- Permisos

CREATE TABLE permisos(
    codigo varchar(50) NOT NULL,
    fechaEmision date NOT NULL,
    fechaVencimiento date NOT NULL,
    idExportador bigint NOT NULL,

    CONSTRAINT pk_permisos
        PRIMARY KEY (codigo),

    CONSTRAINT fk_permisos_exportador FOREIGN KEY (idExportador) REFERENCES exportador (idCliente)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT,

    CONSTRAINT ck_permisos_codigo
        CHECK (btrim(codigo) <> '')
);

-- Comprobante

CREATE TABLE comprobante(
    numero bigint NOT NULL,
    fecha date NOT NULL DEFAULT CURRENT_DATE,
    idCliente bigint NOT NULL,
    idSalaVenta bigint NOT NULL,
    subtotal numeric(12,2) NOT NULL,
    descuento numeric(12,2) NOT NULL,
    total numeric(12,2) NOT NULL,

    CONSTRAINT pk_comprobante
        PRIMARY KEY (numero),

    CONSTRAINT fk_comprobante_cliente FOREIGN KEY (idCliente) REFERENCES cliente (idCliente)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT,

    CONSTRAINT fk_comprobante_sala_venta FOREIGN KEY (idSalaVenta) REFERENCES sala_venta (idSalaVenta)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT,

    CONSTRAINT ck_comprobante_numero
        CHECK (numero > 0),

    CONSTRAINT ck_comprobante_subtotal
        CHECK (subtotal >= 0),

    CONSTRAINT ck_comprobante_descuento
        CHECK (descuento >= 0),

    CONSTRAINT ck_comprobante_total
        CHECK (total >= 0)
);

-- Renglon_comprobante

CREATE TABLE renglon_comprobante(
    numeroComprobante bigint NOT NULL,
    codigoVino bigint NOT NULL,
    cantidad integer NOT NULL,
    precioUnitario numeric(12,2) NOT NULL,
    descuento numeric(5,2) NOT NULL,
    subtotalRenglon numeric(12,2) NOT NULL,

    CONSTRAINT pk_renglon_comprobante
        PRIMARY KEY (numeroComprobante, codigoVino),

    CONSTRAINT fk_renglon_comprobante_comprobante FOREIGN KEY (numeroComprobante) REFERENCES comprobante (numero)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT,

    CONSTRAINT fk_renglon_comprobante_vino FOREIGN KEY (codigoVino) REFERENCES vino (codigoVino)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT,

    CONSTRAINT ck_renglon_cantidad
        CHECK (cantidad > 0),

    CONSTRAINT ck_renglon_precio
        CHECK (precioUnitario > 0),

    CONSTRAINT ck_renglon_descuento
        CHECK (descuento IN (10.00, 20.00, 30.00)),

    CONSTRAINT ck_renglon_subtotal
        CHECK (subtotalRenglon >= 0)
);

-- Empresas_transporte

CREATE TABLE empresas_transporte(
    codigoTransporte bigint NOT NULL,
    razonSocial varchar(200) NOT NULL,
    cuit dom_cuit NOT NULL,
    email varchar(254) NOT NULL,
    telefono varchar(30) NOT NULL,
    domicilio varchar(250) NOT NULL,

    CONSTRAINT pk_empresas_transporte
        PRIMARY KEY (codigoTransporte),

    CONSTRAINT uq_empresas_transporte_cuit
        UNIQUE (cuit),

    CONSTRAINT ck_transporte_codigo
        CHECK (codigoTransporte > 0),

    CONSTRAINT ck_transporte_razon_social
        CHECK (btrim(razonSocial) <> ''),

    CONSTRAINT ck_transporte_email
        CHECK (btrim(email) <> ''),

    CONSTRAINT ck_transporte_telefono
        CHECK (btrim(telefono) <> ''),

    CONSTRAINT ck_transporte_domicilio
        CHECK (btrim(domicilio) <> '')
);

-- Alcanza

CREATE TABLE alcanza(
    codigoTransporte bigint NOT NULL,
    idLocalidad bigint NOT NULL,

    CONSTRAINT pk_alcanza
        PRIMARY KEY (codigoTransporte, idLocalidad),

    CONSTRAINT fk_alcanza_transporte FOREIGN KEY (codigoTransporte) REFERENCES empresas_transporte (codigoTransporte)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT,

    CONSTRAINT fk_alcanza_localidad FOREIGN KEY (idLocalidad) REFERENCES localidad (idLocalidad)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT
);

-- Deposito

CREATE TABLE deposito(
    idDeposito bigint NOT NULL,

    CONSTRAINT pk_deposito
        PRIMARY KEY (idDeposito),

    CONSTRAINT ck_deposito_id
        CHECK (idDeposito = 1)
);

-- Almacena

CREATE TABLE almacena(
    codigoVino bigint NOT NULL,
    idDeposito bigint NOT NULL,
    cantidadStock integer NOT NULL DEFAULT 0,

    CONSTRAINT pk_almacena
        PRIMARY KEY (codigoVino),

    CONSTRAINT fk_almacena_vino FOREIGN KEY (codigoVino) REFERENCES vino (codigoVino)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT,

    CONSTRAINT fk_almacena_deposito FOREIGN KEY (idDeposito) REFERENCES deposito (idDeposito)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT,

    CONSTRAINT ck_almacena_deposito
        CHECK (idDeposito = 1),

    CONSTRAINT ck_almacena_stock
        CHECK (cantidadStock >= 0)
);

-- Posee

CREATE TABLE posee(
    idSalaVenta bigint NOT NULL,
    codigoVino bigint NOT NULL,
    cantidadStock integer NOT NULL DEFAULT 0,

    CONSTRAINT pk_posee
        PRIMARY KEY (idSalaVenta, codigoVino),

    CONSTRAINT fk_posee_sala_venta FOREIGN KEY (idSalaVenta) REFERENCES sala_venta (idSalaVenta)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT,

    CONSTRAINT fk_posee_vino FOREIGN KEY (codigoVino) REFERENCES vino (codigoVino)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT,

    CONSTRAINT ck_posee_stock
        CHECK (cantidadStock >= 0)
);

-- Ingresos

CREATE TABLE ingresos(
    codigoIngreso bigint NOT NULL,
    fecha date NOT NULL DEFAULT CURRENT_DATE,
    estado estado_documento NOT NULL DEFAULT 'en_confeccion',
    cuitBodega dom_cuit NOT NULL,
    codigoTransporte bigint NOT NULL,
    idDeposito bigint NOT NULL,

    CONSTRAINT pk_ingresos
        PRIMARY KEY (codigoIngreso),

    CONSTRAINT fk_ingresos_bodega FOREIGN KEY (cuitBodega) REFERENCES bodega (cuit)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,

    CONSTRAINT fk_ingresos_transporte FOREIGN KEY (codigoTransporte) REFERENCES empresas_transporte (codigoTransporte)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT,

    CONSTRAINT fk_ingresos_deposito FOREIGN KEY (idDeposito) REFERENCES deposito (idDeposito)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT,

    CONSTRAINT ck_ingresos_codigo
        CHECK (codigoIngreso > 0),

    CONSTRAINT ck_ingresos_deposito
        CHECK (idDeposito = 1)
);

-- Contiene

CREATE TABLE contiene(
    codigoIngreso bigint NOT NULL,
    codigoVino bigint NOT NULL,
    cantidadBotellas integer NOT NULL,

    CONSTRAINT pk_contiene
        PRIMARY KEY (codigoIngreso, codigoVino),

    CONSTRAINT fk_contiene_ingresos FOREIGN KEY (codigoIngreso) REFERENCES ingresos (codigoIngreso)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT,

    CONSTRAINT fk_contiene_vino FOREIGN KEY (codigoVino) REFERENCES vino (codigoVino)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT,

    CONSTRAINT ck_contiene_cantidad
        CHECK (cantidadBotellas > 0)
);

-- Transferencia

CREATE TABLE transferencia(
    numeroSolicitud bigint NOT NULL,
    estado estado_documento NOT NULL DEFAULT 'en_confeccion',
    fechaConfeccion date NOT NULL DEFAULT CURRENT_DATE,
    idSalaVenta bigint NOT NULL,

    CONSTRAINT pk_transferencia
        PRIMARY KEY (numeroSolicitud),

    CONSTRAINT fk_transferencia_sala_venta FOREIGN KEY (idSalaVenta) REFERENCES sala_venta (idSalaVenta)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT,

    CONSTRAINT ck_transferencia_numero
        CHECK (numeroSolicitud > 0)
);

-- Incluye

CREATE TABLE incluye(
    numeroSolicitud bigint NOT NULL,
    codigoVino bigint NOT NULL,
    cantidad integer NOT NULL,

    CONSTRAINT pk_incluye
        PRIMARY KEY (numeroSolicitud, codigoVino),

    CONSTRAINT fk_incluye_transferencia FOREIGN KEY (numeroSolicitud) REFERENCES transferencia (numeroSolicitud)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT,

    CONSTRAINT fk_incluye_vino FOREIGN KEY (codigoVino) REFERENCES vino (codigoVino)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT,

    CONSTRAINT ck_incluye_cantidad
        CHECK (cantidad > 0)
);
