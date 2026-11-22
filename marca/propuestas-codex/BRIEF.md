# Encargo: mejorar el logo de CataLog

Trabaja SOLO dentro de esta carpeta. No modifiques nada fuera de ella.

## La app
CataLog es una app Android para dos compradores de convertidores catalíticos usados (Chile). Registra cada compra (fecha, vendedor, precio, tipo), imprime un sticker térmico de 58 mm con QR y código de barras que se pega en el catalítico, y después se escanea para ver la ficha. Público: comerciantes, uso en terreno, teléfonos Android.

## Logo actual (ver `referencia/`)
- `catalog-icono.svg` / `catalog-icono.png`: ícono de app. Silueta de un catalítico (cuerpo redondeado con un código de barras calado) con dos tubos naranjos a los lados, sobre fondo azul marino.
- `catalog-logo.svg`, `catalog-logo-oscuro.svg`, `catalog-logo-bn.svg`: logo horizontal ("Cata" azul marino + "Log" naranja, Space Grotesk Bold), versión para fondo oscuro y versión negro puro para imprimir.
- `sticker-58mm.png`: cómo sale el logo impreso en el sticker (384 px de ancho, blanco y negro).

Problemas a resolver: el catalítico se lee más como una "píldora" o cápsula que como un convertidor catalítico; el ícono pierde fuerza a tamaño chico; el logo en el sticker debe verse nítido a 203 ppp en papel térmico.

## Qué mantener
- Concepto: catalítico + código (barras o QR), porque la app trata de etiquetar y registrar catalíticos.
- Colores: azul marino #0E2A47, naranja #FF7A1A, gris niebla #F4F6F8 (acero #5B6B7C para detalles).
- Nombre "CataLog" con "Cata" y "Log" diferenciados por color. Tipografía Space Grotesk Bold (puedes ajustar espaciado).

## Qué entregar
Tres propuestas DISTINTAS entre sí, en carpetas `propuesta-1/`, `propuesta-2/`, `propuesta-3/`. Cada una con:
1. `icono.svg`: ícono de app, viewBox 0 0 64 64, fondo cuadrado azul marino (sin esquinas redondeadas: Android aplica su máscara). El símbolo debe caber dentro del 66 % central (zona segura del ícono adaptativo) y reconocerse a 48 px.
2. `simbolo.svg`: solo el símbolo, sin fondo, viewBox ajustado.
3. `logo.svg`: horizontal (símbolo + "CataLog") para fondo claro.
4. `logo-oscuro.svg`: horizontal para fondo azul marino.
5. `logo-bn.svg`: horizontal en NEGRO PURO (#000) sobre transparente, para impresora térmica: sin degradados, sin grises, sin líneas de menos de 2 px a 384 px de ancho.
6. `NOTAS.md`: 3-5 líneas con la idea y por qué es mejor que el actual.

Además, un `propuestas.html` en esta carpeta que muestre las tres propuestas lado a lado (íconos a 192, 96 y 48 px; logos claro, oscuro y blanco y negro) y el logo actual de referencia, para comparar.

## Reglas técnicas
- SVG limpio y a mano (formas simples: rect, circle, path). Nada de imágenes incrustadas ni filtros.
- El texto puede ir como `<text>` con font-family "'Space Grotesk', Arial, sans-serif" y font-weight 700 (como el actual).
- No copies logos de marcas existentes.
- No instales dependencias ni uses internet.
