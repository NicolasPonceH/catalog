import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../app_scope.dart';
import '../backup/respaldo.dart';
import '../data/sesiones.dart';
import '../domain/formato.dart';
import '../system/confirmar.dart';
import '../system/sistema.dart';
import '../theme.dart';

// Respaldo, traspaso a otro celular y sesiones. Se usan desde el Inicio
// (botón de accesos directos) y desde Ajustes.

String _dos(int n) => n.toString().padLeft(2, '0');
String _sello(DateTime t) => '${t.year}${_dos(t.month)}${_dos(t.day)}-${_dos(t.hour)}${_dos(t.minute)}';

Future<File> _archivoTemporal(String nombre, List<int> bytes) async {
  final archivo = File(p.join((await getTemporaryDirectory()).path, nombre));
  await archivo.writeAsBytes(bytes, flush: true);
  return archivo;
}

Future<ShareResult> _compartirZip(File archivo, String texto) => SharePlus.instance.share(ShareParams(
      files: [XFile(archivo.path, mimeType: 'application/zip')],
      text: texto,
    ));

/// Respaldo completo (compras + fotos). Se guarda en Descargas/Respaldo CataLog
/// y después se ofrece enviarlo también (correo, Drive, WhatsApp).
Future<void> crearRespaldoYEnviar(BuildContext context) async {
  final scope = AppScope.of(context);
  if (scope.soloLectura) {
    avisar(context, 'Los respaldos se hacen desde tu sesión de compra');
    return;
  }
  avisar(context, 'Preparando respaldo…');
  try {
    final zip = await armarRespaldo(scope.base, scope.fotos.carpetaBase);
    final prefijo = await scope.compras.prefijo();
    final nombre = 'CataLog-respaldo-$prefijo-${_sello(DateTime.now())}.zip';
    String? lugar;
    try {
      lugar = await Sistema.guardarEnDescargas(nombre, zip, prefijoBorrar: 'CataLog-respaldo-', conservar: 10);
    } catch (_) {
      lugar = null;
    }
    if (lugar != null) await scope.compras.registrarRespaldo();
    if (!context.mounted) return;
    final enviar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(lugar != null ? Icons.check_circle : Icons.warning_amber,
            color: lugar != null ? CatalogColors.verde : CatalogColors.rojo, size: 36),
        title: Text(lugar != null ? 'Respaldo guardado' : 'No se pudo guardar en el teléfono'),
        content: Text(
          lugar != null
              ? 'Quedó en $lugar. Para protegerte si se pierde el teléfono, envíalo también a tu correo, Drive o WhatsApp.'
              : 'Puedes enviarlo directamente a tu correo, Drive o WhatsApp.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Listo')),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size(120, 44)),
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.share_outlined),
            label: const Text('Enviar'),
          ),
        ],
      ),
    );
    if (enviar != true) return;
    final archivo = await _archivoTemporal(nombre, zip);
    final r = await _compartirZip(archivo, 'Respaldo de CataLog');
    if (r.status != ShareResultStatus.dismissed) await scope.compras.registrarRespaldo();
  } catch (e) {
    if (context.mounted) avisar(context, 'No se pudo crear el respaldo: $e');
  }
}

String _tamano(int bytes) =>
    bytes >= 1024 * 1024 ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB' : '${(bytes / 1024).ceil()} KB';

