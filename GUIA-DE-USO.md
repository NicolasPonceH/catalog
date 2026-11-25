# CataLog · Guía de uso

CataLog registra cada catalítico que compras, le imprime un sticker con su código, permite cuadrar inventario por Wi-Fi local con el supervisor y te arma los reportes en Excel. Todo queda guardado en el teléfono y funciona en terreno sin internet.

## 1. Instalar

1. Pasa el APK más nuevo (`CataLog-1.6.apk`) al celular, por WhatsApp o con el cable.
2. Ábrelo y acepta **instalar apps desconocidas** cuando el teléfono lo pida.
3. Si aparece un aviso de seguridad (Xiaomi o Play Protect), toca **Instalar de todas formas**.

Las versiones nuevas se instalan encima de la anterior **sin borrar las compras**.

## 2. Al abrir CataLog

- **Bienvenida y bloqueo:** el logo se arma solo, te saluda por tu nombre y muestra lo gastado en el mes. Si activaste el bloqueo, ves la pantalla de análisis de huella (sin mostrar montos hasta desbloquear).
- **Alertas visuales en Inicio:** si tienes compras sin sacar sticker o dejaste un lote abierto sin cerrar, aparecen arriba **tarjetas con borde naranja** para resolverlo con un toque.
- **Barra de pestañas abajo:** **Inicio**, **Historial**, **Lotes** y **Reportes**, con el botón naranja grande de **Escanear** siempre al centro.
- **Botón de ayuda (`?`):** ilumina cada botón de la pantalla actual y explica para qué sirve paso a paso.

## 3. Lo que puedes configurar en Ajustes

En **Ajustes** (la ruedita, arriba a la derecha):

- **Tu perfil:** edita **tu nombre** y el **prefijo** de este teléfono (`CTL`, `CTT`, etc.) para que los códigos nunca se repitan.
- **Apariencia e idioma:** elige **tema** (claro, oscuro o automático), **alto contraste**, **tamaño de letra**, **animaciones** e idioma **Español / English** en vivo.
- **Fotos y espacio en el teléfono:** por defecto las fotos se guardan en calidad **Ligera (~80 KB)** para que la app siga liviana aunque tengas miles de compras. También puedes elegir *Normal* o *Alta* y tocar **Optimizar fotos guardadas** para comprimir fotos antiguas.
- **Notificaciones emergentes (Pop-up):**
  - Elige cada cuánto repetir los avisos pendientes en el día (**Cada 30 min, 1 h, 2 h, 4 h o 1 vez**).
  - Activa el **aviso inmediato apenas sales de la app** si dejaste un sticker sin imprimir o un lote abierto.
  - Si tu teléfono (ej. Xiaomi o Samsung) oculta los banners flotantes, toca **Activar Pop-up en pantalla (Android)** para habilitarlo directo.
- **Ubicar respaldo (tarjeta roja importante):** abre la app de Archivos del teléfono exactamente en `Descargas/Respaldo CataLog`.
- **Impresora:** enciéndela, toca **Buscar** y elígela de la lista. Después toca **Imprimir sticker de prueba**. Usa **rollos térmicos adhesivos**.

## 4. Registrar una compra rápida

1. Toca **Nueva compra**.
2. Revisa la **fecha y hora de compra** (se llena sola y puedes corregirla).
3. Completa:
   - **Vendedor:** al tocar o escribir las primeras letras aparecen abajo **pastillas rápidas de 1 toque** con tus vendedores más frecuentes.
   - **Lugar** (guarda el GPS automáticamente) y **Precio pagado**.
   - **Motor** y **material**.
   - **Código grabado de fábrica:** si ya compraste ese mismo código antes, muestra debajo cuánto pagaste la última vez y el promedio, con botón para usar ese monto al tiro.
   - **De qué autos es:** también sugiere con **1 toque** los vehículos frecuentes de tu historial.
   - **Foto** ligera del catalítico.
4. Toca **Guardar compra** e **Imprimir sticker**. Mientras una compra tenga `0 impresiones`, se verá destacada con **borde naranja (`No se le ha sacado el sticker`)** en Inicio e Historial.

El precio **no** sale en el sticker: solo se ve dentro de CataLog.

## 5. Ver un catalítico y sacar stickers pendientes

Toca el botón naranja **Escanear** al centro de la barra inferior y apunta al QR o código de barras para abrir la ficha completa.

En **Historial**, toca el chip **Sin imprimir** (o el aviso naranja de Inicio) para ver todas las compras pendientes de sticker y sacarlas seguidas en bodega.

## 6. Lotes y utilidad real

1. Toca **Lotes > Nuevo lote** y ponle nombre.
2. Escanea los stickers uno tras otro: suma lo pagado y no cuenta duplicados. Mientras siga abierto, aparecerá destacado con **borde naranja (`⚠ Falta cerrar`)** y te avisará si sales sin cerrarlo.
3. Toca **Terminar** y anota opcionalmente **cuánto te pagaron por el lote** para ver la **utilidad neta** (`Venta − Costo pagado`) en pantalla y en el Excel.

## 7. Sincronizar por Wi-Fi y Revisión de Supervisor

No necesitas cambiar de sesión ni mezclar datos:

1. Con ambos celulares conectados al **mismo Wi-Fi** (o compartiendo zona portátil de uno al otro), toca el botón `⇄` en Inicio **> Sincronizar por Wi-Fi**.
2. Uno elige **Enviar (Mostrar QR)** y el otro **Recibir datos**: el teléfono aparece detectado automáticamente en pantalla o basta con apuntar al código QR para pasar compras y fotos en segundos (de tu celular al del supervisor y viceversa).
3. El supervisor entra a **Revisión de Supervisor** (desde el menú `⇄` o Ajustes):
   - Escanea los stickers físicos con la cámara integrada para marcar cada pieza como **Verificada** y ver al instante cuáles **faltan por escanear**.
   - Puede tocar cualquier pieza para revisar su ficha con foto y GPS en solo lectura.
   - Toca el botón naranja **Excel** para generar y compartir la planilla completa de la revisión.

## 8. Reportes, correcciones y respaldos sin basura

- **Reportes:** exporta a Excel por día, semana, mes, rango de fechas o todo (con hojas de Resumen, Compras, Por tipo y Por vendedor).
- **Anular o corregir:** nada se borra; las compras anuladas salen de los totales pero quedan en el historial (pide **huella o PIN**).
- **Respaldo inteligente:** en **Ajustes > Supervisor, Wi-Fi y Respaldos > Limpieza de respaldos**, por defecto CataLog **sobrescribe un único archivo `.zip`** siempre al día en `Descargas/Respaldo CataLog` para no llenar la carpeta de copias repetidas (o puedes elegir que expiren solos a los 7 o 30 días).
