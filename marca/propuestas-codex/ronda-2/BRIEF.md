# Encargo, ronda 2: logo de CataLog MÁS ORIGINAL

Trabaja SOLO dentro de esta carpeta (`ronda-2/`). Puedes LEER `../referencia/` y `../propuesta-1..3/` para no repetirlas, pero no las modifiques.

## Qué pasó en la ronda 1
Las tres propuestas anteriores se parecían entre sí y al logo actual: todas eran la silueta lateral de un catalítico con tubos a los lados y barras adentro. Al cliente le parecieron poco originales. **Esta ronda debe ser claramente distinta.**

## La app (contexto)
CataLog es una app Android de dos compradores chilenos de convertidores catalíticos usados. Registran cada compra (fecha, vendedor, precio, tipo), imprimen un sticker térmico con QR y código de barras que pegan en la pieza, y después lo escanean para ver su historia. El nombre une "catalítico" + "log" (registro, bitácora). Es una herramienta de trabajo en terreno: tiene que verse confiable, fuerte y simple.

## Prohibido en esta ronda
- La silueta lateral de un catalítico con dos tubos (lo que ya se hizo).
- Repetir cualquiera de las propuestas de la ronda 1 con otro ángulo o color.
- Logos de marcas existentes o parecidos a ellos.

## Pide 5 direcciones REALMENTE distintas entre sí
Algunas ideas posibles (puedes usar otras mejores):
- El **panal cerámico** interior del catalítico visto en corte (celdas cuadradas o hexagonales), que se convierte en un código o en una letra.
- Un **monograma** C + L (o "CL") construido con un recurso propio: un tubo de escape, una etiqueta, una celda.
- La **etiqueta / sticker** con su perforación, como objeto: el registro pegado a la pieza.
- Los **metales preciosos** del catalítico (platino, paladio, rodio): una casilla de tabla periódica propia de la marca.
- La **bitácora**: renglones, check, un libro de registro que también es un código.
- Un recurso tipográfico fuerte: la palabra CataLog con una letra intervenida (la "o" como sección de tubo o celda, la "g" como gancho de etiqueta…).

Para cada dirección, mantén la legibilidad a 48 px y que funcione impresa en negro en papel térmico.

## Colores
Puedes partir de la paleta actual (azul marino #0E2A47, naranja #FF7A1A, gris niebla #F4F6F8) y, si una dirección lo pide, proponer un ajuste; explícalo en sus notas. El nombre sigue siendo "CataLog".

## Entrega
Carpetas `direccion-1/` a `direccion-5/`, cada una con:
1. `icono.svg`: viewBox 0 0 64 64, fondo cuadrado sin esquinas redondeadas; el símbolo dentro del 66 % central; reconocible a 48 px.
2. `simbolo.svg`: solo el símbolo, sin fondo.
3. `logo.svg` (fondo claro), `logo-oscuro.svg` (fondo azul marino) y `logo-bn.svg` (negro puro #000 sobre transparente, sin grises ni líneas de menos de 2 px a 384 px de ancho).
4. `NOTAS.md`: nombre de la dirección, la idea en 2-3 líneas, y en qué se diferencia de las demás.

Y un `propuestas.html` en esta carpeta que muestre las 5 direcciones lado a lado (íconos a 192, 96 y 48 px; logos claro, oscuro y blanco y negro).

## Reglas técnicas
- SVG simple hecho a mano (rect, circle, path), sin imágenes incrustadas ni filtros.
- Texto como `<text>` con font-family "'Space Grotesk', Arial, sans-serif" y font-weight 700, o letras dibujadas como path si la dirección es tipográfica.
- No instales dependencias ni uses internet.