/// Elige un archivo de CataLog: primero los de la carpeta Respaldo CataLog,
/// o cualquier otro con el selector de archivos. Devuelve sus bytes.
Future<List<int>?> elegirArchivoCatalog(BuildContext context, {required String titulo}) async {
  var lista = <ArchivoRespaldo>[];
  try {
    lista = await Sistema.listarRespaldos();
  } catch (_) {}
  if (!context.mounted) return null;
  final eleccion = await showModalBottomSheet<Object>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (hoja) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(hoja).size.height * 0.75),
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text(titulo, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                lista.isEmpty
                    ? 'No hay respaldos en Descargas/$carpetaRespaldos. Búscalo en otra carpeta.'
                    : 'En Descargas/$carpetaRespaldos:',
                style: etiqueta,
              ),
            ),
            for (final a in lista)
              ListTile(
                leading: Icon(a.esAutomatico ? Icons.schedule : Icons.inventory_2_outlined, color: CatalogColors.texto),
                title: Text(a.esAutomatico ? 'Copia automática' : 'Respaldo', style: const TextStyle(fontWeight: FontWeight.w500)),
                subtitle: Text('${fechaHora(a.fecha)} · ${_tamano(a.tamano)}\n${a.nombre}', style: etiqueta),
                isThreeLine: true,
                onTap: () => Navigator.pop(hoja, a),
              ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.folder_open_outlined),
              title: const Text('Buscar otro archivo'),
              subtitle: const Text('WhatsApp, Drive, otra carpeta…'),
              onTap: () => Navigator.pop(hoja, 'otro'),
            ),
          ],
        ),
      ),
    ),
  );
  if (eleccion == null) return null;
  try {
    if (eleccion is ArchivoRespaldo) return await Sistema.leerArchivo(eleccion.uri);
    final elegido = await FilePicker.pickFile(type: FileType.any);
    return elegido == null ? null : await elegido.readAsBytes();
  } catch (e) {
    if (context.mounted) avisar(context, 'No se pudo leer el archivo: $e');
    return null;
  }
}

/// Manda todas las compras a otro celular, que las abre como sesión de revisión.
Future<void> enviarAOtroCelular(BuildContext context) async {
  final scope = AppScope.of(context);
  if (scope.soloLectura) {
    avisar(context, 'Vuelve a tu sesión de compra para enviar tus compras');
    return;
  }
  final conFotos = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Enviar mis compras a otro celular'),
      content: const Text(
        'El otro celular las abre en CataLog como sesión de revisión: puede escanear tus '
        'stickers y ver cada ficha, sin mezclarlas con sus propias compras.\n\n'
        '¿Incluir las fotos? Con fotos el archivo pesa más.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Sin fotos')),
        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Con fotos')),
      ],
    ),
  );
  if (conFotos == null || !context.mounted) return;
  avisar(context, 'Preparando el archivo…');
  try {
    final zip = await armarRespaldo(scope.base, scope.fotos.carpetaBase, incluirFotos: conFotos, tipo: 'traspaso');
    final prefijo = await scope.compras.prefijo();
    final nombre = await scope.compras.leerAjuste('nombre') ?? '';
    final archivo = await _archivoTemporal('CataLog-datos-$prefijo-${_sello(DateTime.now())}.zip', zip);
    await _compartirZip(
      archivo,
      'Compras de CataLog${nombre.isNotEmpty ? ' de $nombre' : ''}. '
      'Abre este archivo con CataLog para revisarlas y escanear los stickers.',
    );
  } catch (e) {
    if (context.mounted) avisar(context, 'No se pudo preparar el archivo: $e');
  }
}

