import os
import time
from decimal import Decimal

import httpx
import psycopg
import pytest


@pytest.fixture(scope="session")
def api():
    with httpx.Client(base_url=os.getenv("TEST_API_URL", "http://api:8000")) as client:
        for _ in range(25):
            try:
                if client.get("/salud").status_code == 200:
                    break
            except httpx.ConnectError:
                pass
            time.sleep(0.4)
        else:
            pytest.fail("La API no quedó disponible")
        yield client


@pytest.fixture
def db():
    with psycopg.connect(
        host=os.environ["DB_HOST"], port=os.environ["DB_PORT"],
        dbname=os.environ["DB_NAME"], user=os.environ["DB_USER"],
        password=os.environ["DB_PASSWORD"], autocommit=True,
    ) as connection:
        yield connection


def verificar(respuesta, estado):
    assert respuesta.status_code == estado, respuesta.text
    if estado != 204:
        return respuesta.json()


def vino(codigo, **cambios):
    return {
        "codigo": codigo, "nombre": f"Vino {codigo}", "volumen": 750,
        "graduacion_alcoholica": 13, "tipo": "tinto", "anada": 2024, "precio": 120,
        "cuit_bodega": "20111111111",
        "composicion": [{"id_cepa": 1, "porcentaje": 100}], "maridajes": [1],
        **cambios,
    }


def cliente(documento, **cambios):
    return {
        "tipo": "socio_club", "tipo_documento": "DNI", "numero_documento": documento,
        "nombre": "Ana", "apellido": "Prueba", "direccion": "Mitre 100", "id_localidad": 1,
        **cambios,
    }


def test_salud_y_openapi(api):
    assert verificar(api.get("/salud"), 200)["base"] == "disponible"
    rutas = verificar(api.get("/openapi.json"), 200)["paths"]
    assert "post" in rutas["/transferencias/{numero}/procesar"]
    assert verificar(api.get("/vinos/99999"), 404)["detail"]


def test_catalogo_filtros_paginacion_y_detalle(api):
    filtro = {"tipo": "tinto", "cepa": 1, "bodega": "20111111111", "anada": 2024}
    assert [v["codigo"] for v in verificar(api.get("/vinos", params=filtro), 200)] == [1]
    assert verificar(api.get("/vinos", params={"limite": 1, "offset": 1}), 200)[0]["codigo"] == 2
    detalle = verificar(api.get("/vinos/1"), 200)
    assert Decimal(detalle["composicion"][0]["porcentaje"]) == 100
    assert detalle["maridajes"][0]["nombre"] == "Asado"


def test_inyeccion_sql_fallida(api):
    ataque = "tinto' OR '1'='1' --"
    antes = verificar(api.get("/vinos"), 200)
    respuesta = api.get("/vinos", params={"tipo": ataque})
    assert verificar(respuesta, 200) == []
    despues = verificar(api.get("/vinos"), 200)
    assert despues == antes and len(despues) >= 2
    print(f"\nGET {respuesta.request.url.raw_path.decode()}")
    print(f"HTTP {respuesta.status_code} {respuesta.text}")
    print(f"GET /vinos antes: {len(antes)} filas; después: {len(despues)} filas.")


def test_vino_actualiza_precio_y_audita_con_rol_limitado(api, db):
    datos = vino(110)
    verificar(api.post("/vinos", json=datos), 201)
    datos.pop("codigo")
    datos["precio"] = 175
    verificar(api.put("/vinos/110", json=datos), 200)
    fila = db.execute("""
        SELECT precioanterior, precionuevo, usuario,
               has_table_privilege(current_user, 'auditoria_precio', 'INSERT')
        FROM auditoria_precio WHERE codigovino = %s
    """, (110,)).fetchone()
    assert fila == (Decimal("120"), Decimal("175"), "bodega_api", False)
    assert db.execute("SELECT rolsuper FROM pg_roles WHERE rolname = current_user").fetchone() == (False,)
    verificar(api.delete("/vinos/110"), 409)  # La auditoría conserva su FK.
    assert verificar(api.get("/vinos/110"), 200)["composicion"]


def test_vino_baja_con_composicion(api):
    verificar(api.post("/vinos", json=vino(111)), 201)
    verificar(api.delete("/vinos/111"), 204)
    verificar(api.get("/vinos/111"), 404)


def test_precio_negativo_check_422(api):
    error = verificar(api.post("/vinos", json=vino(112, precio=-1)), 422)
    assert error["sqlstate"] == "23514"
    assert error["restriccion"] == "ck_vino_precio"
    verificar(api.get("/vinos/112"), 404)


def test_composicion_diferida_409_y_rollback(api):
    datos = vino(113, composicion=[{"id_cepa": 1, "porcentaje": 80}])
    error = verificar(api.post("/vinos", json=datos), 409)
    assert error["sqlstate"] == "P0001" and "RN-05" in error["detail"]
    verificar(api.get("/vinos/113"), 404)


