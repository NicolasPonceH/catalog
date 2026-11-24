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
import '../i18n.dart';
import '../system/confirmar.dart';
import '../system/notificaciones.dart';
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
    avisar(context, tr('Los respaldos se hacen desde tu sesión de compra', 'Backups are created from your purchase session'));
    return;
  }
  avisar(context, tr('Preparando respaldo…', 'Preparing backup…'));
  await Notificaciones.avisarRespaldoEnCurso(scope.dispositivo);
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
    if (lugar != null) {
      await scope.compras.registrarRespaldo();
      await Notificaciones.avisarRespaldoListo(scope.dispositivo, lugar: lugar);
    }
    if (!context.mounted) return;
    final enviar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(lugar != null ? Icons.check_circle : Icons.warning_amber,
            color: lugar != null ? CatalogColors.verde : CatalogColors.rojo, size: 36),
        title: Text(
          lugar != null
              ? tr('Respaldo guardado', 'Backup saved')
              : tr('No se pudo guardar en el teléfono', 'Could not save to phone'),
        ),
        content: Text(
          lugar != null
              ? tr(
                  'Quedó en $lugar. Para protegerte si se pierde el teléfono, envíalo también a tu correo, Drive o WhatsApp.',
                  'Saved in $lugar. To protect your data if the phone is lost, send it to your email, Drive, or WhatsApp too.',
                )
              : tr(
                  'Puedes enviarlo directamente a tu correo, Drive o WhatsApp.',
                  'You can send it directly to your email, Drive, or WhatsApp.',
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Listo', 'Done'))),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size(120, 44)),
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.share_outlined),
            label: Text(tr('Enviar', 'Send')),
          ),
        ],
      ),
    );
    if (enviar != true) return;
    final archivo = await _archivoTemporal(nombre, zip);
    final r = await _compartirZip(archivo, tr('Respaldo de CataLog', 'CataLog backup'));
    if (r.status != ShareResultStatus.dismissed) await scope.compras.registrarRespaldo();
  } catch (e) {
    if (context.mounted) avisar(context, '${tr('No se pudo crear el respaldo', 'Could not create backup')}: $e');
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
                    ? tr(
                        'No hay respaldos en Descargas/$carpetaRespaldos. Búscalo en otra carpeta.',
                        'No backups in Downloads/$carpetaRespaldos. Browse another folder.',
                      )
                    : tr('En Descargas/$carpetaRespaldos:', 'In Downloads/$carpetaRespaldos:'),
                style: etiqueta,
              ),
            ),
            for (final a in lista)
              ListTile(
                leading: Icon(a.esAutomatico ? Icons.schedule : Icons.inventory_2_outlined, color: CatalogColors.texto),
                title: Text(
                  a.esAutomatico ? tr('Copia automática', 'Auto backup') : tr('Respaldo', 'Backup'),
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                subtitle: Text('${fechaHora(a.fecha)} · ${_tamano(a.tamano)}\n${a.nombre}', style: etiqueta),
                isThreeLine: true,
                onTap: () => Navigator.pop(hoja, a),
              ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.folder_open_outlined),
              title: Text(tr('Buscar otro archivo', 'Browse another file')),
              subtitle: Text(tr('WhatsApp, Drive, otra carpeta…', 'WhatsApp, Drive, another folder…')),
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
    if (context.mounted) avisar(context, '${tr('No se pudo leer el archivo', 'Could not read file')}: $e');
    return null;
  }
}

