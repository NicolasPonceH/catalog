import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_scope.dart';
import '../data/compra.dart';
import '../domain/formato.dart';
import '../i18n.dart';
import '../printing/etiqueta.dart';
import '../printing/imprimir.dart';
import '../system/confirmar.dart';
import '../theme.dart';
import '../widgets/compra_tile.dart';
import '../widgets/consulta.dart';
import '../widgets/guia.dart';
import 'compra_form_screen.dart';

/// Toda la información de un catalítico. La fecha de compra va arriba.
class FichaScreen extends StatefulWidget {
  const FichaScreen({super.key, required this.id, this.recienCreada = false});

  final int id;
  final bool recienCreada;

  @override
  State<FichaScreen> createState() => _FichaScreenState();
}

class _FichaScreenState extends State<FichaScreen> {
  // Partes que ilumina la guía.
  final _gCodigo = GlobalKey();
  final _gFecha = GlobalKey();
  final _gSticker = GlobalKey();
  final _gImprimir = GlobalKey();
  final _gCompartir = GlobalKey();
  final _gDetalles = GlobalKey();
  final _gMapa = GlobalKey();
  final _gCorregir = GlobalKey();
  final _gMenu = GlobalKey();

  Future<void> _mostrarGuia() => mostrarGuia(context, [
        PasoGuia(
          clave: _gCodigo,
          icono: Icons.qr_code_2,
          titulo: tr('Código único', 'Unique code'),
          texto: tr(
            'Prefijo del teléfono, día de compra y número de pieza de ese día. Es el mismo que va en el sticker.',
            'Phone prefix, purchase date, and daily unit number. Matches the code printed on the sticker.',
          ),
        ),
        PasoGuia(
          clave: _gFecha,
          icono: Icons.event,
          titulo: tr('Cuándo se compró', 'When it was bought'),
          texto: tr(
            'La fecha y hora de compra. Abajo dice cuándo se anotó y, si alguien la corrigió, cuándo fue.',
            'Purchase date and time. Below it shows when it was logged and whether the date was later edited.',
          ),
        ),
        PasoGuia(
          clave: _gSticker,
          icono: Icons.sticky_note_2_outlined,
          titulo: tr('Vista del sticker', 'Sticker preview'),
          texto: tr(
            'Así sale impreso: QR, código de barras, fecha y tipo. El precio no va en el sticker.',
            'Exact print preview: QR code, barcode, date, and type. The price is never printed on the sticker.',
          ),
        ),
        PasoGuia(
          clave: _gImprimir,
          icono: Icons.print_outlined,
          titulo: tr('Imprimir sticker', 'Print sticker'),
          texto: tr(
            'Lo manda por Bluetooth a tu impresora térmica. La primera vez, elígela en Ajustes.',
            'Sends the label over Bluetooth to your thermal printer. Select your printer in Settings the first time.',
          ),
        ),
        PasoGuia(
          clave: _gCompartir,
          icono: Icons.share_outlined,
          titulo: tr('Compartir como imagen', 'Share as image'),
          texto: tr(
            'Si una impresora no conecta directo, compártelo como imagen e imprímelo con la app de la impresora.',
            'If a printer won’t connect directly, share the label as an image and print it through the printer’s own app.',
          ),
        ),
        PasoGuia(
          clave: _gDetalles,
          icono: Icons.list_alt,
          titulo: tr('Datos de la compra', 'Purchase details'),
          texto: tr(
            'Vendedor, lugar, precio, tipo, código de fábrica y de qué autos es.',
            'Seller, location, price, type, factory code, and compatible vehicles.',
          ),
        ),
        PasoGuia(
          clave: _gMapa,
          icono: Icons.map_outlined,
          titulo: tr('Ver dónde se compró', 'View purchase location'),
          texto: tr(
            'Abre el punto exacto del GPS en el mapa del teléfono.',
            'Opens the exact GPS coordinates in your phone’s map app.',
          ),
        ),
        PasoGuia(
          clave: _gCorregir,
          icono: Icons.edit_outlined,
          titulo: tr('Corregir', 'Edit'),
          texto: tr(
            'Cambia algún dato que haya quedado mal escrito.',
            'Fix any field that was entered with a typo.',
          ),
        ),
        PasoGuia(
          clave: _gMenu,
          icono: Icons.more_vert,
          titulo: tr('Anular', 'Void'),
          texto: tr(
            'Nada se borra: si te equivocaste, la compra se anula (pide tu huella) y deja de sumar en los totales.',
            'Nothing is ever erased: voiding a purchase (with your fingerprint) excludes it from totals while preserving history.',
          ),
        ),
      ]);

