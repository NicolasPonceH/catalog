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
import 'ficha_screen.dart';

/// Escanea un sticker y abre toda la información de ese catalítico.
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
          titulo: tr('Apunta al sticker', 'Point at the sticker'),
          texto: tr(
            'Sirve el QR o el código de barras. Al leerlo se abre la ficha del catalítico. Con poca luz, toca la linterna (arriba a la derecha de la cámara).',
            'Works with the QR code or barcode. Reading it opens the converter record. In low light, tap the flashlight (top right of the camera).',
          ),
        ),
        PasoGuia(
          clave: _gMano,
          icono: Icons.keyboard_outlined,
          titulo: tr('Sticker dañado', 'Damaged sticker'),
          texto: tr(
            'Si no se lee, escribe el código que aparece impreso, por ejemplo CTL-261121-0007.',
            'If it will not scan, type the printed code, for example CTL-261121-0007.',
          ),
        ),
      ]);

  Future<void> _buscar(String texto) async {
    if (_buscando) return;
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
      detalle: '${compra.tipo} · ${clp(compra.precio)} · ${compra.vendedor}',
    );
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => FichaScreen(id: compra.id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Escanear sticker', 'Scan sticker')),
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
                  'Apunta al QR o al código de barras del sticker.',
                  'Point at the QR code or barcode on the sticker.',
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