/// Abre un archivo de CataLog recibido (elegido a mano o tocado en WhatsApp)
/// y pregunta si se revisa aparte o si reemplaza las compras.
Future<void> recibirDatos(BuildContext context, [List<int>? bytes]) async {
  final scope = AppScope.of(context);
  bytes ??= await elegirArchivoCatalog(context, titulo: 'Elige el archivo de CataLog');
  if (bytes == null) return;
  ContenidoRespaldo contenido;
  try {
    contenido = leerRespaldo(bytes);
  } on RespaldoInvalido catch (e) {
    if (context.mounted) avisar(context, e.mensaje);
    return;
  }
  if (!context.mounted) return;
  final quien = contenido.nombre.isNotEmpty
      ? contenido.nombre
      : (contenido.prefijo.isNotEmpty ? 'el teléfono ${contenido.prefijo}' : 'otro celular');
  final creado = contenido.creado;
  final eleccion = await showDialog<String>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('Datos de CataLog recibidos'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
          child: Text(
            'Archivo de $quien${creado != null ? ' del ${fechaHora(creado)}' : ''}: '
            '${contenido.compras} compras.',
            style: const TextStyle(fontSize: 15, height: 1.4),
          ),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, 'revisar'),
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.fact_check_outlined, color: CatalogColors.texto),
            title: Text('Abrir para revisar'),
            subtitle: Text('Se guarda aparte, como sesión de revisión. Tus compras no se tocan.'),
          ),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, 'restaurar'),
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.settings_backup_restore, color: CatalogColors.rojo),
            title: Text('Reemplazar mis compras'),
            subtitle: Text('Úsalo como respaldo: tus compras actuales se reemplazan por estas.'),
          ),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar', textAlign: TextAlign.right),
        ),
      ],
    ),
  );
  if (!context.mounted || eleccion == null) return;
  if (eleccion == 'revisar') {
    await scope.acciones?.recibirRevision(contenido);
  } else {
    await restaurarDesdeContenido(context, contenido);
  }
}

/// Elige un respaldo (de la carpeta Respaldo CataLog u otro lugar), lo extrae y
/// con él se vuelven a poblar las compras de la sesión de compra.
Future<void> restaurarDesdeArchivo(BuildContext context) async {
  final bytes = await elegirArchivoCatalog(context, titulo: 'Elige el respaldo');
  if (bytes == null || !context.mounted) return;
  try {
    final contenido = leerRespaldo(bytes);
    if (context.mounted) await restaurarDesdeContenido(context, contenido);
  } on RespaldoInvalido catch (e) {
    if (context.mounted) avisar(context, e.mensaje);
  }
}

/// Reemplaza las compras propias por las del respaldo, guardando antes una copia.
Future<void> restaurarDesdeContenido(BuildContext context, ContenidoRespaldo contenido) async {
  final scope = AppScope.of(context);
  final acciones = scope.acciones;
  if (acciones == null) return;
  if (scope.soloLectura) {
    avisar(context, 'Vuelve a tu sesión de compra para restaurar un respaldo');
    return;
  }
  final actuales = await scope.compras.contarCompras();
  if (!context.mounted) return;
  final creado = contenido.creado;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Reemplazar mis compras'),
      content: Text(
        'El archivo${creado != null ? ' es del ${fechaHora(creado)} y' : ''} tiene '
        '${contenido.compras} compras'
        '${contenido.prefijo.isNotEmpty ? ' (prefijo ${contenido.prefijo})' : ''}.\n\n'
        'Va a reemplazar las compras de este teléfono ($actuales). Antes se guarda una '
        'copia de lo actual dentro del teléfono, por si acaso.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Reemplazar')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  if (!await confirmarConHuella(context, 'Confirma para reemplazar tus compras')) return;
  if (!context.mounted) return;
  try {
    await guardarCopiaLocal(await armarRespaldo(scope.base, scope.fotos.carpetaBase), scope.fotos.carpetaBase);
  } catch (e) {
    if (context.mounted) avisar(context, 'No se pudo guardar la copia de seguridad, no se cambió nada: $e');
    return;
  }
  await acciones.reemplazarDatos(
    (ruta) => aplicarRespaldo(contenido, rutaBase: ruta, carpetaBase: scope.fotos.carpetaBase),
    mensaje: 'Datos restaurados: ${contenido.compras} compras',
  );
}