/// Manda todas las compras a otro celular, que las abre como sesión de revisión.
Future<void> enviarAOtroCelular(BuildContext context) async {
  final scope = AppScope.of(context);
  if (scope.soloLectura) {
    avisar(
      context,
      tr('Vuelve a tu sesión de compra para enviar tus compras', 'Switch to your purchase session to send your purchases'),
    );
    return;
  }
  final conFotos = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(tr('Enviar mis compras a otro celular', 'Send my purchases to another phone')),
      content: Text(
        tr(
          'El otro celular las abre en CataLog como sesión de revisión: puede escanear tus stickers y ver cada ficha, sin mezclarlas con sus propias compras.\n\n¿Incluir las fotos? Con fotos el archivo pesa más.',
          'The other phone opens them in CataLog as a review session: it can scan your stickers and view every record without mixing them with its own purchases.\n\nInclude photos? With photos the file is larger.',
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Cancelar', 'Cancel'))),
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Sin fotos', 'Without photos'))),
        TextButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('Con fotos', 'With photos'))),
      ],
    ),
  );
  if (conFotos == null || !context.mounted) return;
  avisar(context, tr('Preparando el archivo…', 'Preparing file…'));
  try {
    final zip = await armarRespaldo(scope.base, scope.fotos.carpetaBase, incluirFotos: conFotos, tipo: 'traspaso');
    final prefijo = await scope.compras.prefijo();
    final nombre = await scope.compras.leerAjuste('nombre') ?? '';
    final archivo = await _archivoTemporal('CataLog-datos-$prefijo-${_sello(DateTime.now())}.zip', zip);
    await _compartirZip(
      archivo,
      tr(
        'Compras de CataLog${nombre.isNotEmpty ? ' de $nombre' : ''}. Abre este archivo con CataLog para revisarlas y escanear los stickers.',
        'CataLog purchases${nombre.isNotEmpty ? ' from $nombre' : ''}. Open this file with CataLog to review them and scan stickers.',
      ),
    );
  } catch (e) {
    if (context.mounted) avisar(context, '${tr('No se pudo preparar el archivo', 'Could not prepare file')}: $e');
  }
}

