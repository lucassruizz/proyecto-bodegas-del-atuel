"""Contratos HTTP. PostgreSQL valida las reglas de negocio."""

from datetime import date
from decimal import Decimal
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field

Id = Annotated[int, Field(gt=0, le=2**63 - 1)]


class Entrada(BaseModel):
    model_config = ConfigDict(extra="forbid")


class Cepa(Entrada):
    id_cepa: Id
    porcentaje: Decimal


class Vino(Entrada):
    nombre: str
    volumen: Decimal
    graduacion_alcoholica: Decimal
    tipo: str
    anada: int
    precio: Decimal
    cuit_bodega: str
    composicion: list[Cepa] = Field(min_length=1)
    maridajes: list[Id] = Field(default_factory=list)


class VinoNuevo(Vino):
    codigo: Id


class DatosCliente(Entrada):
    tipo_documento: str
    numero_documento: str
    direccion: str
    id_localidad: Id
    nombre: str | None = None
    apellido: str | None = None
    razon_social: str | None = None


class Socio(DatosCliente):
    tipo: Literal["socio_club"]


class Distribuidor(DatosCliente):
    tipo: Literal["distribuidor"]
    zona_cobertura: str
    numero_habilitacion: str


class Exportador(DatosCliente):
    tipo: Literal["exportador"]
    pais_destino_principal: str


Cliente = Annotated[Socio | Distribuidor | Exportador, Field(discriminator="tipo")]


class Renglon(Entrada):
    codigo_vino: Id
    cantidad: int


class Venta(Entrada):
    numero: Id
    id_cliente: Id
    id_sala: Id
    renglones: list[Renglon] = Field(min_length=1)
    fecha: date | None = None


class Transferencia(Entrada):
    numero: Id
    id_sala: Id


class Ingreso(Entrada):
    codigo: Id
    cuit_bodega: str
    codigo_transporte: Id
    fecha: date | None = None


class FilaVino(BaseModel):
    codigo: int
    nombre: str
    tipo: str
    anada: int
    precio: Decimal
    cuit_bodega: str
    bodega: str


class CepaDetalle(Cepa):
    nombre: str


class MaridajeDetalle(BaseModel):
    id_maridaje: int
    nombre: str


class FichaVino(FilaVino):
    volumen: Decimal
    graduacion_alcoholica: Decimal
    stock_deposito: int
    stock_salas: int
    stock_total: int
    composicion: list[CepaDetalle]
    maridajes: list[MaridajeDetalle]


class FichaCliente(DatosCliente):
    id_cliente: int
    fecha_alta: date
    descuento: Decimal
    tipo: Literal["socio_club", "distribuidor", "exportador"]
    zona_cobertura: str | None
    numero_habilitacion: str | None
    pais_destino_principal: str | None


class RenglonVenta(Renglon):
    precio_unitario: Decimal
    descuento: Decimal
    subtotal: Decimal


class Comprobante(BaseModel):
    numero: int
    fecha: date
    id_cliente: int
    id_sala: int
    subtotal: Decimal
    descuento: Decimal
    total: Decimal
    renglones: list[RenglonVenta]


Estado = Literal["en_confeccion", "terminado", "procesado"]


class EstadoTransferencia(BaseModel):
    numero: int
    estado: Estado


class TransferenciaDetalle(EstadoTransferencia):
    id_sala: int
    fecha: date


class RenglonTransferencia(Renglon):
    numero: int


class EstadoIngreso(BaseModel):
    codigo: int
    estado: Estado


class IngresoDetalle(EstadoIngreso):
    cuit_bodega: str
    codigo_transporte: int
    id_deposito: int
    fecha: date


class RenglonIngreso(Renglon):
    codigo: int


class VinoVendido(BaseModel):
    codigo: int
    nombre: str
    botellas: int


class VentasSala(BaseModel):
    id_sala: int
    ventas: Decimal


class VinoSinStock(BaseModel):
    codigo: int
    nombre: str
    stock_deposito: int


class TransportistaActivo(BaseModel):
    codigo: int
    razon_social: str
    envios: int


class Salud(BaseModel):
    estado: str
    base: str


class ErrorSQL(BaseModel):
    detail: str
    sqlstate: str | None = None
    restriccion: str | None = None