  @override
  void initState() {
    super.initState();
    if (widget.recienCreada) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) avisar(context, tr('Compra guardada. Imprime el sticker.', 'Purchase saved. Print its sticker.'));
      });
    }
  }

  Future<void> _abrirMapa(Compra c) async {
    final uri = Uri.parse('geo:${c.lat},${c.lng}?q=${c.lat},${c.lng}(${Uri.encodeComponent(c.codigo)})');
    final web = Uri.parse('https://www.google.com/maps/search/?api=1&query=${c.lat},${c.lng}');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      await launchUrl(web, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _anular(Compra c) async {
    final motivo = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('¿Anular esta compra?', 'Void this purchase?')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr(
                'La compra queda guardada en el historial como anulada y deja de sumar en los reportes. Su código no se vuelve a usar.',
                'The purchase stays in history marked as voided and stops counting toward reports. Its code will not be reused.',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: motivo,
              decoration: InputDecoration(labelText: tr('Motivo (opcional)', 'Reason (optional)')),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Cancelar', 'Cancel'))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('Anular compra', 'Void purchase'))),
        ],
      ),
    );
    final textoMotivo = motivo.text;
    motivo.dispose();
    if (ok != true || !mounted) return;
    if (!await confirmarConHuella(context, tr('Confirma para anular ${c.codigo}', 'Confirm to void ${c.codigo}'))) return;
    if (!mounted) return;
    await AppScope.of(context).compras.anular(c.id, textoMotivo);
    if (mounted) avisar(context, tr('Compra anulada', 'Purchase voided'));
  }

  Future<void> _reactivar(Compra c) async {
    await AppScope.of(context).compras.reactivar(c.id);
    if (mounted) {
      avisar(context, tr('La compra vuelve a contar en los totales', 'Purchase restored to totals'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = AppScope.of(context).compras;
    return Consulta<Compra?>(
      claves: [widget.id],
      cargar: () => repo.obtener(widget.id),
      builder: (context, c) {
        if (c == null) {
          return Scaffold(
            appBar: AppBar(title: Text(tr('Catalítico', 'Converter'))),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(tr('Catalítico', 'Converter')),
            actions: [
              BotonAyuda(alTocar: _mostrarGuia),
              // En una sesión de revisión los datos son de otro celular: no se corrigen.
              if (!AppScope.of(context).soloLectura) ...[
                IconButton(
                  key: _gCorregir,
                  tooltip: tr('Corregir', 'Edit'),
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => abrir(context, CompraFormScreen(existente: c)),
                ),
                PopupMenuButton<String>(
                  key: _gMenu,
                  onSelected: (v) => v == 'anular' ? _anular(c) : _reactivar(c),
                  itemBuilder: (_) => [
                    if (!c.anulada) PopupMenuItem(value: 'anular', child: Text(tr('Anular compra', 'Void purchase'))),
                    if (c.anulada) PopupMenuItem(value: 'reactivar', child: Text(tr('Reactivar compra', 'Restore purchase'))),
                  ],
                ),
              ],
            ],
          ),
          body: SafeArea(
            child: ListView(
              scrollCacheExtent: const ScrollCacheExtent.pixels(4000), // construye toda la ficha, para la guía
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
              children: [
                if (c.anulada) _avisoAnulada(c),
                _encabezado(c),
                const SizedBox(height: 12),
                KeyedSubtree(key: _gFecha, child: _tarjetaFecha(c)),
                const SizedBox(height: 12),
                _tarjetaSticker(c),
                const SizedBox(height: 12),
                KeyedSubtree(key: _gDetalles, child: _detalles(c)),
                if (c.tieneUbicacion) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: _gMapa,
                    onPressed: () => _abrirMapa(c),
                    icon: const Icon(Icons.map_outlined),
                    label: Text(tr('Ver dónde se compró', 'View purchase location')),
                  ),
                ],
                if (c.fotoPath != null) ...[
                  const SizedBox(height: 12),
                  _foto(c.fotoPath!),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  /// Tarjeta principal azul marino con distintivo de material, código y precio.
  Widget _encabezado(Compra c) {
    return Container(
      key: _gCodigo,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CatalogColors.marino,
        borderRadius: BorderRadius.circular(18),
        border: CatalogColors.paleta.oscura || CatalogColors.paleta.grosorBorde > 1
            ? Border.all(color: CatalogColors.borde, width: CatalogColors.paleta.grosorBorde)
            : null,
      ),
      child: Row(
        children: [
          MarcaTipo(material: c.material, anulada: c.anulada, tamano: 44),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: SelectableText(c.codigo, style: mono(size: 21, color: CatalogColors.niebla)),
                ),
                const SizedBox(height: 3),
                Text(c.tipo, style: const TextStyle(color: Color(0xB3FFFFFF), fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              clp(c.precio),
              style: mono(size: 22, color: c.anulada ? const Color(0x99FFFFFF) : CatalogColors.naranja).copyWith(
                decoration: c.anulada ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _avisoAnulada(Compra c) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Card(
          color: CatalogColors.rojo.withValues(alpha: 0.12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Text(
              tr(
                'Compra anulada${c.anuladaEn != null ? ' el ${fechaHora(c.anuladaEn!)}' : ''}${c.motivoAnulacion.isNotEmpty ? ': ${c.motivoAnulacion}' : ''}. No cuenta en los totales.',
                'Purchase voided${c.anuladaEn != null ? ' on ${fechaHora(c.anuladaEn!)}' : ''}${c.motivoAnulacion.isNotEmpty ? ': ${c.motivoAnulacion}' : ''}. Excluded from totals.',
              ),
              style: TextStyle(color: CatalogColors.rojo, fontSize: 14),
            ),
          ),
        ),
      );

  Widget _tarjetaFecha(Compra c) => Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: CatalogColors.naranja, width: 1.5),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.event, color: CatalogColors.naranja, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('Comprado el', 'Purchased on'), style: etiqueta),
                    Text(capitalizar(fechaLarga(c.fechaCompra)),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    Text('${tr('a las', 'at')} ${hora(c.fechaCompra)}', style: mono(size: 18)),
                    const SizedBox(height: 6),
                    Text('${tr('Anotado el', 'Logged on')} ${fechaHora(c.creadoEn)}', style: etiqueta),
                    if (c.fechaCompraEditadaEn != null)
                      Text(
                        '${tr('Fecha de compra corregida el', 'Purchase date edited on')} ${fechaHora(c.fechaCompraEditadaEn!)}',
                        style: TextStyle(
                            fontSize: 13,
                            color: CatalogColors.paleta.oscura ? CatalogColors.naranja : const Color(0xFFB35300)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  Widget _detalles(Compra c) {
    final filas = <(String, String, bool)>[
      (tr('Vendedor', 'Seller'), c.vendedor, false),
      (tr('Lugar', 'Location'), c.lugar, false),
      (tr('Precio', 'Price'), clp(c.precio), true),
      (tr('Tipo', 'Type'), c.tipo, false),
      (tr('Código de fábrica', 'Factory code'), c.codigoFabrica, true),
      (tr('Autos', 'Vehicles'), c.autos, false),
      if (c.notas.isNotEmpty) (tr('Notas', 'Notes'), c.notas, false),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Column(
          children: [
            for (var i = 0; i < filas.length; i++) ...[
              if (i > 0) Divider(height: 1, color: CatalogColors.borde),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 130, child: Text(filas[i].$1, style: etiqueta)),
                    Expanded(
                      child: Text(
                        filas[i].$2.isEmpty ? '—' : filas[i].$2,
                        style: filas[i].$3 ? mono(size: 15) : const TextStyle(fontSize: 15),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _foto(String relativa) {
    final archivo = File(AppScope.of(context).fotos.archivo(relativa).path);
    return GestureDetector(
      onTap: () => abrir(
        context,
        Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(backgroundColor: Colors.black),
          body: Center(child: InteractiveViewer(child: Image.file(archivo))),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(
          archivo,
          height: 220,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => SizedBox(
            height: 60,
            child: Center(child: Text(tr('No se encontró la foto', 'Photo not found'), style: etiqueta)),
          ),
        ),
      ),
    );
  }

  Widget _tarjetaSticker(Compra c) {
    final datos = DatosEtiqueta.deCompra(c);
    final veces = c.impresiones == 1 ? tr('1 vez', '1 time') : tr('${c.impresiones} veces', '${c.impresiones} times');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text('Sticker', style: etiqueta)),
                if (c.impresiones > 0) Text('${tr('Impreso', 'Printed')} $veces', style: etiqueta),
              ],
            ),
            const SizedBox(height: 8),
            EtiquetaVista(key: _gSticker, datos: datos),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: _gImprimir,
              onPressed: c.anulada ? null : () => imprimirSticker(context, datos, compraId: c.id),
              icon: const Icon(Icons.print_outlined),
              label: Text(
                c.impresiones == 0 ? tr('Imprimir sticker', 'Print sticker') : tr('Reimprimir sticker', 'Reprint sticker'),
              ),
            ),
            TextButton.icon(
              key: _gCompartir,
              onPressed: () async {
                try {
                  await compartirSticker(datos);
                } catch (e) {
                  if (mounted) avisar(context, '${tr('No se pudo compartir', 'Could not share')}: $e');
                }
              },
              icon: const Icon(Icons.share_outlined),
              label: Text(tr('Compartir sticker como imagen', 'Share sticker as image')),
            ),
          ],
        ),
      ),
    );
  }
}