/// Abre un archivo de CataLog recibido (elegido a mano o tocado en WhatsApp)
/// y pregunta si se revisa aparte o si reemplaza las compras.
Future<void> recibirDatos(BuildContext context, [List<int>? bytes]) async {
  final scope = AppScope.of(context);
  bytes ??= await elegirArchivoCatalog(context, titulo: tr('Elige el archivo de CataLog', 'Choose CataLog file'));
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
      : (contenido.prefijo.isNotEmpty
          ? tr('el teléfono ${contenido.prefijo}', 'phone ${contenido.prefijo}')
          : tr('otro celular', 'another phone'));
  final creado = contenido.creado;
  final eleccion = await showDialog<String>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(tr('Datos de CataLog recibidos', 'CataLog data received')),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
          child: Text(
            tr(
              'Archivo de $quien${creado != null ? ' del ${fechaHora(creado)}' : ''}: ${contenido.compras} compras.',
              'File from $quien${creado != null ? ' (${fechaHora(creado)})' : ''}: ${contenido.compras} purchases.',
            ),
            style: const TextStyle(fontSize: 15, height: 1.4),
          ),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, 'revisar'),
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.fact_check_outlined, color: CatalogColors.texto),
            title: Text(tr('Abrir para revisar', 'Open for review')),
            subtitle: Text(
              tr(
                'Se guarda aparte, como sesión de revisión. Tus compras no se tocan.',
                'Saved separately as a review session. Your own purchases are untouched.',
              ),
            ),
          ),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, 'restaurar'),
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.settings_backup_restore, color: CatalogColors.rojo),
            title: Text(tr('Reemplazar mis compras', 'Replace my purchases')),
            subtitle: Text(
              tr(
                'Úsalo como respaldo: tus compras actuales se reemplazan por estas.',
                'Use as backup: your current purchases will be replaced by these.',
              ),
            ),
          ),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('Cancelar', 'Cancel'), textAlign: TextAlign.right),
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
  final bytes = await elegirArchivoCatalog(context, titulo: tr('Elige el respaldo', 'Choose backup'));
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
    avisar(
      context,
      tr('Vuelve a tu sesión de compra para restaurar un respaldo', 'Switch to your purchase session to restore a backup'),
    );
    return;
  }
  final actuales = await scope.compras.contarCompras();
  if (!context.mounted) return;
  final creado = contenido.creado;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(tr('Reemplazar mis compras', 'Replace my purchases')),
      content: Text(
        tr(
          'El archivo${creado != null ? ' es del ${fechaHora(creado)} y' : ''} tiene ${contenido.compras} compras${contenido.prefijo.isNotEmpty ? ' (prefijo ${contenido.prefijo})' : ''}.\n\nVa a reemplazar las compras de este teléfono ($actuales). Antes se guarda una copia de lo actual dentro del teléfono, por si acaso.',
          'This file${creado != null ? ' from ${fechaHora(creado)}' : ''} contains ${contenido.compras} purchases${contenido.prefijo.isNotEmpty ? ' (prefix ${contenido.prefijo})' : ''}.\n\nIt will replace the purchases on this phone ($actuales). A safety copy of current data is saved first.',
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Cancelar', 'Cancel'))),
        TextButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('Reemplazar', 'Replace'))),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  if (!await confirmarConHuella(context, tr('Confirma para reemplazar tus compras', 'Confirm to replace your purchases'))) {
    return;
  }
  if (!context.mounted) return;
  try {
    await guardarCopiaLocal(await armarRespaldo(scope.base, scope.fotos.carpetaBase), scope.fotos.carpetaBase);
  } catch (e) {
    if (context.mounted) {
      avisar(
        context,
        '${tr('No se pudo guardar la copia de seguridad, no se cambió nada', 'Could not save safety copy, nothing was changed')}: $e',
      );
    }
    return;
  }
  await acciones.reemplazarDatos(
    (ruta) => aplicarRespaldo(contenido, rutaBase: ruta, carpetaBase: scope.fotos.carpetaBase),
    mensaje: tr('Datos restaurados: ${contenido.compras} compras', 'Data restored: ${contenido.compras} purchases'),
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
        title: Text(tr('¿Borrar "${s.nombre}"?', 'Delete "${s.nombre}"?')),
        content: Text(
          tr(
            'Es una copia de los datos del otro celular; allá no se borra nada.',
            'This is only a local copy from the other phone; nothing is deleted there.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Cancelar', 'Cancel'))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('Borrar', 'Delete'))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    if (!await confirmarConHuella(context, tr('Confirma para borrar la revisión', 'Confirm to delete review'))) return;
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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text(tr('Sesiones', 'Sessions'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                tr(
                  'La sesión de compra son tus compras. Las de revisión son datos recibidos de otro celular: se escanean y se ven, pero no se mezclan con las tuyas.',
                  'The purchase session holds your own purchases. Review sessions hold data received from another phone: you can scan and inspect them without mixing them with yours.',
                ),
                style: etiqueta,
              ),
            ),
            ListTile(
              leading: Icon(Icons.shopping_bag_outlined, color: CatalogColors.texto),
              title: Text(tr('Mis compras', 'My purchases')),
              subtitle: Text(tr('Sesión de compra', 'Purchase session')),
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
                  tr(
                    'Revisión · ${s.compras} compras${s.recibidaEn != null ? ' · recibida el ${fechaHora(s.recibidaEn!)}' : ''}',
                    'Review · ${s.compras} purchases${s.recibidaEn != null ? ' · received ${fechaHora(s.recibidaEn!)}' : ''}',
                  ),
                ),
                selected: actual == s.id,
                trailing: IconButton(
                  tooltip: tr('Borrar revisión', 'Delete review'),
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
              title: Text(tr('Recibir datos de otro celular', 'Receive data from another phone')),
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

/// Abre directamente la carpeta exacta de los respaldos en la app de Archivos
/// del teléfono (`Descargas/Respaldo CataLog`). Si el sistema no tiene visor
/// directo, muestra la ruta exacta y los archivos guardados ahí.
Future<void> ubicarRespaldosEnArchivos(BuildContext context) async {
  final abrio = await Sistema.abrirCarpetaRespaldos();
  if (!context.mounted) return;
  if (abrio) {
    avisar(
      context,
      tr(
        'Abriendo Descargas/$carpetaRespaldos en tus archivos…',
        'Opening Downloads/$carpetaRespaldos in your files…',
      ),
    );
    return;
  }
  var lista = <ArchivoRespaldo>[];
  try {
    lista = await Sistema.listarRespaldos();
  } catch (_) {}
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Icon(Icons.folder_special, color: CatalogColors.rojo, size: 36),
      title: Text(tr('Ubicación de tus respaldos', 'Backup folder location')),
      content: Text(
        lista.isEmpty
            ? tr(
                'Tus respaldos se guardan en:\nAlmacenamiento interno > Descargas > $carpetaRespaldos\n\nTodavía no hay archivos .zip creados ahí.',
                'Your backups are saved in:\nInternal storage > Downloads > $carpetaRespaldos\n\nNo .zip backups have been saved there yet.',
              )
            : tr(
                'Tus respaldos (${lista.length}) están en:\nAlmacenamiento interno > Descargas > $carpetaRespaldos\n\nMás reciente: ${lista.first.nombre}',
                'Your backups (${lista.length}) live in:\nInternal storage > Downloads > $carpetaRespaldos\n\nLatest: ${lista.first.nombre}',
              ),
      ),
      actions: [
        FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Entendido', 'Got it'))),
      ],
    ),
  );
}

