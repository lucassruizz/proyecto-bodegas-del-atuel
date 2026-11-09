"""Rutas HTTP y transacciones de Bodegas del Atuel."""

import logging
from typing import Annotated

import psycopg
from fastapi import Depends, FastAPI, HTTPException, Path, Query, Request, Response
from fastapi.responses import JSONResponse
from psycopg_pool import PoolTimeout

from . import consultas as q
from . import modelos as m
from .db import lifespan

app = FastAPI(
    title="Bodegas del Atuel",
    version="1.0.0",
    description="API del TPI de Bases de Datos. PostgreSQL aplica las reglas de negocio.",
    lifespan=lifespan,
    responses={
        400: {"model": m.ErrorSQL, "description": "Formato inválido en PostgreSQL"},
        404: {"model": m.ErrorSQL, "description": "Recurso inexistente"},
        409: {"model": m.ErrorSQL, "description": "Conflicto o regla de negocio"},
        503: {"model": m.ErrorSQL, "description": "Base indisponible o conflicto transitorio"},
    },
)
log = logging.getLogger(__name__)


def conexion(request: Request):
    with request.app.state.pool.connection() as db:
        yield db


DB = Annotated[psycopg.Connection, Depends(conexion, scope="function")]
Codigo = Annotated[int, Path(gt=0, le=2**63 - 1)]
Limite = Annotated[int, Query(ge=1, le=100)]
Offset = Annotated[int, Query(ge=0, le=2**63 - 1)]
ConsultaId = Annotated[int, Query(gt=0, le=2**63 - 1)]
Anada = Annotated[int, Query(ge=1, le=9999)]

ESTADOS_SQL = {
    "23505": (409, "Ya existe un registro con esos datos."),
    "23503": (409, "El dato relacionado no existe o tiene registros dependientes."),
    "23514": (422, "El valor incumple una restricción de la base."),
    "23502": (422, "Falta un dato obligatorio."),
    "22001": (422, "El texto excede la longitud admitida."),
    "22003": (422, "El número está fuera del rango admitido."),
    "22P02": (400, "El valor tiene un formato inválido."),
    "P0001": (409, "La base rechazó la operación."),
    "40001": (503, "Conflicto transitorio. Reintentá la operación."),
    "40P01": (503, "Conflicto transitorio. Reintentá la operación."),
}


@app.exception_handler(psycopg.Error)
async def error_sql(request: Request, error: psycopg.Error):
    estado = error.sqlstate
    if estado in ESTADOS_SQL:
        codigo, mensaje = ESTADOS_SQL[estado]
        if estado == "P0001":
            mensaje = error.diag.message_primary or mensaje
        cuerpo = {"detail": mensaje, "sqlstate": estado}
        if error.diag.constraint_name:
            cuerpo["restriccion"] = error.diag.constraint_name
        return JSONResponse(
            cuerpo, status_code=codigo, headers={"Retry-After": "1"} if codigo == 503 else None
        )
    if isinstance(error, psycopg.OperationalError):
        return await base_no_disponible(request, error)
    log.error("Error PostgreSQL inesperado en %s (SQLSTATE %s)", request.url.path, estado)
    return JSONResponse({"detail": "Error interno de base de datos."}, status_code=500)


@app.exception_handler(PoolTimeout)
async def base_no_disponible(_request: Request, _error: Exception):
    return JSONResponse(
        {"detail": "Base de datos temporalmente no disponible."},
        status_code=503, headers={"Retry-After": "1"},
    )


def existente(fila, recurso):
    if fila is None:
        raise HTTPException(404, f"{recurso} no encontrado.")
    return fila


def guardar_composicion(db, codigo, vino):
    for cepa in vino.composicion:
        q.insertar_cepa_vino(db, codigo, cepa)
    for maridaje in vino.maridajes:
        q.insertar_maridaje_vino(db, codigo, maridaje)


def guardar_subtipo(db, codigo, cliente):
    if isinstance(cliente, m.Socio):
        q.guardar_socio(db, codigo)
    elif isinstance(cliente, m.Distribuidor):
        q.guardar_distribuidor(db, codigo, cliente)
    else:
        q.guardar_exportador(db, codigo, cliente)
    q.actualizar_descuento(db, codigo)


QUITAR_SUBTIPO = {
    "socio_club": q.quitar_socio,
    "distribuidor": q.quitar_distribuidor,
    "exportador": q.quitar_exportador,
}


