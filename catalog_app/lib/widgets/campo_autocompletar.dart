import 'package:material_ui/material_ui.dart';

/// Campo de texto que sugiere valores ya usados (vendedores, lugares, autos).
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
  });

  final TextEditingController controller;
  final String etiqueta;
  final List<String> opciones;
  final IconData? icono;
  final String? ayuda;
  final TextStyle? estilo;
  final String? Function(String?)? validator;
  final TextCapitalization mayusculas;

  @override
  State<CampoAutocompletar> createState() => _CampoAutocompletarState();
}

class _CampoAutocompletarState extends State<CampoAutocompletar> {
  final _foco = FocusNode();

  @override
  void dispose() {
    _foco.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, limites) => RawAutocomplete<String>(
        textEditingController: widget.controller,
        focusNode: _foco,
        optionsBuilder: (valor) {
          final t = valor.text.trim().toLowerCase();
          if (t.isEmpty) return const Iterable<String>.empty();
          return widget.opciones
              .where((o) => o.toLowerCase().contains(t) && o.toLowerCase() != t)
              .take(6);
        },
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
    );
  }
}
