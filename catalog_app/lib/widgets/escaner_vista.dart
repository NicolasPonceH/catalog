import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../i18n.dart';

/// Cámara que lee el QR o el código de barras del sticker.
/// No repite el mismo código si se queda frente a la cámara.
class EscanerVista extends StatefulWidget {
  const EscanerVista({super.key, required this.alLeer});

  final void Function(String texto) alLeer;

  @override
  State<EscanerVista> createState() => _EscanerVistaState();
}

class _EscanerVistaState extends State<EscanerVista> {
  final _control = MobileScannerController(
    formats: const [BarcodeFormat.qrCode, BarcodeFormat.code128],
  );
  String? _ultimo;
  DateTime _ultimoEn = DateTime(2000);
  bool _linterna = false;

  void _detectar(BarcodeCapture captura) {
    for (final b in captura.barcodes) {
      final texto = b.rawValue;
      if (texto == null || texto.isEmpty) continue;
      final ahora = DateTime.now();
      if (texto == _ultimo && ahora.difference(_ultimoEn) < const Duration(seconds: 3)) return;
      _ultimo = texto;
      _ultimoEn = ahora;
      widget.alLeer(texto);
      return;
    }
  }

  @override
  void dispose() {
    _control.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ColoredBox(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            MobileScanner(
              controller: _control,
              onDetect: _detectar,
              errorBuilder: (context, error) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    error.errorCode == MobileScannerErrorCode.permissionDenied
                        ? tr(
                            'CataLog no tiene permiso para usar la cámara. Actívalo en Ajustes de Android > Apps > CataLog > Permisos.',
                            'CataLog does not have camera permission. Enable it in Android Settings > Apps > CataLog > Permissions.',
                          )
                        : tr('No se pudo abrir la cámara.', 'Could not open camera.'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4),
                  ),
                ),
              ),
            ),
            IgnorePointer(
              child: Center(
                child: Container(
                  width: 250,
                  height: 160,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white, width: 3),
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 8,
              top: 8,
              child: IconButton.filledTonal(
                tooltip: tr('Linterna', 'Flashlight'),
                icon: Icon(_linterna ? Icons.flashlight_off : Icons.flashlight_on),
                onPressed: () {
                  _control.toggleTorch();
                  setState(() => _linterna = !_linterna);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Diálogo para escribir el código a mano (si el sticker está dañado).
Future<String?> pedirCodigoManual(BuildContext context) {
  final control = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(tr('Escribir código', 'Enter code')),
      content: TextField(
        controller: control,
        autofocus: true,
        textCapitalization: TextCapitalization.characters,
        decoration: const InputDecoration(hintText: 'CTL-261121-0007'),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Cancelar', 'Cancel'))),
        TextButton(onPressed: () => Navigator.pop(context, control.text), child: Text(tr('Buscar', 'Search'))),
      ],
    ),
  ).whenComplete(control.dispose);
}
