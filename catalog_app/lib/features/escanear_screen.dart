import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../domain/codigo.dart';
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
          titulo: 'Apunta al sticker',
          texto: 'Sirve el QR o el código de barras. Al leerlo se abre la ficha del catalítico. '
              'Con poca luz, toca la linterna (arriba a la derecha de la cámara).',
        ),
        PasoGuia(
          clave: _gMano,
          icono: Icons.keyboard_outlined,
          titulo: 'Sticker dañado',
          texto: 'Si no se lee, escribe el código que aparece impreso, por ejemplo CTL-261121-0007.',
        ),
      ]);

  Future<void> _buscar(String texto) async {
    if (_buscando) return;
    final codigo = leerCodigoEscaneado(texto);
    if (codigo == null) {
      avisar(context, 'Ese código no es de CataLog');
      return;
    }
    _buscando = true;
    final compra = await AppScope.of(context).compras.buscarPorCodigo(codigo);
    if (!mounted) return;
    _buscando = false;
    if (compra == null) {
      avisar(context, '$codigo no está registrado en este teléfono');
      return;
    }
    HapticFeedback.mediumImpact();
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => FichaScreen(id: compra.id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Escanear sticker'),
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
              const Text(
                'Apunta al QR o al código de barras del sticker.',
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
                label: const Text('Escribir el código a mano'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
