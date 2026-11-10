"""Carga histórica reproducible para las migraciones 001 a 005 de etapa-2.

Python 3.10+. Instalar: pip install -r requirements.txt
Configurar DB_NAME, DB_USER, DB_PASSWORD y opcionalmente DB_HOST/DB_PORT.
Ejecutar sobre una base VACÍA ya migrada. Ver README_carga.md.
"""
from __future__ import annotations

import csv
import json
import os
import random
import time
from datetime import date, timedelta
from pathlib import Path

import psycopg
from psycopg import sql
from faker import Faker

SEMILLA = 2026
FECHA_BASE = date(2026, 11, 7)  # Fija: no depende del día de ejecución.
RUTA_BASE = Path(__file__).resolve().parent
RUTA_CATALOGOS = RUTA_BASE / "csv"
TAMANO_LOTE = 2000
TABLAS_A_CONTROLAR = tuple("localidad encargado_regional sala_venta empleado departamento finca cepa parcela bodega lote analisis_calidad vino componen maridaje tienen auditoria_precio cliente socio_club distribuidor exportador permisos comprobante renglon_comprobante empresas_transporte alcanza deposito almacena posee ingresos contiene transferencia incluye".split())


def obtener_configuracion():
    faltantes = [v for v in ("DB_NAME", "DB_USER", "DB_PASSWORD") if not os.getenv(v)]
    if faltantes:
        raise RuntimeError("Faltan variables: " + ", ".join(faltantes))
    return dict(host=os.getenv("DB_HOST", "localhost"), port=os.getenv("DB_PORT", "5432"),
                dbname=os.environ["DB_NAME"], user=os.environ["DB_USER"], password=os.environ["DB_PASSWORD"])


def conectar():
    return psycopg.connect(**obtener_configuracion())


def insertar_por_lotes(cursor, sentencia, filas, tamano_lote=TAMANO_LOTE):
    if tamano_lote < 1:
        raise ValueError("El tamaño del lote debe ser positivo")
    bloque, total = [], 0
    for fila in filas:
        bloque.append(fila)
        if len(bloque) == tamano_lote:
            cursor.executemany(sentencia, bloque)
            total += len(bloque)
            bloque = []
    if bloque:
        cursor.executemany(sentencia, bloque)
        total += len(bloque)
    return total


def medir_tiempo(etiqueta, operacion):
    inicio = time.perf_counter()
    resultado = operacion()
    print(f"{etiqueta}: {time.perf_counter() - inicio:.3f} s")
    return resultado


def leer_catalogo(nombre_archivo):
    with (RUTA_CATALOGOS / nombre_archivo).open(encoding="utf-8-sig", newline="") as archivo:
        return list(csv.DictReader(archivo))


def copiar(cursor, tabla, columnas, filas):
    sentencia = sql.SQL("COPY {} ({}) FROM STDIN").format(
        sql.Identifier(tabla), sql.SQL(",").join(map(sql.Identifier, columnas.lower().split())))
    with cursor.copy(sentencia) as copia:
        for fila in filas:
            copia.write_row(fila)


def insertar_id(cursor, tabla, columnas, valores, clave):
    cursor.execute(sql.SQL("INSERT INTO {} ({}) VALUES ({}) RETURNING {}").format(
        sql.Identifier(tabla), sql.SQL(",").join(map(sql.Identifier, columnas.lower().split())),
        sql.SQL(",").join(sql.Placeholder() for _ in valores), sql.Identifier(clave.lower())), valores)
    return cursor.fetchone()[0]


def cargar_catalogos(cursor):
    resultado = {}
    for tabla, archivo, columnas, clave in (
        ("departamento", "departamentos.csv", "nombredepartamento provincia", "iddepartamento"),
        ("localidad", "localidades_mendoza.csv", "nombre provincia codigopostal", "idlocalidad"),
        ("cepa", "cepas.csv", "nombre tipo", "idcepa"),
        ("maridaje", "maridajes.csv", "nombre temperatura", "idmaridaje"),
    ):
        resultado[tabla] = [insertar_id(cursor, tabla, columnas, [r[c] for c in columnas.split()], clave)
                            for r in leer_catalogo(archivo)]
    resultado["tipos"] = [r["nombre"] for r in leer_catalogo("tipos_vino.csv")]
    copiar(cursor, "encargado_regional", "datosencargado idlocalidad",
           ((f"Responsable regional {i}", i) for i in resultado["localidad"]))
    return resultado