def test_documento_duplicado_409(api):
    datos = cliente("32000010")
    verificar(api.post("/clientes", json=datos), 201)
    error = verificar(api.post("/clientes", json=datos), 409)
    assert error["sqlstate"] == "23505"


def test_clientes_tres_subtipos_y_crud(api):
    datos = cliente("32000011")
    socio = verificar(api.post("/clientes", json=datos), 201)
    codigo = socio["id_cliente"]
    assert Decimal(str(socio["descuento"])) == 10
    distribuidor = dict(datos, tipo="distribuidor", zona_cobertura="Sur", numero_habilitacion="D-1")
    assert Decimal(str(verificar(api.put(f"/clientes/{codigo}", json=distribuidor), 200)["descuento"])) == 20
    exportador = dict(datos, tipo="exportador", pais_destino_principal="Chile")
    assert Decimal(str(verificar(api.put(f"/clientes/{codigo}", json=exportador), 200)["descuento"])) == 30
    assert verificar(api.get(f"/clientes/{codigo}"), 200)["pais_destino_principal"] == "Chile"
    assert len(verificar(api.get("/clientes", params={"limite": 1}), 200)) == 1
    verificar(api.delete(f"/clientes/{codigo}"), 204)
    verificar(api.get(f"/clientes/{codigo}"), 404)


def test_venta_calculada_por_la_base(api):
    socio = verificar(api.post("/clientes", json=cliente("32000012")), 201)
    datos = {
        "numero": 121, "id_cliente": socio["id_cliente"], "id_sala": 1,
        "renglones": [{"codigo_vino": 1, "cantidad": 2}],
    }
    venta = verificar(api.post("/comprobantes", json=datos), 201)
    assert Decimal(str(venta["total"])) == 180
    assert verificar(api.get("/comprobantes/121"), 200) == venta


def test_stock_insuficiente_409_revierte_cabecera_renglones_y_stock(api):
    socio = verificar(api.post("/clientes", json=cliente("32000013")), 201)
    antes = verificar(api.get("/vinos/1"), 200)["stock_salas"]
    datos = {
        "numero": 122, "id_cliente": socio["id_cliente"], "id_sala": 1,
        "renglones": [{"codigo_vino": 1, "cantidad": 1}, {"codigo_vino": 2, "cantidad": 1000}],
    }
    error = verificar(api.post("/comprobantes", json=datos), 409)
    assert error["sqlstate"] == "P0001" and "Stock insuficiente" in error["detail"]
    verificar(api.get("/comprobantes/122"), 404)
    assert verificar(api.get("/vinos/1"), 200)["stock_salas"] == antes


def test_estado_invalido_409_y_transferencia_completa(api):
    verificar(api.post("/transferencias", json={"numero": 131, "id_sala": 1}), 201)
    error = verificar(api.post("/transferencias/131/procesar"), 409)
    assert error["sqlstate"] == "P0001" and "estar terminada" in error["detail"]
    datos = {"codigo_vino": 1, "cantidad": 3}
    verificar(api.post("/transferencias/131/renglones", json=datos), 201)
    verificar(api.post("/transferencias/131/terminar"), 200)
    error = verificar(api.post("/transferencias/131/renglones", json=datos), 409)
    assert error["sqlstate"] == "P0001" and "no confeccionada" in error["detail"]
    antes = verificar(api.get("/vinos/1"), 200)
    assert verificar(api.post("/transferencias/131/procesar"), 200)["estado"] == "procesado"
    despues = verificar(api.get("/vinos/1"), 200)
    assert despues["stock_salas"] == antes["stock_salas"] + 3
    assert despues["stock_deposito"] == antes["stock_deposito"] - 3
    verificar(api.post("/transferencias/131/procesar"), 409)


def test_ingreso_completo_y_reportes(api):
    datos = {"codigo": 141, "cuit_bodega": "20111111111", "codigo_transporte": 1}
    verificar(api.post("/ingresos", json=datos), 201)
    verificar(api.post("/ingresos/141/renglones", json={"codigo_vino": 1, "cantidad": 5}), 201)
    verificar(api.post("/ingresos/141/terminar"), 200)
    antes = verificar(api.get("/vinos/1"), 200)["stock_deposito"]
    assert verificar(api.post("/ingresos/141/procesar"), 200)["estado"] == "procesado"
    ficha = verificar(api.get("/reportes/trazabilidad/1"), 200)
    assert ficha["stock_deposito"] == antes + 5
    assert verificar(api.get("/reportes/transportista-activo"), 200)[0]["codigo"] == 1
    assert 2 in [v["codigo"] for v in verificar(api.get("/reportes/vinos-sin-stock?sala=1"), 200)]
    assert isinstance(verificar(api.get("/reportes/top-vinos"), 200), list)
    assert isinstance(verificar(api.get("/reportes/ventas-por-sala"), 200), list)
