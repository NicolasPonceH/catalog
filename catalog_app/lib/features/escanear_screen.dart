import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../domain/codigo.dart';
import '../domain/formato.dart';
import '../i18n.dart';
import '../system/notificaciones.dart';
import '../theme.dart';
import '../widgets/escaner_vista.dart';
import '../widgets/guia.dart';
import 'ficha_saco_screen.dart';
import 'ficha_screen.dart';
import 'lote_screen.dart';

/// Escanea tanto stickers individuales de catalíticos (`CTL-...`) como
/// Etiquetas Maestras QR / código de barras de sacos o lotes (`LOT-...` / `SUP-...`).
class EscanearScreen extends StatefulWidget {
  const EscanearScreen({super.key});

  @override
  State<EscanearScreen> createState() => _EscanearScreenState();
}

class _EscanearScreenState extends State<EscanearScreen> {
  bool _buscando = false;

  // Partes que ilumina la guía.
  final _gCamara = GlobalKey();
  final _gMano = GlobalKey();

  Future<void> _mostrarGuia() => mostrarGuia(context, [
        PasoGuia(
          clave: _gCamara,
          icono: Icons.qr_code_scanner,
          titulo: tr('Sticker de pieza o de saco', 'Unit or bag sticker'),
          texto: tr(
            'Sirve tanto para el sticker de un catalítico individual como para la Etiqueta QR del Saco / Caja (abre el lote completo o permite auditarlo en Supervisor).',
            'Works for both individual converter stickers and Master Bag / Box QR labels (opens the full batch or lets you audit it in Supervisor Review).',
          ),
        ),
        PasoGuia(
          clave: _gMano,
          icono: Icons.keyboard_outlined,
          titulo: tr('Sticker dañado', 'Damaged sticker'),
          texto: tr(
            'Si no se lee, escribe el código impreso (por ejemplo CTL-261121-0007 o LOT-261125-0001).',
            'If it will not scan, type the printed code (for example CTL-261121-0007 or LOT-261125-0001).',
          ),
        ),
      ]);

  Future<void> _buscar(String texto) async {
    if (_buscando) return;

    // 1. ¿Es la Etiqueta Maestra de un Saco / Lote (LOT-... o SUP-... o QR CATALOG-LOTE)?
    final saco = leerCodigoLoteEscaneado(texto);
    if (saco != null) {
      _buscando = true;
      final scope = AppScope.of(context);
      final d = scope.dispositivo;
      if (d?.vibrar ?? true) HapticFeedback.mediumImpact();
      if (d?.sonar ?? true) SystemSound.play(SystemSoundType.click);

      // Si es un lote de comprador creado en este mismo celular, abre LoteScreen directo.
      if (!saco.esSupervisor) {
        final loteLocal = await scope.lotes.obtener(saco.loteId);
        if (!mounted) return;
        if (loteLocal != null && diaClave(loteLocal.cerradoEn ?? loteLocal.creadoEn) == saco.dia) {
          _buscando = false;
          await Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => LoteScreen(loteId: loteLocal.id)),
          );
          return;
        }
      }

      // Si es un Lote de Supervisor o un saco recibido de otro comprador, abre FichaSacoScreen.
      final pantallaSaco = await FichaSacoScreen.resolver(scope: scope, escaneado: saco);
      if (!mounted) return;
      _buscando = false;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => pantallaSaco),
      );
      return;
    }

    // 2. Catalítico individual (`PREFIJO-AAMMDD-NNNN`)
    final codigo = leerCodigoEscaneado(texto);
    if (codigo == null) {
      avisar(context, tr('Ese código no es de CataLog', 'That code is not from CataLog'));
      return;
    }
    _buscando = true;
    final compra = await AppScope.of(context).compras.buscarPorCodigo(codigo);
    if (!mounted) return;
    _buscando = false;
    if (compra == null) {
      avisar(
        context,
        tr('$codigo no está registrado en este teléfono', '$codigo is not registered on this phone'),
      );
      return;
    }
    final d = AppScope.of(context).dispositivo;
    if (d?.vibrar ?? true) HapticFeedback.mediumImpact();
    if (d?.sonar ?? true) SystemSound.play(SystemSoundType.click);
    Notificaciones.avisarCataliticoEscaneado(
      d,
      codigo: compra.codigo,
      detalle: '${compra.tipoConLlenado} · ${clp(compra.precio)} · ${compra.vendedor}',
    );
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => FichaScreen(id: compra.id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Escanear sticker o saco', 'Scan sticker or bag')),
        actions: [BotonAyuda(alTocar: _mostrarGuia)],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: EscanerVista(key: _gCamara, alLeer: _buscar)),
              const SizedBox(height: 14),
              Text(
                tr(
                  'Apunta al sticker de un catalítico o a la Etiqueta QR de un saco / lote.',
                  'Point at a converter sticker or a Master Bag / Batch QR label.',
                ),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: CatalogColors.acero),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                key: _gMano,
                onPressed: () async {
                  final t = await pedirCodigoManual(context);
                  if (t != null && t.trim().isNotEmpty) await _buscar(t);
                },
                icon: const Icon(Icons.keyboard_outlined),
                label: Text(tr('Escribir el código a mano', 'Type code manually')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
