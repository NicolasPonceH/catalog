# CataLog · Guía de uso

CataLog registra cada catalítico que compras, le imprime un sticker con su código y te arma los reportes en Excel. Todo queda guardado en el teléfono y funciona sin internet.

## 1. Instalar

1. Pasa el APK más nuevo (hoy `CataLog-1.2.1.apk`) al celular, por WhatsApp o con el cable.
2. Ábrelo y acepta **instalar apps desconocidas** cuando el teléfono lo pida.
3. Si aparece un aviso de seguridad (Xiaomi o Play Protect), toca **Instalar de todas formas**.

Las versiones nuevas se instalan encima de la anterior **sin borrar las compras**.

## 2. La primera vez

En **Ajustes** (la ruedita, arriba a la derecha):

- **Tu nombre** y el **prefijo** de este teléfono. Usa un prefijo distinto en cada celular, por ejemplo `CTL` para uno y `CTT` para el otro, así los códigos nunca se repiten.
- **Impresora:** enciéndela, toca **Buscar** y elígela de la lista. CataLog detecta solo el tipo de impresora. Después toca **Imprimir sticker de prueba**.
  - Si la impresora es "clásica", primero hay que emparejarla en *Ajustes de Android > Bluetooth* (el PIN suele ser 0000 o 1234).
  - Si un equipo aparece dos veces y uno no imprime, prueba con el otro.
- Usa **rollos térmicos adhesivos** para que el sticker pegue.

## 3. Registrar una compra

1. Toca **Nueva compra**.
2. Revisa la **fecha y hora de compra**: se llena sola. Si anotas la compra más tarde, tócala y pon la fecha y hora reales.
3. Completa:
   - **Vendedor** y **lugar**. La app te sugiere los que ya usaste y guarda el GPS sola.
   - **Precio pagado**.
   - **Motor** y **material**.
   - **Código grabado de fábrica** y **de qué autos es**.
   - **Foto** del catalítico.
4. Toca **Guardar compra**. Se abre la ficha con el código, por ejemplo `CTL-261121-0007`.
5. Toca **Imprimir sticker** y pégalo en el catalítico.

El precio **no** sale en el sticker: solo se ve al escanearlo con CataLog.

## 4. Ver un catalítico

En el Inicio, toca **Escanear sticker** y apunta al QR o al código de barras. Se abre su ficha completa: fecha de compra, vendedor, lugar con mapa, precio, tipo y foto.

Si el sticker está dañado, toca **Escribir el código a mano**.

## 5. Lotes (varios catalíticos juntos)

1. Toca **Lotes > Nuevo lote** y escribe el nombre (viene sugerido con la fecha y hora).
2. Escanea los stickers uno tras otro. Cada uno suma lo que pagaste por él, y el mismo catalítico no se cuenta dos veces.
3. Al final toca **Terminar**. Si sales sin escanear nada, el lote no se guarda.
4. Con el botón de tabla (arriba) se manda el **Excel del lote** por WhatsApp o correo.

## 6. Reportes y Excel

En **Reportes** eliges el período: hoy, semana, mes, unas fechas o todo. Ahí ves el total gastado, la cantidad, el promedio y los totales por tipo y por vendedor.

**Exportar a Excel** arma un archivo con estas hojas:
- Resumen
- Compras: una fila por catalítico, con fecha, hora y precio
- Por tipo
- Por vendedor

## 7. Corregir o anular

- **Corregir:** en la ficha, toca el lápiz. Si cambias la fecha de compra, la ficha muestra que se corrigió y cuándo.
- **Anular:** en la ficha, menú de tres puntos > **Anular compra**. Sale de los totales, pero queda en el historial y su número no se vuelve a usar.
- **Para borrar o anular cualquier cosa** (una compra, un lote, un catalítico de un lote, una revisión, o reemplazar tus compras con un respaldo) CataLog pide tu **huella o PIN**.

## 8. Respaldo (muy importante)

Las compras viven solo en el teléfono. Si se pierde o se rompe, se pierden. Para evitarlo:

- Todos los respaldos quedan en la carpeta **Descargas/Respaldo CataLog** del teléfono. Esa carpeta **no se borra si desinstalas la app**.
- **Copia automática:** cada día CataLog guarda sola una copia ahí (se conservan las 3 últimas).
- **Crear respaldo:** botón de flechas del Inicio (o Ajustes) **> Crear respaldo**. Se guarda en esa carpeta y después te ofrece **Enviar** a tu correo, Drive o WhatsApp. Envíalo de vez en cuando: eso protege si se pierde el teléfono.
- CataLog te recuerda en el Inicio cuando toca hacerlo.
- **Restaurar:** **Ajustes > Restaurar desde un respaldo**. La app muestra los respaldos de la carpeta Respaldo CataLog; eliges uno y lo extrae sola. Si el archivo está en otra parte (WhatsApp, Drive), toca **Buscar otro archivo**, o tócalo directamente y elige **Abrir con CataLog**.

## 9. Pasar las compras a otro celular (sesiones)

CataLog separa los datos en **sesiones**:

- **Sesión de compra:** tus compras. Ahí registras, imprimes y ves tus totales.
- **Sesión de revisión:** datos que te mandó otro celular. Se pueden escanear, ver las fichas, armar lotes y sacar reportes, pero **no se mezclan con tus compras** ni se pueden modificar.

**Para mandar tus compras** (por ejemplo, para que tu tío revise y escanee los catalíticos que le entregas):
1. Botón de flechas del Inicio **> Enviar mis compras a otro celular**.
2. Elige con o sin fotos (sin fotos pesa menos) y mándalo por WhatsApp o por donde quieras.

**Para recibirlas en el otro celular:**
1. Toca el archivo en WhatsApp y elige **Abrir con CataLog** (o, en CataLog, **Recibir datos de otro celular**).
2. Elige **Abrir para revisar**. Arriba del Inicio aparece "Sesión de revisión".
3. Para volver a tus compras: **Volver a mis compras**, o botón de flechas **> Cambiar de sesión**.

Si te vuelven a mandar datos del mismo teléfono, la revisión se actualiza (no se duplica).

## 10. Bloqueo con huella o PIN

En **Ajustes > Seguridad** activa **Pedir huella o PIN al abrir**. CataLog usa el bloqueo del teléfono (huella, rostro, PIN o patrón) y lo vuelve a pedir si la app estuvo cerrada más de 2 minutos.

## Si algo falla

- **La impresora no aparece:** revisa que el Bluetooth esté encendido y que la impresora esté prendida y cerca. Si Android pide el permiso de **Dispositivos cercanos**, acéptalo.
- **El sticker sale en blanco:** el rollo está al revés. El papel térmico imprime por un solo lado.
- **El sticker sale muy claro o se borra:** guarda los catalíticos bajo techo. El papel térmico se borra con el sol y el calor; una cinta transparente encima ayuda.
- **No lee el código:** acerca o aleja el teléfono, usa la **linterna** del escáner o escribe el código a mano.
- **Una impresora que no conecta de ninguna forma:** usa **Compartir sticker como imagen** e imprímelo con la app propia de la impresora.