@app.get("/salud", tags=["Salud"], response_model=m.Salud)
def salud(db: DB):
    q.salud(db)
    return {"estado": "ok", "base": "disponible"}


@app.get("/vinos", tags=["Vinos"], response_model=list[m.FilaVino])
def listar_vinos(
    db: DB, tipo: str | None = None, cepa: ConsultaId | None = None,
    bodega: str | None = None, anada: Anada | None = None,
    limite: Limite = 20, offset: Offset = 0,
):
    """Filtra por tipo, ID de cepa, CUIT de bodega y añada."""
    return q.listar_vinos(db, tipo, cepa, bodega, anada, limite, offset)


@app.get("/vinos/{codigo}", tags=["Vinos"], response_model=m.FichaVino)
def detalle_vino(codigo: Codigo, db: DB):
    return existente(q.detalle_vino(db, codigo), "Vino")


@app.post("/vinos", status_code=201, tags=["Vinos"], response_model=m.FichaVino)
def crear_vino(vino: m.VinoNuevo, db: DB):
    with db.transaction():
        q.insertar_vino(db, vino)
        guardar_composicion(db, vino.codigo, vino)
        return q.detalle_vino(db, vino.codigo)


@app.put("/vinos/{codigo}", tags=["Vinos"], response_model=m.FichaVino)
def actualizar_vino(codigo: Codigo, vino: m.Vino, db: DB):
    """Reemplaza los datos, la composición y los maridajes del vino."""
    with db.transaction():
        existente(q.actualizar_vino(db, codigo, vino), "Vino")
        q.quitar_composicion(db, codigo)
        q.quitar_maridajes(db, codigo)
        guardar_composicion(db, codigo, vino)
        return q.detalle_vino(db, codigo)


@app.delete("/vinos/{codigo}", status_code=204, tags=["Vinos"])
def eliminar_vino(codigo: Codigo, db: DB):
    with db.transaction():
        existente(q.bloquear_vino(db, codigo), "Vino")
        q.quitar_composicion(db, codigo)
        q.quitar_maridajes(db, codigo)
        q.eliminar_vino(db, codigo)
    return Response(status_code=204)


@app.get("/clientes", tags=["Clientes"], response_model=list[m.FichaCliente])
def listar_clientes(db: DB, limite: Limite = 20, offset: Offset = 0):
    return q.listar_clientes(db, limite, offset)


@app.get("/clientes/{codigo}", tags=["Clientes"], response_model=m.FichaCliente)
def detalle_cliente(codigo: Codigo, db: DB):
    return existente(q.detalle_cliente(db, codigo), "Cliente")


@app.post("/clientes", status_code=201, tags=["Clientes"], response_model=m.FichaCliente)
def crear_cliente(cliente: m.Cliente, db: DB):
    with db.transaction():
        codigo = q.insertar_cliente(db, cliente)
        guardar_subtipo(db, codigo, cliente)
        return q.detalle_cliente(db, codigo)


@app.put("/clientes/{codigo}", tags=["Clientes"], response_model=m.FichaCliente)
def actualizar_cliente(codigo: Codigo, cliente: m.Cliente, db: DB):
    with db.transaction():
        existente(q.actualizar_cliente(db, codigo, cliente), "Cliente")
        tipo_anterior = q.detalle_cliente(db, codigo)["tipo"]
        if tipo_anterior != cliente.tipo and tipo_anterior in QUITAR_SUBTIPO:
            QUITAR_SUBTIPO[tipo_anterior](db, codigo)
        guardar_subtipo(db, codigo, cliente)
        return q.detalle_cliente(db, codigo)


@app.delete("/clientes/{codigo}", status_code=204, tags=["Clientes"])
def eliminar_cliente(codigo: Codigo, db: DB):
    with db.transaction():
        existente(q.bloquear_cliente(db, codigo), "Cliente")
        for quitar in QUITAR_SUBTIPO.values():
            quitar(db, codigo)
        q.eliminar_cliente(db, codigo)
    return Response(status_code=204)


@app.post("/comprobantes", status_code=201, tags=["Comprobantes"], response_model=m.Comprobante)
def crear_venta(venta: m.Venta, db: DB):
    """Registra la venta completa. Los triggers calculan importes y descuentan stock."""
    with db.transaction():
        q.insertar_venta(db, venta)
        # Orden de bloqueo estable para ventas con varios vinos.
        for renglon in sorted(venta.renglones, key=lambda item: item.codigo_vino):
            existente(q.insertar_renglon_venta(db, venta.numero, renglon), "Vino")
        return q.detalle_venta(db, venta.numero)


