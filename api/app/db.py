"""Configuración del pool de conexiones con PostgreSQL."""

import os
from contextlib import asynccontextmanager

from psycopg.conninfo import make_conninfo
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool


@asynccontextmanager
async def lifespan(app):
    conninfo = make_conninfo(
        host=os.getenv("DB_HOST", "localhost"),
        port=os.getenv("DB_PORT", "5432"),
        dbname=os.getenv("DB_NAME", "bodegas"),
        user=os.getenv("DB_USER", "bodega_api"),
        password=os.environ["DB_PASSWORD"],
        connect_timeout=5,
    )
    with ConnectionPool(
        conninfo, min_size=1, max_size=8, timeout=5, open=False,
        kwargs={"row_factory": dict_row, "autocommit": True},
    ) as pool:
        app.state.pool = pool
        yield
