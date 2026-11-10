"""SQL de la API. Los valores externos se envían como parámetros de psycopg."""


def salud(db):
    return db.execute("SELECT 1 AS disponible").fetchone()


def listar_vinos(db, tipo, cepa, bodega, anada, limite, offset):
    return db.execute("""
        SELECT v.codigovino AS codigo, v.nombre, v.tipo, v.anada, v.precio,
               v.cuitbodega AS cuit_bodega, b.razonsocial AS bodega
        FROM vino v JOIN bodega b ON b.cuit = v.cuitbodega
        WHERE (%(tipo)s::text IS NULL OR v.tipo = %(tipo)s)
          AND (%(bodega)s::text IS NULL OR v.cuitbodega = %(bodega)s)
          AND (%(anada)s::integer IS NULL OR v.anada = %(anada)s)
          AND (%(cepa)s::bigint IS NULL OR EXISTS (
              SELECT 1 FROM componen c
              WHERE c.codigovino = v.codigovino AND c.idcepa = %(cepa)s
          ))
        ORDER BY v.codigovino LIMIT %(limite)s OFFSET %(offset)s
    """, dict(tipo=tipo, cepa=cepa, bodega=bodega, anada=anada,
              limite=limite, offset=offset)).fetchall()


def detalle_vino(db, codigo):
    return db.execute("""
        SELECT v.codigovino AS codigo, v.nombre, v.volumen, v.tipo, v.anada,
               v.graduacionalcoholica AS graduacion_alcoholica, v.precio,
               v.cuitbodega AS cuit_bodega, b.razonsocial AS bodega,
               st.stock_deposito, st.stock_salas, st.stock_total,
               COALESCE(c.cepas, '[]'::jsonb) AS composicion,
               COALESCE(m.maridajes, '[]'::jsonb) AS maridajes
        FROM vino v
        JOIN bodega b ON b.cuit = v.cuitbodega
        JOIN vw_stock_total_vino st USING (codigovino)
        LEFT JOIN LATERAL (
            SELECT jsonb_agg(jsonb_build_object(
                'id_cepa', ce.idcepa, 'nombre', ce.nombre,
                'porcentaje', co.porcentaje::text
            ) ORDER BY ce.idcepa) AS cepas
            FROM componen co JOIN cepa ce USING (idcepa)
            WHERE co.codigovino = v.codigovino
        ) c ON true
        LEFT JOIN LATERAL (
            SELECT jsonb_agg(jsonb_build_object(
                'id_maridaje', ma.idmaridaje, 'nombre', ma.nombre
            ) ORDER BY ma.idmaridaje) AS maridajes
            FROM tienen t JOIN maridaje ma USING (idmaridaje)
            WHERE t.codigovino = v.codigovino
        ) m ON true
        WHERE v.codigovino = %s
    """, (codigo,)).fetchone()


def insertar_vino(db, vino):
    db.execute("""
        INSERT INTO vino (codigovino, nombre, volumen, graduacionalcoholica,
                          tipo, anada, precio, cuitbodega)
        VALUES (%(codigo)s, %(nombre)s, %(volumen)s, %(graduacion_alcoholica)s,
                %(tipo)s, %(anada)s, %(precio)s, %(cuit_bodega)s)
    """, vino.model_dump())


def actualizar_vino(db, codigo, vino):
    return db.execute("""
        UPDATE vino SET nombre = %(nombre)s, volumen = %(volumen)s,
            graduacionalcoholica = %(graduacion_alcoholica)s, tipo = %(tipo)s,
            anada = %(anada)s, precio = %(precio)s, cuitbodega = %(cuit_bodega)s
        WHERE codigovino = %(codigo)s RETURNING codigovino
    """, dict(vino.model_dump(), codigo=codigo)).fetchone()


def bloquear_vino(db, codigo):
    return db.execute(
        "SELECT codigovino FROM vino WHERE codigovino = %s FOR UPDATE", (codigo,)
    ).fetchone()


def eliminar_vino(db, codigo):
    db.execute("DELETE FROM vino WHERE codigovino = %s", (codigo,))


def quitar_composicion(db, codigo):
    db.execute("DELETE FROM componen WHERE codigovino = %s", (codigo,))