@app.get("/comprobantes/{numero}", tags=["Comprobantes"], response_model=m.Comprobante)
def detalle_venta(numero: Codigo, db: DB):
    return existente(q.detalle_venta(db, numero), "Comprobante")


@app.post("/transferencias", status_code=201, tags=["Transferencias"], response_model=m.TransferenciaDetalle)
def crear_transferencia(datos: m.Transferencia, db: DB):
    return q.insertar_transferencia(db, datos)


@app.post("/transferencias/{numero}/renglones", status_code=201, tags=["Transferencias"], response_model=m.RenglonTransferencia)
def agregar_transferencia(numero: Codigo, renglon: m.Renglon, db: DB):
    with db.transaction():
        existente(q.bloquear_transferencia(db, numero), "Transferencia")
        return q.insertar_renglon_transferencia(db, numero, renglon)


@app.post("/transferencias/{numero}/terminar", tags=["Transferencias"], response_model=m.EstadoTransferencia)
def terminar_transferencia(numero: Codigo, db: DB):
    return existente(q.terminar_transferencia(db, numero), "Transferencia")


@app.post("/transferencias/{numero}/procesar", tags=["Transferencias"], response_model=m.EstadoTransferencia)
def procesar_transferencia(numero: Codigo, db: DB):
    with db.transaction():
        existente(q.bloquear_transferencia(db, numero), "Transferencia")
        q.procesar_transferencia(db, numero)
        return q.detalle_transferencia(db, numero)


@app.post("/ingresos", status_code=201, tags=["Ingresos"], response_model=m.IngresoDetalle)
def crear_ingreso(datos: m.Ingreso, db: DB):
    return q.insertar_ingreso(db, datos)


@app.post("/ingresos/{codigo}/renglones", status_code=201, tags=["Ingresos"], response_model=m.RenglonIngreso)
def agregar_ingreso(codigo: Codigo, renglon: m.Renglon, db: DB):
    with db.transaction():
        existente(q.bloquear_ingreso(db, codigo), "Ingreso")
        return q.insertar_renglon_ingreso(db, codigo, renglon)


@app.post("/ingresos/{codigo}/terminar", tags=["Ingresos"], response_model=m.EstadoIngreso)
def terminar_ingreso(codigo: Codigo, db: DB):
    return existente(q.terminar_ingreso(db, codigo), "Ingreso")


@app.post("/ingresos/{codigo}/procesar", tags=["Ingresos"], response_model=m.EstadoIngreso)
def procesar_ingreso(codigo: Codigo, db: DB):
    with db.transaction():
        existente(q.bloquear_ingreso(db, codigo), "Ingreso")
        q.procesar_ingreso(db, codigo)
        return q.detalle_ingreso(db, codigo)


@app.get("/reportes/top-vinos", tags=["Reportes"], response_model=list[m.VinoVendido])
def top_vinos(db: DB, limite: Limite = 10, offset: Offset = 0):
    """S1. Los diez vinos más vendidos por cantidad de botellas."""
    return q.top_vinos(db, limite, offset)


@app.get("/reportes/ventas-por-sala", tags=["Reportes"], response_model=list[m.VentasSala])
def ventas_por_sala(db: DB, limite: Limite = 20, offset: Offset = 0):
    """S8. Ventas por sala en el último trimestre móvil."""
    return q.ventas_por_sala(db, limite, offset)


@app.get("/reportes/vinos-sin-stock", tags=["Reportes"], response_model=list[m.VinoSinStock])
def vinos_sin_stock(db: DB, sala: ConsultaId, limite: Limite = 20, offset: Offset = 0):
    """S6. Vinos sin stock en la sala, con stock en el depósito."""
    return q.vinos_sin_stock(db, sala, limite, offset)


@app.get("/reportes/transportista-activo", tags=["Reportes"], response_model=list[m.TransportistaActivo])
def transportista_activo(db: DB, limite: Limite = 20, offset: Offset = 0):
    """S7. Transportistas con más ingresos procesados en el último mes."""
    return q.transportista_activo(db, limite, offset)


@app.get("/reportes/trazabilidad/{codigo}", tags=["Reportes"], response_model=m.FichaVino)
def trazabilidad(codigo: Codigo, db: DB):
    """S9. Ficha con bodega, cepas, maridajes y stock total."""
    return existente(q.detalle_vino(db, codigo), "Vino")
