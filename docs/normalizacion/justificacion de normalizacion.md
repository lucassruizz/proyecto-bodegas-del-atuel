# Justificación de normalización

## Primera Forma Normal (1FN)

Cada tabla tiene una clave primaria y cada campo contiene un solo valor. No se guardan listas de vinos, cepas o permisos en una misma columna.

Los atributos compuestos del DER se separaron en campos. Por ejemplo, la dirección de una sala se dividió en calle y número, y el documento del cliente en tipo y número.

Los datos que pueden repetirse se registran en tablas relacionadas. Por eso los comprobantes tienen renglones, los exportadores tienen permisos y los vinos se relacionan con sus cepas y maridajes.

## Segunda Forma Normal (2FN)

Se revisó que los datos dependieran de la clave completa, especialmente cuando se necesitan dos campos para identificar un registro.

| Tabla | Clave | Datos asociados a la combinación completa |
|---|---|---|
| parcela | idFinca y numeroParcela | Superficie, año de plantación y cepa. |
| componen | codigoVino e idCepa | Porcentaje de la cepa en ese vino. |
| contiene | codigoIngreso y codigoVino | Cantidad de botellas en ese ingreso. |
| incluye | numeroSolicitud y codigoVino | Cantidad del vino en esa transferencia. |
| posee | idSalaVenta y codigoVino | Stock del vino en esa sala. |

Por ejemplo, la superficie de una parcela corresponde a una finca y un número de parcela juntos. El número por sí solo no identifica una parcela de toda la empresa.

Las tablas tienen y alcanza contienen únicamente los campos de su clave. En renglon_comprobante, la cantidad y el precio corresponden a un vino dentro de una venta concreta. El descuento común a toda la venta constituye una excepción, explicada al final.

## Tercera Forma Normal (3FN)

Se separaron los datos de cada entidad para evitar repetir información que puede consultarse mediante una referencia.

SALA_VENTA y CLIENTE referencian a LOCALIDAD sin repetir su nombre y provincia. VINO referencia a BODEGA sin copiar su razón social ni su domicilio. Los subtipos de cliente conservan sus datos específicos y comparten los datos generales de CLIENTE.

FINCA referencia a DEPARTAMENTO, donde se guardan el nombre del departamento y su provincia. Esta separación permite compartir esos datos entre varias fincas. Guardarlos directamente en FINCA no demostraría, por sí solo, un incumplimiento de 3FN.

Algunas dependencias consideradas son:

- idLocalidad determina nombre, provincia y codigoPostal.
- idSalaVenta determina calle, numero, diaCierreSemanal e idLocalidad.
- idDepartamento determina nombreDepartamento y provincia.
- El id de FINCA determina nombre, superficieTotal e idDepartamento.
- El CUIT de BODEGA determina razonSocial y domicilio.
- La combinación de idFinca y numeroParcela determina superficie, anioPlantacion e idCepa.
- La combinación de codigoVino e idCepa determina porcentaje.
- La combinación de idSalaVenta y codigoVino determina cantidadStock.

En estas relaciones, los datos corresponden a sus claves y no se repiten los atributos descriptivos de las entidades referenciadas.

## Excepciones por descuentos e importes

Se conservan los descuentos, subtotales y totales solicitados por la consigna. Sin embargo, esto requiere aclarar algunas excepciones a la normalización.

El porcentaje de descuento se repite en los renglones de una misma venta. Como es común al comprobante, depende de numeroComprobante y no de la clave completa del renglón. Por eso renglon_comprobante no cumple estrictamente 2FN ni 3FN bajo esta decisión.

Además, subtotalRenglon se calcula a partir de cantidad, precioUnitario y descuento. En COMPROBANTE, total se obtiene restando descuento a subtotal. Al guardar estos resultados, quedan dependencias entre campos que no son clave y no se puede afirmar un cumplimiento estricto de 3FN en esas tablas.

El precio unitario histórico debe conservarse porque puede diferir del precio actual del vino. El porcentaje aplicado también se mantiene para que cambios posteriores en la situación del cliente no alteren ventas anteriores.

Estas excepciones se documentan como redundancias controladas: se conserva información repetida o calculable y se exige mantenerla coherente. El SQL actual todavía no garantiza todos los cálculos ni la correspondencia del descuento con el subtipo.

## Conclusión

El modelo separa entidades y asociaciones para reducir repeticiones. Las excepciones identificadas corresponden a descuentos e importes almacenados. Por eso se justifica la normalización de los datos básicos, pero no se afirma que todas las tablas cumplan estrictamente 3FN sin excepciones.
