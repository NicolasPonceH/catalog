import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_scope.dart';
import '../data/compra.dart';
import '../domain/formato.dart';
import '../printing/etiqueta.dart';
import '../printing/imprimir.dart';
import '../system/confirmar.dart';
import '../theme.dart';
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
          titulo: 'Código único',
          texto: 'Prefijo del teléfono, día de compra y número de pieza de ese día. Es el mismo que va en el sticker.',
        ),
        PasoGuia(
          clave: _gFecha,
          icono: Icons.event,
          titulo: 'Cuándo se compró',
          texto: 'La fecha y hora de compra. Abajo dice cuándo se anotó y, si alguien la corrigió, cuándo fue.',
        ),
        PasoGuia(
          clave: _gSticker,
          icono: Icons.sticky_note_2_outlined,
          titulo: 'Vista del sticker',
          texto: 'Así sale impreso: QR, código de barras, fecha y tipo. El precio no va en el sticker.',
        ),
        PasoGuia(
          clave: _gImprimir,
          icono: Icons.print_outlined,
          titulo: 'Imprimir',
          texto: 'Lo manda a tu impresora Bluetooth (se elige en Ajustes). Arriba ves cuántas veces se imprimió.',
        ),
        PasoGuia(
          clave: _gCompartir,
          icono: Icons.share_outlined,
          titulo: 'Compartir como imagen',
          texto: 'Si la impresora no conecta, manda el sticker como imagen e imprímelo con la app de la impresora.',
        ),
        PasoGuia(
          clave: _gDetalles,
          icono: Icons.list_alt,
          titulo: 'Datos de la compra',
          texto: 'Vendedor, lugar, precio, tipo, código de fábrica y autos.',
        ),
        PasoGuia(
          clave: _gMapa,
          icono: Icons.map_outlined,
          titulo: 'Dónde se compró',
          texto: 'Abre el mapa en el punto GPS que se guardó al registrar la compra.',
        ),
        PasoGuia(
          clave: _gCorregir,
          icono: Icons.edit_outlined,
          titulo: 'Corregir',
          texto: 'Cambia cualquier dato. El código no cambia, porque puede estar impreso.',
        ),
        PasoGuia(
          clave: _gMenu,
          icono: Icons.block,
          titulo: 'Anular',
          texto: 'Una compra no se borra: se anula. Sale de los totales, queda en el historial y pide tu huella.',
        ),
      ]);

  @override
  void initState() {
    super.initState();
    if (widget.recienCreada) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) avisar(context, 'Compra guardada');
      });
    }
  }

  Future<void> _abrirMapa(Compra c) async {
    final geo = Uri.parse('geo:${c.lat},${c.lng}?q=${c.lat},${c.lng}');
    final web = Uri.parse('https://www.google.com/maps/search/?api=1&query=${c.lat},${c.lng}');
    try {
      if (await launchUrl(geo)) return;
    } catch (_) {}
    try {
      await launchUrl(web, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) avisar(context, 'No hay una app de mapas instalada');
    }
  }

  Future<void> _anular(Compra c) async {
    final motivo = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Anular compra'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('La compra sale de los totales, pero queda en el historial. '
                'Su código no se vuelve a usar.'),
            const SizedBox(height: 12),
            TextField(
              controller: motivo,
              decoration: const InputDecoration(labelText: 'Motivo (opcional)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Anular')),
        ],
      ),
    );
    final texto = motivo.text;
    motivo.dispose();
    if (ok != true || !mounted) return;
    if (!await confirmarConHuella(context, 'Confirma para anular ${c.codigo}')) return;
    if (mounted) await AppScope.of(context).compras.anular(c.id, texto);
  }

  Future<void> _reactivar(Compra c) async {
    await AppScope.of(context).compras.reactivar(c.id);
    if (mounted) avisar(context, 'La compra vuelve a contar en los totales');
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
            appBar: AppBar(title: const Text('Catalítico')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        return Scaffold(
          appBar: AppBar(
            title: const Text('Catalítico'),
            actions: [
              BotonAyuda(alTocar: _mostrarGuia),
              // En una sesión de revisión los datos son de otro celular: no se corrigen.
              if (!AppScope.of(context).soloLectura) ...[
                IconButton(
                  key: _gCorregir,
                  tooltip: 'Corregir',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => abrir(context, CompraFormScreen(existente: c)),
                ),
                PopupMenuButton<String>(
                  key: _gMenu,
                  onSelected: (v) => v == 'anular' ? _anular(c) : _reactivar(c),
                  itemBuilder: (_) => [
                    if (!c.anulada) const PopupMenuItem(value: 'anular', child: Text('Anular compra')),
                    if (c.anulada) const PopupMenuItem(value: 'reactivar', child: Text('Reactivar compra')),
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
                Center(child: SelectableText(key: _gCodigo, c.codigo, style: mono(size: 24))),
                const SizedBox(height: 14),
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
                    label: const Text('Ver dónde se compró'),
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

  Widget _avisoAnulada(Compra c) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Card(
          color: const Color(0xFFFCEBEB),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Text(
              'Compra anulada${c.anuladaEn != null ? ' el ${fechaHora(c.anuladaEn!)}' : ''}'
              '${c.motivoAnulacion.isNotEmpty ? ': ${c.motivoAnulacion}' : ''}. '
              'No cuenta en los totales.',
              style: const TextStyle(color: CatalogColors.rojo, fontSize: 14),
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
                    const Text('Comprado el', style: etiqueta),
                    Text(capitalizar(fechaLarga(c.fechaCompra)),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    Text('a las ${hora(c.fechaCompra)}', style: mono(size: 18)),
                    const SizedBox(height: 6),
                    Text('Anotado el ${fechaHora(c.creadoEn)}', style: etiqueta),
                    if (c.fechaCompraEditadaEn != null)
                      Text(
                        'Fecha de compra corregida el ${fechaHora(c.fechaCompraEditadaEn!)}',
                        style: const TextStyle(fontSize: 13, color: Color(0xFFB35300)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  Widget _detalles(Compra c) {
    Widget fila(String k, String v, {bool esMono = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 130, child: Text(k, style: etiqueta)),
              Expanded(
                child: Text(
                  v.isEmpty ? '—' : v,
                  style: esMono ? mono(size: 15) : const TextStyle(fontSize: 15),
                ),
              ),
            ],
          ),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Column(
          children: [
            fila('Vendedor', c.vendedor),
            fila('Lugar', c.lugar),
            fila('Precio', clp(c.precio), esMono: true),
            fila('Tipo', c.tipo),
            fila('Código de fábrica', c.codigoFabrica, esMono: true),
            fila('Autos', c.autos),
            if (c.notas.isNotEmpty) fila('Notas', c.notas),
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
        child: Image.file(archivo, height: 220, fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const SizedBox(
                height: 60, child: Center(child: Text('No se encontró la foto', style: etiqueta)))),
      ),
    );
  }

  Widget _tarjetaSticker(Compra c) {
    final datos = DatosEtiqueta.deCompra(c);
    final veces = c.impresiones == 1 ? '1 vez' : '${c.impresiones} veces';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(child: Text('Sticker', style: etiqueta)),
                if (c.impresiones > 0) Text('Impreso $veces', style: etiqueta),
              ],
            ),
            const SizedBox(height: 8),
            EtiquetaVista(key: _gSticker, datos: datos),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: _gImprimir,
              onPressed: c.anulada ? null : () => imprimirSticker(context, datos, compraId: c.id),
              icon: const Icon(Icons.print_outlined),
              label: Text(c.impresiones == 0 ? 'Imprimir sticker' : 'Reimprimir sticker'),
            ),
            TextButton.icon(
              key: _gCompartir,
              onPressed: () async {
                try {
                  await compartirSticker(datos);
                } catch (e) {
                  if (mounted) avisar(context, 'No se pudo compartir: $e');
                }
              },
              icon: const Icon(Icons.share_outlined),
              label: const Text('Compartir sticker como imagen'),
            ),
          ],
        ),
      ),
    );
  }
}
