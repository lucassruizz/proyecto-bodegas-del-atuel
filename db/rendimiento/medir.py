"""Ejecuta la etapa 4 sobre una base de pruebas recién cargada."""

import argparse
import json
import statistics
from pathlib import Path

import psycopg
from psycopg import sql

CARPETA = Path(__file__).resolve().parent
CONSULTAS = ("S3", "S8", "S12a", "S12b", "S5", "S1")
REPETICIONES = 7
EXPLAIN = "EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) "
TABLAS = ("comprobante", "renglon_comprobante")


def medir(cursor, consulta):
    cursor.execute(EXPLAIN + consulta)
    return cursor.fetchone()[0][0]


def medir_consultas(cursor, consultas):
    resultados = {}
    for codigo, consulta in consultas.items():
        cursor.execute(consulta)
        filas = cursor.fetchall()
        muestras = [medir(cursor, consulta) for _ in range(REPETICIONES)]
        mediano = sorted(muestras, key=lambda plan: plan["Execution Time"])[REPETICIONES // 2]
        resultados[codigo] = (filas, mediano, [p["Execution Time"] for p in muestras])
    return resultados


def preparar_escritura(cursor, esquema, tabla):
    destino = sql.Identifier(esquema, tabla)
    cursor.execute(sql.SQL(
        "CREATE TABLE {} (LIKE {} INCLUDING CONSTRAINTS INCLUDING INDEXES)"
    ).format(destino, sql.Identifier("public", tabla)))
    return destino


def medir_escritura(cursor, destinos):
    resultados = {}
    for tabla in TABLAS:
        tiempos = {"antes": [], "despues": []}
        origen = sql.Identifier("public", tabla)
        for repeticion in range(REPETICIONES):
            orden = list(tiempos)
            if repeticion % 2:
                orden.reverse()
            for variante in orden:
                destino = destinos[variante][tabla]
                cursor.execute(sql.SQL("TRUNCATE {}").format(destino))
                cursor.execute(sql.SQL(
                    "EXPLAIN (ANALYZE, BUFFERS, WAL, FORMAT JSON) "
                    "INSERT INTO {} SELECT * FROM {} ORDER BY {}"
                ).format(destino, origen, sql.SQL(
                    "numero" if tabla == "comprobante" else "numeroComprobante, codigoVino"
                )))
                tiempos[variante].append(cursor.fetchone()[0][0])
        resultados[tabla] = {}
        for variante, muestras in tiempos.items():
            campo = "Execution Time"
            mediano = sorted(muestras, key=lambda plan: plan[campo])[REPETICIONES // 2]
            resultados[tabla][variante] = {
                "ms": [p[campo] for p in muestras], "plan_mediano": mediano
            }
    return resultados


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("salida", type=Path, help="Directorio donde se guardan los planes")
    args = parser.parse_args()
    consultas = {c: (CARPETA / f"{c}.sql").read_text(encoding="utf-8") for c in CONSULTAS}
    migracion = CARPETA.parent / "migrations" / "008_indices.sql"

    with psycopg.connect() as conn, conn.cursor() as cursor:
        cursor.execute("SET LOCAL search_path TO public")
        cursor.execute("SELECT version(), current_setting('shared_buffers'), current_setting('work_mem')")
        servidor, shared_buffers, work_mem = cursor.fetchone()
        cursor.execute("""
            SELECT t.relname, i.relname FROM pg_index x
            JOIN pg_class t ON t.oid = x.indrelid
            JOIN pg_class i ON i.oid = x.indexrelid
            WHERE t.relnamespace = 'public'::regnamespace
              AND NOT EXISTS (SELECT 1 FROM pg_constraint c
                              WHERE c.conindid = i.oid AND c.contype IN ('p', 'u'))
        """)
        adicionales = cursor.fetchall()
        if adicionales:
            raise RuntimeError(f"La medición inicial exige solo índices de PK y UNIQUE: {adicionales}")

        # VACUUM debe ejecutarse fuera de la transacción. Se hace en el mismo
        # estado de carga que ambas rondas, para igualar el mapa de visibilidad.
        conn.commit()
        conn.autocommit = True
        cursor.execute("VACUUM (ANALYZE) public.comprobante, public.renglon_comprobante")
        conn.autocommit = False
        cursor.execute("SET LOCAL search_path TO public")
        cursor.execute("ANALYZE")
        cursor.execute("SELECT (SELECT count(*) FROM comprobante), (SELECT count(*) FROM renglon_comprobante)")
        cantidades = dict(zip(TABLAS, cursor.fetchone()))
        if any(n <= 100_000 for n in cantidades.values()):
            raise RuntimeError(f"Se requiere el dataset completo de la etapa 3: {cantidades}")
        antes = medir_consultas(cursor, consultas)
        cursor.execute("""
            CREATE INDEX idx_prueba_fecha_brin
            ON comprobante USING brin (fecha) WITH (pages_per_range = 32)
        """)
        cursor.execute("ANALYZE comprobante")
        descarte = medir_consultas(cursor, {"S8": consultas["S8"]})
        if descarte["S8"][0] != antes["S8"][0]:
            raise RuntimeError("El resultado cambió con el BRIN de prueba")
        cursor.execute("SELECT pg_relation_size('idx_prueba_fecha_brin')")
        bytes_descartado = cursor.fetchone()[0]
        cursor.execute("DROP INDEX idx_prueba_fecha_brin")

        cursor.execute("CREATE SCHEMA medicion_antes")
        destinos = {"antes": {t: preparar_escritura(cursor, "medicion_antes", t) for t in TABLAS}}
        cursor.execute(migracion.read_text(encoding="utf-8"))
        cursor.execute("ANALYZE")
        despues = medir_consultas(cursor, consultas)
        for codigo in consultas:
            if antes[codigo][0] != despues[codigo][0]:
                raise RuntimeError(f"El resultado cambió para {codigo}")

        cursor.execute("CREATE SCHEMA medicion_despues")
        destinos["despues"] = {t: preparar_escritura(cursor, "medicion_despues", t) for t in TABLAS}
        escritura = medir_escritura(cursor, destinos)
        cursor.execute("""
            SELECT indexname, pg_relation_size(('public.' || quote_ident(indexname))::regclass)
            FROM pg_indexes WHERE schemaname = 'public' AND indexname LIKE 'idx_%' ORDER BY indexname
        """)
        tamanos = dict(cursor.fetchall())
        cursor.execute("DROP SCHEMA medicion_antes CASCADE")
        cursor.execute("DROP SCHEMA medicion_despues CASCADE")

    args.salida.mkdir(parents=True, exist_ok=True)
    resumen = {"servidor": servidor, "shared_buffers": shared_buffers, "work_mem": work_mem,
               "filas_dataset": cantidades, "repeticiones": REPETICIONES, "bytes_indices": tamanos,
               "bytes_indice_descartado": bytes_descartado, "consultas": {}, "escritura": {}}
    for variante, resultados in (("antes", antes), ("despues", despues), ("descarte", descarte)):
        for codigo, (filas, plan, tiempos) in resultados.items():
            resumen["consultas"].setdefault(codigo, {})[variante] = {
                "ms": tiempos, "mediana_ms": statistics.median(tiempos), "filas_resultado": len(filas)
            }
            guardar(args.salida / f"{codigo}_{variante}.json", plan)
    for tabla, variantes in escritura.items():
        resumen["escritura"][tabla] = {}
        for variante, muestra in variantes.items():
            resumen["escritura"][tabla][variante] = {
                "ms": muestra["ms"], "mediana_ms": statistics.median(muestra["ms"])
            }
            guardar(args.salida / f"carga_{tabla}_{variante}.json", muestra["plan_mediano"])
    guardar(args.salida / "resumen.json", resumen)
    print(f"Mediciones guardadas en {args.salida}")


def guardar(ruta, datos):
    ruta.write_text(json.dumps(datos, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
