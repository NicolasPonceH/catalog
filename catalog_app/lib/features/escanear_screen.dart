import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../domain/codigo.dart';
import '../theme.dart';
import '../widgets/escaner_vista.dart';
import 'ficha_screen.dart';

/// Escanea un sticker y abre toda la información de ese catalítico.
class EscanearScreen extends StatefulWidget {
  const EscanearScreen({super.key});

  @override
  State<EscanearScreen> createState() => _EscanearScreenState();
}

class _EscanearScreenState extends State<EscanearScreen> {
  bool _buscando = false;

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
      appBar: AppBar(title: const Text('Escanear sticker')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: EscanerVista(alLeer: _buscar)),
              const SizedBox(height: 14),
              const Text(
                'Apunta al QR o al código de barras del sticker.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: CatalogColors.acero),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
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