def insertar_cepa_vino(db, codigo, cepa):
    db.execute(
        "INSERT INTO componen (codigovino, idcepa, porcentaje) VALUES (%s, %s, %s)",
        (codigo, cepa.id_cepa, cepa.porcentaje),
    )


def quitar_maridajes(db, codigo):
    db.execute("DELETE FROM tienen WHERE codigovino = %s", (codigo,))


def insertar_maridaje_vino(db, codigo, maridaje):
    db.execute(
        "INSERT INTO tienen (codigovino, idmaridaje) VALUES (%s, %s)",
        (codigo, maridaje),
    )


_CLIENTES = """
    SELECT c.idcliente AS id_cliente, c.nombre, c.apellido,
           c.razonsocial AS razon_social, c.tipodocumento AS tipo_documento,
           c.numerodocumento AS numero_documento, c.direccion,
           c.idlocalidad AS id_localidad, c.fechaalta AS fecha_alta, c.descuento,
           CASE WHEN s.idcliente IS NOT NULL THEN 'socio_club'
                WHEN d.idcliente IS NOT NULL THEN 'distribuidor'
                WHEN e.idcliente IS NOT NULL THEN 'exportador' END AS tipo,
           d.zonacobertura AS zona_cobertura,
           d.numerohabilitacion AS numero_habilitacion,
           e.paisdestinoprincipal AS pais_destino_principal
    FROM cliente c
    LEFT JOIN socio_club s USING (idcliente)
    LEFT JOIN distribuidor d USING (idcliente)
    LEFT JOIN exportador e USING (idcliente)
"""


def listar_clientes(db, limite, offset):
    return db.execute(
        _CLIENTES + " ORDER BY c.idcliente LIMIT %s OFFSET %s", (limite, offset)
    ).fetchall()


def detalle_cliente(db, codigo):
    return db.execute(_CLIENTES + " WHERE c.idcliente = %s", (codigo,)).fetchone()


def insertar_cliente(db, cliente):
    return db.execute("""
        INSERT INTO cliente (nombre, apellido, razonsocial, tipodocumento,
                             numerodocumento, direccion, idlocalidad, descuento)
        VALUES (%(nombre)s, %(apellido)s, %(razon_social)s, %(tipo_documento)s,
                %(numero_documento)s, %(direccion)s, %(id_localidad)s, 10)
        RETURNING idcliente
    """, cliente.model_dump()).fetchone()["idcliente"]


def actualizar_cliente(db, codigo, cliente):
    return db.execute("""
        UPDATE cliente SET nombre = %(nombre)s, apellido = %(apellido)s,
            razonsocial = %(razon_social)s, tipodocumento = %(tipo_documento)s,
            numerodocumento = %(numero_documento)s, direccion = %(direccion)s,
            idlocalidad = %(id_localidad)s
        WHERE idcliente = %(codigo)s RETURNING idcliente
    """, dict(cliente.model_dump(), codigo=codigo)).fetchone()


def bloquear_cliente(db, codigo):
    return db.execute(
        "SELECT idcliente FROM cliente WHERE idcliente = %s FOR UPDATE", (codigo,)
    ).fetchone()


def eliminar_cliente(db, codigo):
    db.execute("DELETE FROM cliente WHERE idcliente = %s", (codigo,))


def guardar_socio(db, codigo):
    db.execute(
        "INSERT INTO socio_club (idcliente) VALUES (%s) ON CONFLICT DO NOTHING",
        (codigo,),
    )


def guardar_distribuidor(db, codigo, cliente):
    db.execute("""
        INSERT INTO distribuidor (idcliente, zonacobertura, numerohabilitacion)
        VALUES (%s, %s, %s)
        ON CONFLICT (idcliente) DO UPDATE SET zonacobertura = EXCLUDED.zonacobertura,
                                            numerohabilitacion = EXCLUDED.numerohabilitacion
    """, (codigo, cliente.zona_cobertura, cliente.numero_habilitacion))