/// Lista de sesiones: la de compra y las de revisión recibidas.
Future<void> mostrarSesiones(BuildContext context) async {
  final scope = AppScope.of(context);
  final sesiones = scope.sesiones;
  final acciones = scope.acciones;
  if (sesiones == null || acciones == null) return;
  final revisiones = await sesiones.revisiones();
  if (!context.mounted) return;
  final actual = scope.sesion?.id ?? idSesionPrincipal;

  Future<void> borrar(Sesion s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('¿Borrar "${s.nombre}"?'),
        content: const Text('Es una copia de los datos del otro celular; allá no se borra nada.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Borrar')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    if (!await confirmarConHuella(context, 'Confirma para borrar la revisión')) return;
    await acciones.eliminarRevision(s);
  }

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (hoja) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(hoja).size.height * 0.75),
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text('Sesiones', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'La sesión de compra son tus compras. Las de revisión son datos recibidos de '
                'otro celular: se escanean y se ven, pero no se mezclan con las tuyas.',
                style: etiqueta,
              ),
            ),
            ListTile(
              leading: Icon(Icons.shopping_bag_outlined, color: CatalogColors.texto),
              title: const Text('Mis compras'),
              subtitle: const Text('Sesión de compra'),
              trailing: actual == idSesionPrincipal ? Icon(Icons.check, color: CatalogColors.verde) : null,
              onTap: () {
                Navigator.pop(hoja);
                if (actual != idSesionPrincipal) acciones.abrirSesion(sesiones.principal);
              },
            ),
            for (final s in revisiones)
              ListTile(
                leading: const Icon(Icons.fact_check_outlined, color: CatalogColors.naranja),
                title: Text(s.nombre),
                subtitle: Text(
                  'Revisión · ${s.compras} compras'
                  '${s.recibidaEn != null ? ' · recibida el ${fechaHora(s.recibidaEn!)}' : ''}',
                ),
                selected: actual == s.id,
                trailing: IconButton(
                  tooltip: 'Borrar revisión',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () {
                    Navigator.pop(hoja);
                    borrar(s);
                  },
                ),
                onTap: () {
                  Navigator.pop(hoja);
                  if (actual != s.id) acciones.abrirSesion(s);
                },
              ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: const Text('Recibir datos de otro celular'),
              onTap: () {
                Navigator.pop(hoja);
                recibirDatos(context);
              },
            ),
          ],
        ),
      ),
    ),
  );
}

/// Accesos directos: respaldo, traspaso, recibir datos y sesiones.
Future<void> mostrarRespaldoYTraspaso(BuildContext context) async {
  final scope = AppScope.of(context);
  final revision = scope.soloLectura;
  void ir(BuildContext hoja, Future<void> Function(BuildContext) accion) {
    Navigator.pop(hoja);
    accion(context);
  }

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (hoja) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Respaldo y traspaso', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
          ),
          if (!revision)
            ListTile(
              leading: Icon(Icons.backup_outlined, color: CatalogColors.texto),
              title: const Text('Crear respaldo'),
              subtitle: const Text('Se guarda en Descargas/Respaldo CataLog'),
              onTap: () => ir(hoja, crearRespaldoYEnviar),
            ),
          if (!revision)
            ListTile(
              leading: Icon(Icons.send_to_mobile_outlined, color: CatalogColors.texto),
              title: const Text('Enviar mis compras a otro celular'),
              subtitle: const Text('Para que las revise y escanee los stickers'),
              onTap: () => ir(hoja, enviarAOtroCelular),
            ),
          ListTile(
            leading: Icon(Icons.download_outlined, color: CatalogColors.texto),
            title: const Text('Recibir datos de otro celular'),
            subtitle: const Text('Abrir un archivo de CataLog'),
            onTap: () => ir(hoja, recibirDatos),
          ),
          ListTile(
            leading: Icon(Icons.swap_horiz, color: CatalogColors.texto),
            title: const Text('Cambiar de sesión'),
            subtitle: Text('Ahora: ${scope.sesion?.nombre ?? 'Mis compras'}'),
            onTap: () => ir(hoja, mostrarSesiones),
          ),
          if (!revision)
            ListTile(
              leading: Icon(Icons.settings_backup_restore, color: CatalogColors.rojo),
              title: const Text('Restaurar desde un respaldo'),
              subtitle: const Text('Elige un .zip y la app recupera tus compras'),
              onTap: () => ir(hoja, restaurarDesdeArchivo),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