/// Accesos directos: respaldo, traspaso, recibir datos y sesiones.
Future<void> mostrarRespaldoYTraspaso(BuildContext context) async {
  final scope = AppScope.of(context);
  final revision = scope.soloLectura;
  final nombreSesion = scope.sesion == null || !scope.sesion!.esRevision
      ? tr('Mis compras', 'My purchases')
      : scope.sesion!.nombre;
  void ir(BuildContext hoja, Future<void> Function(BuildContext) accion) {
    Navigator.pop(hoja);
    accion(context);
  }

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (hoja) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(hoja).size.height * 0.82),
        child: ListView(
          shrinkWrap: true,
          children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                tr('Respaldo y traspaso', 'Backup & transfer'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          if (!revision)
            ListTile(
              leading: Icon(Icons.backup_outlined, color: CatalogColors.texto),
              title: Text(tr('Crear respaldo', 'Create backup')),
              subtitle: Text(tr('Se guarda en Descargas/Respaldo CataLog', 'Saved in Downloads/Respaldo CataLog')),
              onTap: () => ir(hoja, crearRespaldoYEnviar),
            ),
          if (!revision)
            ListTile(
              leading: Icon(Icons.send_to_mobile_outlined, color: CatalogColors.texto),
              title: Text(tr('Enviar mis compras a otro celular', 'Send my purchases to another phone')),
              subtitle: Text(tr('Para que las revise y escanee los stickers', 'So they can review and scan stickers')),
              onTap: () => ir(hoja, enviarAOtroCelular),
            ),
          ListTile(
            leading: Icon(Icons.download_outlined, color: CatalogColors.texto),
            title: Text(tr('Recibir datos de otro celular', 'Receive data from another phone')),
            subtitle: Text(tr('Abrir un archivo de CataLog', 'Open a CataLog file')),
            onTap: () => ir(hoja, recibirDatos),
          ),
          ListTile(
            leading: Icon(Icons.swap_horiz, color: CatalogColors.texto),
            title: Text(tr('Cambiar de sesión', 'Switch session')),
            subtitle: Text('${tr('Ahora', 'Current')}: $nombreSesion'),
            onTap: () => ir(hoja, mostrarSesiones),
          ),
          ListTile(
            leading: Icon(Icons.folder_special_outlined, color: CatalogColors.rojo),
            title: Text(
              tr('Ubicar respaldo', 'Locate backup'),
              style: TextStyle(color: CatalogColors.rojo, fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              tr('Abrir Descargas/Respaldo CataLog en mis archivos', 'Open Downloads/Respaldo CataLog in my files'),
            ),
            onTap: () => ir(hoja, ubicarRespaldosEnArchivos),
          ),
          if (!revision)
            ListTile(
              leading: Icon(Icons.settings_backup_restore, color: CatalogColors.rojo),
              title: Text(tr('Restaurar desde un respaldo', 'Restore from backup')),
              subtitle: Text(tr('Elige un .zip y la app recupera tus compras', 'Pick a .zip to recover your purchases')),
              onTap: () => ir(hoja, restaurarDesdeArchivo),
            ),
          const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
}