def guardar_exportador(db, codigo, cliente):
    db.execute("""
        INSERT INTO exportador (idcliente, paisdestinoprincipal) VALUES (%s, %s)
        ON CONFLICT (idcliente) DO UPDATE SET paisdestinoprincipal = EXCLUDED.paisdestinoprincipal
    """, (codigo, cliente.pais_destino_principal))


def quitar_socio(db, codigo):
    db.execute("DELETE FROM socio_club WHERE idcliente = %s", (codigo,))


def quitar_distribuidor(db, codigo):
    db.execute("DELETE FROM distribuidor WHERE idcliente = %s", (codigo,))


def quitar_exportador(db, codigo):
    db.execute("DELETE FROM exportador WHERE idcliente = %s", (codigo,))


def actualizar_descuento(db, codigo):
    db.execute(
        "UPDATE cliente SET descuento = fn_descuento_cliente(idcliente) WHERE idcliente = %s",
        (codigo,),
    )


def insertar_venta(db, venta):
    db.execute("""
        INSERT INTO comprobante (numero, idcliente, idsalaventa, fecha,
                                  subtotal, descuento, total)
        VALUES (%s, %s, %s, COALESCE(%s, CURRENT_DATE), 0, 0, 0)
    """, (venta.numero, venta.id_cliente, venta.id_sala, venta.fecha))


def insertar_renglon_venta(db, numero, renglon):
    return db.execute("""
        INSERT INTO renglon_comprobante
            (numerocomprobante, codigovino, cantidad, preciounitario,
             descuento, subtotalrenglon)
        SELECT %s, v.codigovino, %s, v.precio, 10, 0
        FROM vino v WHERE v.codigovino = %s
        RETURNING codigovino
    """, (numero, renglon.cantidad, renglon.codigo_vino)).fetchone()


def detalle_venta(db, numero):
    return db.execute("""
        SELECT c.numero, c.fecha, c.idcliente AS id_cliente, c.idsalaventa AS id_sala,
               c.subtotal, c.descuento, c.total,
               COALESCE(r.renglones, '[]'::jsonb) AS renglones
        FROM comprobante c
        LEFT JOIN LATERAL (
            SELECT jsonb_agg(jsonb_build_object(
                'codigo_vino', rc.codigovino, 'cantidad', rc.cantidad,
                'precio_unitario', rc.preciounitario::text,
                'descuento', rc.descuento::text, 'subtotal', rc.subtotalrenglon::text
            ) ORDER BY rc.codigovino) AS renglones
            FROM renglon_comprobante rc WHERE rc.numerocomprobante = c.numero
        ) r ON true
        WHERE c.numero = %s
    """, (numero,)).fetchone()


def insertar_transferencia(db, datos):
    return db.execute("""
        INSERT INTO transferencia (numerosolicitud, idsalaventa) VALUES (%s, %s)
        RETURNING numerosolicitud AS numero, idsalaventa AS id_sala,
                  fechaconfeccion AS fecha, estado
    """, (datos.numero, datos.id_sala)).fetchone()


def bloquear_transferencia(db, numero):
    return db.execute(
        "SELECT numerosolicitud FROM transferencia WHERE numerosolicitud = %s FOR UPDATE",
        (numero,),
    ).fetchone()


def insertar_renglon_transferencia(db, numero, renglon):
    return db.execute("""
        INSERT INTO incluye (numerosolicitud, codigovino, cantidad)
        VALUES (%s, %s, %s)
        RETURNING numerosolicitud AS numero, codigovino AS codigo_vino, cantidad
    """, (numero, renglon.codigo_vino, renglon.cantidad)).fetchone()


def terminar_transferencia(db, numero):
    return db.execute("""
        UPDATE transferencia SET estado = 'terminado' WHERE numerosolicitud = %s
        RETURNING numerosolicitud AS numero, estado
    """, (numero,)).fetchone()


def procesar_transferencia(db, numero):
    db.execute("CALL sp_procesar_transferencia(%s)", (numero,))


def detalle_transferencia(db, numero):
    return db.execute("""
        SELECT numerosolicitud AS numero, estado FROM transferencia WHERE numerosolicitud = %s
    """, (numero,)).fetchone()


