# Informe final del TPI Bodegas del Atuel

## Alcance

Bodegas del Atuel registra la producción de uva y vino, los ingresos al depósito, las transferencias a las salas y las ventas. La base resuelve la integridad, los importes y el stock. La API conecta las operaciones con PostgreSQL mediante consultas parametrizadas. El [README](../README.md) explica el arranque local y las pruebas.

## Modelo de datos

El [DER](der/) representa el escenario. El [esquema relacional](esquema-relacional/), el [diccionario](diccionario-datos/) y la [justificación de normalización](normalizacion/) explican cómo se pasó al SQL. Las [decisiones de diseño](decisiones-dise%C3%B1o/) justifican, entre otras cosas, las claves de negocio, la separación de subtipos de cliente y las acciones referenciales.

Una parcela se identifica por finca y número. El cliente tiene una tabla con sus datos comunes y otra para su subtipo. Los precios históricos se guardan en los renglones. Los importes derivados se guardan y se recalculan al editar los renglones. La justificación de normalización identifica las dependencias que esas redundancias introducen.

## Integridad y concurrencia

La [tabla de trazabilidad](etapa-2/trazabilidad.md) vincula las RN-01 a RN-15 con el mecanismo y su prueba. Los valores de una fila se controlan con CHECK y NOT NULL. Las FK controlan referencias y las claves únicas evitan duplicados. Las condiciones que dependen de varias filas, como el corte, se comprueban con triggers diferidos. Los procedimientos de ingresos y transferencias solicitan el cambio de estado. El trigger de ese cambio mueve el stock dentro de la misma operación. La [prueba de concurrencia](etapa-2/concurrencia.md) muestra qué ve cada sesión al vender la última botella.

## Carga masiva

La [guía de carga](etapa-3/README.md) detalla el orden de las tablas, los CSV, la semilla y los controles. La carga histórica desactiva temporalmente los triggers de usuario dentro de una transacción, con las FK y los CHECK activos. Luego calcula importes y saldos, controla los datos y vuelve a habilitar los triggers. El reporte registra 20.000 clientes, 150.000 comprobantes y 500.000 renglones. La guía incluye la comparación de técnicas de inserción y cómo generar el volcado.

## Índices y rendimiento

El [informe de rendimiento](etapa-4/README.md) guarda los planes antes y después de los cinco índices. En la medición original, S3 bajó de 3,954 a 0,093 ms y S8 de 6,149 a 1,340 ms. S1 siguió con recorrido secuencial porque lee todo el conjunto de renglones. La medición de escritura muestra el costo adicional de mantener índices. Los tiempos dependen de la carga y del entorno.

## Consultas SQL

Las [consultas](../consultas/) llevan código, explicación y parámetros de prueba. El [informe de etapa 5](etapa-5/README.md) incluye resultados, planes y evidencia de reversión. S9 agrega las cepas y los maridajes por separado. S11 usa ventanas para el ranking y las ventas acumuladas. U6 y D5 dejan registrados los rechazos de las reglas vigentes. Aplicarlas con éxito requiere acordar el criterio de descuento y borrado con la cátedra.

## API y frontend

La [documentación de la API](etapa-6/README.md) explica las rutas, las transacciones, la traducción de SQLSTATE y la prueba de parametrización. Swagger muestra los contratos. Las pruebas se ejecutan con PostgreSQL y cubren tanto operaciones exitosas como rechazos y rollback. Los [bocetos del frontend](../front/) quedan como referencia de pantallas.

## Conclusiones

La carga histórica y las ventas nuevas necesitan compartir la misma regla de cálculo. Redondear primero el descuento evita que la resta de los importes difiera del total. También conviene probar las reglas desde SQL, además de probarlas desde la API. Así aparecieron los problemas de permisos sobre los totales y el stock, y el alta de vinos sin corte.
