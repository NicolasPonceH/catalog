import 'package:material_ui/material_ui.dart';

import '../theme.dart';

/// Campo de texto que sugiere valores frecuentes y recientes (vendedores, lugares, autos).
/// Si [mostrarChipsRapidos] es true, muestra pastillas tocables de 1 toque al
/// enfocar o escribir las primeras letras para completar al instante en terreno.
class CampoAutocompletar extends StatefulWidget {
  const CampoAutocompletar({
    super.key,
    required this.controller,
    required this.etiqueta,
    required this.opciones,
    this.icono,
    this.ayuda,
    this.estilo,
    this.validator,
    this.mayusculas = TextCapitalization.sentences,
    this.mostrarChipsRapidos = false,
  });

  final TextEditingController controller;
  final String etiqueta;
  final List<String> opciones;
  final IconData? icono;
  final String? ayuda;
  final TextStyle? estilo;
  final String? Function(String?)? validator;
  final TextCapitalization mayusculas;
  final bool mostrarChipsRapidos;

  @override
  State<CampoAutocompletar> createState() => _CampoAutocompletarState();
}

class _CampoAutocompletarState extends State<CampoAutocompletar> {
  final _foco = FocusNode();

  @override
  void initState() {
    super.initState();
    _foco.addListener(_cambio);
    widget.controller.addListener(_cambio);
  }

  @override
  void didUpdateWidget(covariant CampoAutocompletar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_cambio);
      widget.controller.addListener(_cambio);
    }
  }

  void _cambio() {
    if (mounted && widget.mostrarChipsRapidos) setState(() {});
  }

  @override
  void dispose() {
    _foco.removeListener(_cambio);
    widget.controller.removeListener(_cambio);
    _foco.dispose();
    super.dispose();
  }

  /// Prioriza los que empiezan con lo escrito y luego los que lo contienen.
  List<String> _coincidencias(String texto, {int limite = 6, bool permitirVacio = false}) {
    final t = texto.trim().toLowerCase();
    if (t.isEmpty) {
      return permitirVacio ? widget.opciones.take(limite).toList() : const [];
    }
    final empiezan = <String>[];
    final contienen = <String>[];
    for (final o in widget.opciones) {
      final minus = o.toLowerCase();
      if (minus == t) continue;
      if (minus.startsWith(t)) {
        empiezan.add(o);
      } else if (minus.contains(t)) {
        contienen.add(o);
      }
      if (empiezan.length >= limite) break;
    }
    return [...empiezan, ...contienen].take(limite).toList();
  }

  void _aplicarRapido(String valor) {
    widget.controller.value = TextEditingValue(
      text: valor,
      selection: TextSelection.collapsed(offset: valor.length),
    );
    _foco.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final chips = widget.mostrarChipsRapidos && (_foco.hasFocus || widget.controller.text.trim().isNotEmpty)
        ? _coincidencias(widget.controller.text, limite: 5, permitirVacio: _foco.hasFocus)
        : const <String>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, limites) => RawAutocomplete<String>(
            textEditingController: widget.controller,
            focusNode: _foco,
            optionsBuilder: (valor) => widget.mostrarChipsRapidos
                ? const Iterable<String>.empty()
                : _coincidencias(valor.text, limite: 6),
            fieldViewBuilder: (context, controller, foco, enviar) => TextFormField(
              controller: controller,
              focusNode: foco,
              style: widget.estilo,
              textCapitalization: widget.mayusculas,
              decoration: InputDecoration(
                labelText: widget.etiqueta,
                hintText: widget.ayuda,
                prefixIcon: widget.icono == null ? null : Icon(widget.icono),
              ),
              validator: widget.validator,
              onFieldSubmitted: (_) => enviar(),
            ),
            optionsViewBuilder: (context, elegir, opciones) => Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(10),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: 240, maxWidth: limites.maxWidth),
                  child: ListView(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    children: [
                      for (final o in opciones)
                        ListTile(dense: true, title: Text(o), onTap: () => elegir(o)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (chips.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final opcion in chips)
                  Material(
                    color: CatalogColors.naranja.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(99),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(99),
                      onTap: () => _aplicarRapido(opcion),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(color: CatalogColors.naranja.withValues(alpha: 0.45)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.bolt, size: 14, color: CatalogColors.naranja),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                opcion,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: CatalogColors.texto,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