def insertar_ingreso(db, datos):
    return db.execute("""
        INSERT INTO ingresos (codigoingreso, cuitbodega, codigotransporte, iddeposito, fecha)
        VALUES (%s, %s, %s, 1, COALESCE(%s, CURRENT_DATE))
        RETURNING codigoingreso AS codigo, cuitbodega AS cuit_bodega,
                  codigotransporte AS codigo_transporte, iddeposito AS id_deposito,
                  fecha, estado
    """, (datos.codigo, datos.cuit_bodega, datos.codigo_transporte, datos.fecha)).fetchone()


def bloquear_ingreso(db, codigo):
    return db.execute(
        "SELECT codigoingreso FROM ingresos WHERE codigoingreso = %s FOR UPDATE", (codigo,)
    ).fetchone()


def insertar_renglon_ingreso(db, codigo, renglon):
    return db.execute("""
        INSERT INTO contiene (codigoingreso, codigovino, cantidadbotellas)
        VALUES (%s, %s, %s)
        RETURNING codigoingreso AS codigo, codigovino AS codigo_vino,
                  cantidadbotellas AS cantidad
    """, (codigo, renglon.codigo_vino, renglon.cantidad)).fetchone()


def terminar_ingreso(db, codigo):
    return db.execute("""
        UPDATE ingresos SET estado = 'terminado' WHERE codigoingreso = %s
        RETURNING codigoingreso AS codigo, estado
    """, (codigo,)).fetchone()


def procesar_ingreso(db, codigo):
    db.execute("CALL sp_procesar_ingreso(%s)", (codigo,))


def detalle_ingreso(db, codigo):
    return db.execute("""
        SELECT codigoingreso AS codigo, estado FROM ingresos WHERE codigoingreso = %s
    """, (codigo,)).fetchone()


def top_vinos(db, limite, offset):
    # S1. Ranking de botellas vendidas.
    return db.execute("""
        WITH ventas AS (
            SELECT codigovino, SUM(cantidad) AS botellas
            FROM renglon_comprobante GROUP BY codigovino
            ORDER BY botellas DESC, codigovino LIMIT 10
        )
        SELECT v.codigovino AS codigo, v.nombre, ventas.botellas
        FROM ventas JOIN vino v USING (codigovino)
        ORDER BY ventas.botellas DESC, v.codigovino LIMIT %s OFFSET %s
    """, (limite, offset)).fetchall()


def vinos_sin_stock(db, sala, limite, offset):
    return db.execute("""
        SELECT v.codigovino AS codigo, v.nombre, a.cantidadstock AS stock_deposito
        FROM almacena a
        JOIN vino v USING (codigovino)
        JOIN sala_venta s ON s.idsalaventa = %s
        LEFT JOIN posee p ON p.codigovino = v.codigovino AND p.idsalaventa = s.idsalaventa
        WHERE a.iddeposito = 1 AND a.cantidadstock > 0 AND COALESCE(p.cantidadstock, 0) = 0
        ORDER BY v.codigovino LIMIT %s OFFSET %s
    """, (sala, limite, offset)).fetchall()


def transportista_activo(db, limite, offset):
    return db.execute("""
        WITH actividad AS (
            SELECT e.codigotransporte, e.razonsocial, COUNT(*) AS envios
            FROM ingresos i JOIN empresas_transporte e USING (codigotransporte)
            WHERE i.estado = 'procesado'
              AND i.fecha BETWEEN CURRENT_DATE - INTERVAL '1 month' AND CURRENT_DATE
            GROUP BY e.codigotransporte, e.razonsocial
        )
        SELECT codigotransporte AS codigo, razonsocial AS razon_social, envios
        FROM actividad WHERE envios = (SELECT MAX(envios) FROM actividad)
        ORDER BY codigotransporte LIMIT %s OFFSET %s
    """, (limite, offset)).fetchall()


def ventas_por_sala(db, limite, offset):
    return db.execute("""
        SELECT idsalaventa AS id_sala, SUM(total) AS ventas
        FROM comprobante
        WHERE fecha BETWEEN CURRENT_DATE - INTERVAL '3 months' AND CURRENT_DATE
        GROUP BY idsalaventa ORDER BY ventas DESC, idsalaventa LIMIT %s OFFSET %s
    """, (limite, offset)).fetchall()