def generar_datos_base(cursor, catalogos):
    rng = random.Random(SEMILLA)
    fake = Faker("es_AR")
    fake.seed_instance(SEMILLA)
    loc, dep, cepas, mar = (catalogos[t] for t in ("localidad", "departamento", "cepa", "maridaje"))
    salas = [insertar_id(cursor, "sala_venta", "calle numero diacierresemanal idlocalidad",
                        (fake.street_name(), str(i+100), ("lunes", "miercoles", "domingo")[i % 3], loc[i % len(loc)]), "idsalaventa") for i in range(15)]
    copiar(cursor, "empleado", "cuit nombre fechaingresolaboral salario idsalaventa",
           ((str(20000000000+i), fake.name(), date(2015+i % 5, 1, 1), 900000+i*1000, salas[i % 15]) for i in range(90)))
    fincas = [insertar_id(cursor, "finca", "nombre superficietotal iddepartamento",
                         (f"Finca {i+1}", 100, dep[i % len(dep)]), "id") for i in range(60)]
    parcelas = [(f, p, 5, 2010, cepas[(j+p) % len(cepas)]) for j, f in enumerate(fincas) for p in range(1, 11)]
    copiar(cursor, "parcela", "idfinca numeroparcela superficie anioplantacion idcepa", parcelas)
    bodegas = [str(30000000000+i) for i in range(10)]
    copiar(cursor, "bodega", "cuit razonsocial domicilio", ((b, f"Bodega Atuel {i}", fake.address()) for i, b in enumerate(bodegas)))
    lotes = [(j*600+i+1, date(2022+j, 3, 15), rng.randint(20000, 40000), 2022+j, p[0], p[1], bodegas[i % 10])
             for j in range(5) for i, p in enumerate(parcelas)]
    copiar(cursor, "lote", "numero fechacosecha kiloscosechados campania idfinca numeroparcela cuitbodega", lotes)
    copiar(cursor, "analisis_calidad", "fecha gradobrix ph acideztotal numerolote",
           ((l[1]+timedelta(days=d), 23, "3.50", 6, l[0]) for l in lotes for d in (0, 1)))
    vinos = [(v, f"Vino Atuel {v}", 750, 14, catalogos["tipos"][(v-1) % 4], 2022, 5000+v*10, bodegas[(v-1) % 10]) for v in range(1, 301)]
    copiar(cursor, "vino", "codigovino nombre volumen graduacionalcoholica tipo anada precio cuitbodega", vinos)
    copiar(cursor, "componen", "codigovino idcepa porcentaje", ((v[0], cepas[(v[0]-1) % 7] if v[4] in ("tinto", "rosado") else cepas[7+(v[0]-1) % 5], 100) for v in vinos))
    copiar(cursor, "tienen", "codigovino idmaridaje", ((v[0], mar[(v[0]-1) % len(mar)]) for v in vinos))
    copiar(cursor, "auditoria_precio", "codigovino precioanterior precionuevo fechahora usuario",
           ((v[0], v[6]-100, v[6], "2022-06-01 12:00:00", "carga_historica") for v in vinos))
    clientes = []
    for i in range(20000):
        descuento = (10, 20, 30)[i % 3]
        c = insertar_id(cursor, "cliente", "apellido nombre tipodocumento numerodocumento direccion idlocalidad fechaalta descuento",
                        (fake.last_name(), fake.first_name(), "DNI", str(10000000+i), fake.address(), loc[i % len(loc)], date(2020, 1, 1), descuento), "idcliente")
        clientes.append(c)
    copiar(cursor, "socio_club", "idcliente", ((c,) for i, c in enumerate(clientes) if i % 3 == 0))
    copiar(cursor, "distribuidor", "idcliente zonacobertura numerohabilitacion", ((c, "Mendoza", f"HAB-{c}") for i, c in enumerate(clientes) if i % 3 == 1))
    copiar(cursor, "exportador", "idcliente paisdestinoprincipal", ((c, "Chile") for i, c in enumerate(clientes) if i % 3 == 2))
    copiar(cursor, "permisos", "codigo fechaemision fechavencimiento idexportador",
           ((f"EXP-{c}-{j}", date(2021, 1, 1), date(2030, 1, 1), c) for i, c in enumerate(clientes) if i % 3 == 2 for j in range(1+(i % 4))))
    copiar(cursor, "empresas_transporte", "codigotransporte razonsocial cuit email telefono domicilio",
           ((i, f"Transporte {i}", str(33000000000+i), f"contacto{i}@example.com", "2604000000", fake.address()) for i in range(1, 11)))
    copiar(cursor, "alcanza", "codigotransporte idlocalidad", ((i, l) for i in range(1, 11) for l in loc))
    cursor.execute("INSERT INTO deposito VALUES (1)")
    # 600 ingresos, diez vinos de una misma bodega por ingreso.
    copiar(cursor, "ingresos", "codigoingreso fecha estado cuitbodega codigotransporte iddeposito",
           ((i, date(2022, 6, 2), "procesado", bodegas[(i-1) % 10], (i-1) % 10+1, 1) for i in range(1, 601)))
    copiar(cursor, "contiene", "codigoingreso codigovino cantidadbotellas",
           ((i, ((i-1)//10 % 3)*100+(i-1) % 10+1+j*10, 10000) for i in range(1, 601) for j in range(10)))
    # Cada sala recibe todos los vinos en 60 transferencias de 5 renglones.
    copiar(cursor, "transferencia", "numerosolicitud estado fechaconfeccion idsalaventa",
           ((s*60+k+1, "procesado", date(2022, 6, 3), sala) for s, sala in enumerate(salas) for k in range(60)))
    copiar(cursor, "incluye", "numerosolicitud codigovino cantidad",
           ((s*60+k+1, k*5+j+1, 10000) for s in range(15) for k in range(60) for j in range(5)))
    copiar(cursor, "comprobante", "numero fecha idcliente idsalaventa subtotal descuento total",
           ((i+1, date(2022, 6, 4)+timedelta(days=(i*1618)//150000), clientes[i % 20000], salas[i % 15], 0, 0, 0) for i in range(150000)))
    def renglones():
        for i in range(150000):
            # 100.000 x 3 + 50.000 x 4 = 500.000; sin vino repetido.
            for v in rng.sample(range(1, 301), 4 if i < 50000 else 3):
                yield i+1, v, rng.randint(1, 3), 5000+v*10, (10, 20, 30)[(i % 20000) % 3], 0
    copiar(cursor, "renglon_comprobante", "numerocomprobante codigovino cantidad preciounitario descuento subtotalrenglon", renglones())
    # Cálculos derivados en SQL: misma fórmula de los triggers de etapa-2.
    cursor.execute("""
        UPDATE renglon_comprobante SET subtotalRenglon =
          cantidad * precioUnitario - ROUND(cantidad * precioUnitario * descuento / 100.0, 2);
        UPDATE comprobante c SET subtotal=r.bruto, descuento=r.rebaja, total=r.neto
        FROM (SELECT numeroComprobante, SUM(cantidad*precioUnitario) bruto,
          SUM(ROUND(cantidad*precioUnitario*descuento/100.0,2)) rebaja,
          SUM(subtotalRenglon) neto FROM renglon_comprobante GROUP BY numeroComprobante) r
        WHERE c.numero=r.numeroComprobante;
        INSERT INTO almacena SELECT codigoVino, 1, SUM(cantidadBotellas) FROM contiene GROUP BY codigoVino;
        UPDATE almacena a SET cantidadStock=a.cantidadStock-r.cantidad
        FROM (SELECT codigoVino, SUM(cantidad) cantidad FROM incluye GROUP BY codigoVino) r WHERE a.codigoVino=r.codigoVino;
        INSERT INTO posee SELECT t.idSalaVenta, i.codigoVino, SUM(i.cantidad)
          FROM transferencia t JOIN incluye i USING(numeroSolicitud) GROUP BY t.idSalaVenta,i.codigoVino;
        UPDATE posee p SET cantidadStock=p.cantidadStock-r.cantidad
        FROM (SELECT c.idSalaVenta,r.codigoVino,SUM(r.cantidad) cantidad FROM comprobante c
          JOIN renglon_comprobante r ON c.numero=r.numeroComprobante GROUP BY c.idSalaVenta,r.codigoVino) r
        WHERE p.idSalaVenta=r.idSalaVenta AND p.codigoVino=r.codigoVino;
    """)


def exigir_cero(cursor, nombre, consulta):
    cursor.execute(consulta)
    cantidad = cursor.fetchone()[0]
    if cantidad:
        raise RuntimeError(f"{nombre}: {cantidad} inconsistencias; se revierte toda la carga")
    print(f"Control OK: {nombre}")


def validar_stock_negativo(cursor):
    for tabla in ("almacena", "posee"):
        exigir_cero(cursor, f"stock {tabla}", f"SELECT count(*) FROM {tabla} WHERE cantidadStock<0")


def validar_carga(cursor):
    validar_stock_negativo(cursor)
    controles = {
        "composición": "SELECT count(*) FROM (SELECT v.codigoVino FROM vino v LEFT JOIN componen c USING(codigoVino) GROUP BY v.codigoVino HAVING COALESCE(SUM(porcentaje),0)<>100) x",
        "subtipos y descuentos": "SELECT count(*) FROM cliente c WHERE descuento<>fn_descuento_cliente(c.idCliente)",
        "totales": "SELECT count(*) FROM comprobante c JOIN (SELECT numeroComprobante, SUM(cantidad*precioUnitario) bruto,SUM(ROUND(cantidad*precioUnitario*descuento/100.0,2)) rebaja,SUM(subtotalRenglon) neto FROM renglon_comprobante GROUP BY numeroComprobante) r ON c.numero=r.numeroComprobante WHERE (c.subtotal,c.descuento,c.total) IS DISTINCT FROM (r.bruto,r.rebaja,r.neto)",
        "renglones": "SELECT count(*) FROM renglon_comprobante r JOIN comprobante c ON c.numero=r.numeroComprobante JOIN cliente cl USING(idCliente) WHERE r.descuento<>cl.descuento OR r.subtotalRenglon<>r.cantidad*r.precioUnitario-ROUND(r.cantidad*r.precioUnitario*r.descuento/100.0,2)",
        "fechas de venta": "SELECT count(*) FROM comprobante c JOIN cliente cl USING(idCliente) WHERE c.fecha<cl.fechaAlta OR c.fecha<DATE '2022-06-03' OR c.fecha>DATE '2026-11-07'",
        "saldo depósito": "SELECT count(*) FROM almacena a LEFT JOIN (SELECT codigoVino,SUM(cantidadBotellas) n FROM contiene JOIN ingresos USING(codigoIngreso) WHERE estado='procesado' GROUP BY codigoVino) e USING(codigoVino) LEFT JOIN (SELECT codigoVino,SUM(cantidad) n FROM incluye JOIN transferencia USING(numeroSolicitud) WHERE estado='procesado' GROUP BY codigoVino) t USING(codigoVino) WHERE a.cantidadStock<>COALESCE(e.n,0)-COALESCE(t.n,0)",
        "saldo salas": "SELECT count(*) FROM posee p LEFT JOIN (SELECT idSalaVenta,codigoVino,SUM(cantidad) n FROM incluye JOIN transferencia USING(numeroSolicitud) WHERE estado='procesado' GROUP BY idSalaVenta,codigoVino) t USING(idSalaVenta,codigoVino) LEFT JOIN (SELECT idSalaVenta,codigoVino,SUM(cantidad) n FROM renglon_comprobante r JOIN comprobante c ON c.numero=r.numeroComprobante GROUP BY idSalaVenta,codigoVino) v USING(idSalaVenta,codigoVino) WHERE p.cantidadStock<>COALESCE(t.n,0)-COALESCE(v.n,0)",
        "análisis y cosechas": "SELECT count(*) FROM analisis_calidad a JOIN lote l ON l.numero=a.numeroLote WHERE a.fecha<l.fechaCosecha OR EXTRACT(YEAR FROM l.fechaCosecha)<>l.campania",
        "bodega de ingresos": "SELECT count(*) FROM contiene c JOIN ingresos i USING(codigoIngreso) JOIN vino v USING(codigoVino) WHERE i.cuitBodega<>v.cuitBodega",
        "encargados": "SELECT count(*) FROM localidad l LEFT JOIN encargado_regional e USING(idLocalidad) WHERE e.idEncargado IS NULL",
    }
    for nombre, consulta in controles.items():
        exigir_cero(cursor, nombre, consulta)
    # FK activas durante toda la carga: no hay filas huérfanas. Forzar también
    # cualquier constraint diferida antes de confirmar.
    cursor.execute("SET CONSTRAINTS ALL IMMEDIATE")


def informar_conteos(cursor):
    conteos = {}
    for tabla in TABLAS_A_CONTROLAR:
        cursor.execute(sql.SQL("SELECT count(*) FROM {}").format(sql.Identifier(tabla)))
        conteos[tabla] = cursor.fetchone()[0]
        print(f"{tabla}: {conteos[tabla]:,}")
    if min(conteos.values()) < 1 or sum(n > 10000 for n in conteos.values()) < 3 or max(conteos.values()) <= 100000:
        raise RuntimeError("No se cumplen los volúmenes del enunciado")
    return conteos


def comparar_inserciones(cursor):
    cursor.execute("CREATE TEMP TABLE prueba_carga (numero integer) ON COMMIT DROP")
    filas = [(i,) for i in range(2000)]
    tiempos = {}
    for modo in ("fila_por_fila", "por_lotes"):
        inicio = time.perf_counter()
        if modo == "fila_por_fila":
            for fila in filas:
                cursor.execute("INSERT INTO prueba_carga VALUES (%s)", fila)
        else:
            insertar_por_lotes(cursor, "INSERT INTO prueba_carga VALUES (%s)", filas)
        tiempos[modo] = time.perf_counter()-inicio
        cursor.execute("TRUNCATE prueba_carga")
    return tiempos


def main():
    inicio = time.perf_counter()
    with conectar() as conexion:
        with conexion.cursor() as cursor:
            cursor.execute("SET LOCAL search_path TO public")
            # Impide escrituras concurrentes. No se borra ni trunca ningún dato.
            cursor.execute(sql.SQL("LOCK TABLE {} IN ACCESS EXCLUSIVE MODE").format(sql.SQL(",").join(map(sql.Identifier, TABLAS_A_CONTROLAR))))
            for tabla in TABLAS_A_CONTROLAR:
                cursor.execute(sql.SQL("SELECT EXISTS(SELECT 1 FROM {})").format(sql.Identifier(tabla)))
                if cursor.fetchone()[0]:
                    raise RuntimeError(f"La tabla {tabla} no está vacía. Usar otra base vacía ya migrada.")
            tiempos = comparar_inserciones(cursor)
            # Sólo triggers de usuario; FK, CHECK y UNIQUE permanecen activos.
            # Requiere propietario. ALTER TABLE es transaccional: un error restaura
            # automáticamente su estado. No se usa session_replication_role.
            cursor.execute("""SELECT c.relname,t.tgname,t.tgenabled FROM pg_trigger t
              JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace
              WHERE n.nspname='public' AND NOT t.tgisinternal AND c.relname=ANY(%s)""", (list(TABLAS_A_CONTROLAR),))
            triggers = cursor.fetchall()
            if any(estado != "O" for _, _, estado in triggers):
                raise RuntimeError("Se requieren triggers habilitados normalmente antes de cargar")
            for tabla in TABLAS_A_CONTROLAR:
                cursor.execute(sql.SQL("ALTER TABLE {} DISABLE TRIGGER USER").format(sql.Identifier(tabla)))
            catalogos = cargar_catalogos(cursor)
            generar_datos_base(cursor, catalogos)
            validar_carga(cursor)
            conteos = informar_conteos(cursor)
            for tabla in TABLAS_A_CONTROLAR:
                cursor.execute(sql.SQL("ALTER TABLE {} ENABLE TRIGGER USER").format(sql.Identifier(tabla)))
            # Habilitar no reproduce eventos históricos: por eso se valida antes.
    reporte = dict(semilla=SEMILLA, fecha_base=str(FECHA_BASE), conteos=conteos,
                   comparacion_2000_filas_segundos=tiempos, segundos_totales=time.perf_counter()-inicio,
                   controles="OK; FK/CHECK/UNIQUE activos durante toda la carga")
    ruta = RUTA_BASE / "reporte_carga.json"
    ruta.write_text(json.dumps(reporte, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Carga confirmada. Reporte: {ruta}")


if __name__ == "__main__":
    main()
