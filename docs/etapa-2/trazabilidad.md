# Reglas de negocio y pruebas

La suite [db_tests.sql](../../db/tests/db_tests.sql) identifica los casos por RN. Correrla en una base de prueba vacía con todas las migraciones, según el [README](../../README.md#pruebas).

| Regla | Mecanismo en PostgreSQL | Caso en la suite SQL |
| --- | --- | --- |
| RN-01 | Precio en `vino` y `ck_vino_precio`. La sala guarda cantidad, no precio. | RN-01 rechaza precio cero y prueba la unicidad de nombre, añada y volumen. |
| RN-02 | FK de sala, `UNIQUE` de encargado por localidad y dos triggers diferidos en 005. | RN-02 rechaza dos encargados y una localidad sin encargado. |
| RN-03 | FK obligatoria de `empleado` a `sala_venta`. | RN-03 intenta insertar un empleado sin sala y espera `23502`. |
| RN-04 | FK de parcela a cepa y `uq_lote_parcela_campania` en 002. 011 verifica el año de cosecha. | RN-04 intenta una segunda cosecha de la misma parcela y campaña. |
| RN-05 | `trg_componen_porcentaje` y `trg_vino_corte`, diferidos. | RN-05 acepta un corte al 100 % y rechaza un corte al 80 % y una ficha sin cepas. |
| RN-06 | `fn_descuento_cliente`, CHECK y triggers diferidos de subtipos en 005. | RN-06 prueba 10, 20 y 30 %, doble subtipo, baja del único subtipo y descuento incompatible. |
| RN-07 | FK a `exportador` y `ck_permisos_fecha_vencimiento` en 002. | RN-07 rechaza el vencimiento anterior a la emisión. |
| RN-08 | Triggers de renglones, `fn_total_comprobante` y permisos de cabecera en 011. | RN-08 prueba el recálculo al modificar renglones, el redondeo de 100,05 al 10 % y el rechazo de un cambio manual del total con el rol de la API. |
| RN-09 | `trg_renglon_comprobante_stock` bloquea el saldo y el CHECK evita saldos negativos. | RN-09 prueba ventas válidas, exceso de stock, devolución de stock y traslado de un renglón. Ver también la [prueba de dos sesiones](concurrencia.md). |
| RN-10 | ENUM y trigger de estado en 011. `sp_procesar_ingreso` pide la transición y el trigger incorpora el stock. | RN-10 comprueba el procesamiento por `CALL` y por cambio de estado directo con `bodega_api`. |
| RN-11 | ENUM, trigger de fecha y trigger de estado en 011. `sp_procesar_transferencia` pide la transición y el trigger mueve el saldo. | RN-11 verifica una transferencia válida, la fecha de confección y la reversión cuando falta stock para el segundo vino. |
| RN-12 | `trg_contiene_bloqueo` y `trg_incluye_bloqueo`. 011 bloquea la cabecera antes de validar el estado. | RN-12 intenta altas, cambios y bajas de renglones en ambos tipos de documento cerrado. |
| RN-13 | `trg_vino_auditar_precio` y función de 009, que registra `SESSION_USER`. | RN-13 verifica la auditoría de precio. La prueba HTTP verifica que se registra al rol de la API y que el rol no puede insertar en auditoría. |
| RN-14 | FK con `ON DELETE RESTRICT`. | RN-14 intenta borrar bodega, vino y transportista con referencias y espera `23503`. |
| RN-15 | CHECK de cantidades, superficies, kilos, precios y graduación. | RN-15 prueba ceros, negativos y graduaciones por debajo de 5 y por encima de 20. |
