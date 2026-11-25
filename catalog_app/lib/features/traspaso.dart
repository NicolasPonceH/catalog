import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../app_scope.dart';
import '../backup/respaldo.dart';
import '../domain/formato.dart';
import '../i18n.dart';
import '../sync/wifi_sync.dart';
import '../system/confirmar.dart';
import '../system/notificaciones.dart';
import '../system/sistema.dart';
import '../theme.dart';
import '../widgets/selector_fechas_envio.dart';
import 'revision_supervisor_screen.dart';

// Respaldo (con sobrescritura o expiración), sincronización Wi-Fi local y
// acceso al Módulo de Revisión del Supervisor. Se usan desde Inicio y Ajustes.

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
/// respetando si el usuario eligió sobrescribir un único archivo o expirar los antiguos.
Future<void> crearRespaldoYEnviar(BuildContext context) async {
  final scope = AppScope.of(context);
  if (scope.soloLectura) {
    avisar(context, tr('Los respaldos se hacen desde tus compras', 'Backups are created from your purchases'));
    return;
  }
  avisar(context, tr('Preparando respaldo…', 'Preparing backup…'));
  await Notificaciones.avisarRespaldoEnCurso(scope.dispositivo);
  try {
    final zip = await armarRespaldo(scope.base, scope.fotos.carpetaBase);
    final prefijo = await scope.compras.prefijo();
    final disp = scope.dispositivo;
    final sobrescribir = disp?.sobrescribirRespaldo ?? true;
    final expirarDias = disp?.diasExpiracionRespaldo;
    final nombre = sobrescribir
        ? 'CataLog-respaldo-$prefijo.zip'
        : 'CataLog-respaldo-$prefijo-${_sello(DateTime.now())}.zip';
    String? lugar;
    try {
      lugar = await Sistema.guardarEnDescargas(
        nombre,
        zip,
        prefijoBorrar: 'CataLog-respaldo-',
        conservar: sobrescribir ? 1 : 40,
        expirarDias: expirarDias,
      );
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
                  sobrescribir
                      ? 'Actualizado sobre un único archivo en $lugar (sin acumular copias repetidas). Si quieres, envíalo también a tu correo, Drive o WhatsApp.'
                      : 'Quedó en $lugar (los respaldos antiguos expiran solos). Para protegerte si se pierde el teléfono, envíalo también a tu correo, Drive o WhatsApp.',
                  sobrescribir
                      ? 'Updated in place at $lugar (no duplicate clutter). You can also send a copy to your email, Drive, or WhatsApp.'
                      : 'Saved in $lugar (older backups expire automatically). Send it to your email, Drive, or WhatsApp for extra safety.',
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
            if (lista.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(tr('En Descargas/$carpetaRespaldos:', 'In Downloads/$carpetaRespaldos:'), style: etiqueta),
              ),
            for (final a in lista)
              ListTile(
                leading: Icon(
                  a.esAutomatico ? Icons.schedule : Icons.folder_zip_outlined,
                  color: CatalogColors.naranja,
                ),
                title: Text(a.nombre, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  '${fechaHora(a.fecha)} · ${_tamano(a.tamano)}'
                  '${a.esAutomatico ? ' · ${tr('automático', 'auto')}' : ''}',
                  style: etiqueta,
                ),
                onTap: () => Navigator.pop(hoja, a),
              ),
            if (lista.isNotEmpty) const Divider(),
            ListTile(
              leading: const Icon(Icons.folder_open_outlined),
              title: Text(
                lista.isEmpty
                    ? tr('Buscar archivo .zip en el teléfono', 'Browse for .zip file on phone')
                    : tr('Buscar en otra carpeta…', 'Browse in another folder…'),
              ),
              subtitle: lista.isEmpty
                  ? Text(tr('Por ejemplo en Descargas/$carpetaRespaldos', 'For example in Downloads/$carpetaRespaldos'), style: etiqueta)
                  : null,
              onTap: () => Navigator.pop(hoja, 'buscar'),
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

/// Sincronización directa en el mismo Wi-Fi (Comprador ⇄ Supervisor).
Future<void> sincronizarPorWifi(BuildContext context, {bool iniciarEnRecibir = false}) async {
  final contenido = await mostrarSincronizacionWifi(context, iniciarEnRecibir: iniciarEnRecibir);
  if (contenido == null || !context.mounted) return;
  await procesarContenidoRecibido(context, contenido);
}

/// Comparte un .zip con las compras filtradas por fechas (por WhatsApp, correo, etc.)
/// para que el supervisor solo vea y revise ese período sin arrastrar todo el historial.
Future<void> enviarAOtroCelular(BuildContext context) async {
  final scope = AppScope.of(context);
  if (scope.soloLectura) return;
  final seleccion = await pedirOpcionesEnvioPorFechas(context, base: scope.base);
  if (seleccion == null || !context.mounted) return;
  avisar(context, tr('Preparando envío…', 'Preparing package…'));
  try {
    final zip = await armarRespaldo(
      scope.base,
      scope.fotos.carpetaBase,
      incluirFotos: seleccion.conFotos,
      tipo: 'traspaso',
      filtro: seleccion.filtro,
    );
    final prefijo = await scope.compras.prefijo();
    final nombre = await scope.compras.leerAjuste('nombre') ?? '';
    final archivo = await _archivoTemporal('CataLog-envio-$prefijo-${_sello(DateTime.now())}.zip', zip);
    final rangoTxt = seleccion.filtro.etiqueta.isNotEmpty ? ' · ${seleccion.filtro.etiqueta}' : '';
    await _compartirZip(
      archivo,
      tr(
        'CataLog${nombre.isNotEmpty ? ' · $nombre' : ''}$rangoTxt (${contarCataliticos(seleccion.cantidad)}). Ábrelo con CataLog en Revisión de Supervisor.',
        'CataLog${nombre.isNotEmpty ? ' · $nombre' : ''}$rangoTxt (${contarCataliticos(seleccion.cantidad)}). Open with CataLog in Supervisor Review.',
      ),
    );
  } catch (e) {
    if (context.mounted) avisar(context, '${tr('No se pudo preparar el archivo', 'Could not prepare file')}: $e');
  }
}

/// Abre un archivo de CataLog recibido (elegido a mano o tocado en WhatsApp).
Future<void> recibirDatos(BuildContext context, [List<int>? bytes]) async {
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
  await procesarContenidoRecibido(context, contenido);
}

/// Pregunta si los datos recibidos (por Wi-Fi o .zip) se abren en el Módulo de
/// Revisión del Supervisor o si pueblan/reemplazan las compras de este celular.
Future<void> procesarContenidoRecibido(BuildContext context, ContenidoRespaldo contenido) async {
  final scope = AppScope.of(context);
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
              'Datos de $quien${contenido.rango.isNotEmpty ? ' · ${contenido.rango}' : (creado != null ? ' (${fechaHora(creado)})' : '')}: ${contenido.compras} compras.',
              'Data from $quien${contenido.rango.isNotEmpty ? ' · ${contenido.rango}' : (creado != null ? ' (${fechaHora(creado)})' : '')}: ${contenido.compras} purchases.',
            ),
            style: const TextStyle(fontSize: 15, height: 1.4),
          ),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, 'revisar'),
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.fact_check_outlined, color: CatalogColors.naranja),
            title: Text(tr('Abrir en Revisión de Supervisor', 'Open in Supervisor Review')),
            subtitle: Text(
              tr(
                'Escanea los stickers con la cámara y genera el Excel sin mezclar ni cambiar de sesión.',
                'Scan stickers with the camera and export Excel without mixing or switching sessions.',
              ),
            ),
          ),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, 'restaurar'),
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.sync_alt, color: CatalogColors.rojo),
            title: Text(tr('Poblar / Reemplazar mis compras', 'Populate / Replace my purchases')),
            subtitle: Text(
              tr(
                'Carga estas compras como las compras principales de este teléfono (guarda copia previa).',
                'Loads these purchases as this phone’s main catalog (saves a safety backup first).',
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
    final sesiones = scope.sesiones;
    if (sesiones == null) return;
    final guardada = await sesiones.guardarRevision(contenido);
    if (!context.mounted) return;
    await abrir(context, RevisionSupervisorScreen(revisionInicial: guardada));
  } else {
    await restaurarDesdeContenido(context, contenido);
  }
}

/// Elige un respaldo (de la carpeta Respaldo CataLog u otro lugar), lo extrae y
/// con él se vuelven a poblar las compras de este celular.
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
  if (acciones == null || scope.soloLectura) return;
  final actuales = await scope.compras.contarCompras();
  if (!context.mounted) return;
  final creado = contenido.creado;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(tr('Poblar / Reemplazar mis compras', 'Populate / Replace my purchases')),
      content: Text(
        tr(
          'El archivo${creado != null ? ' es del ${fechaHora(creado)} y' : ''} tiene ${contenido.compras} compras${contenido.prefijo.isNotEmpty ? ' (prefijo ${contenido.prefijo})' : ''}.\n\nVa a actualizar las compras de este teléfono ($actuales actuales). Antes se guarda una copia de seguridad interna por si acaso.',
          'This file${creado != null ? ' from ${fechaHora(creado)}' : ''} contains ${contenido.compras} purchases${contenido.prefijo.isNotEmpty ? ' (prefix ${contenido.prefijo})' : ''}.\n\nIt will replace the purchases on this phone ($actuales current). A safety copy is saved first.',
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Cancelar', 'Cancel'))),
        TextButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('Continuar', 'Continue'))),
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
    mensaje: tr('Datos actualizados: ${contenido.compras} compras', 'Data updated: ${contenido.compras} purchases'),
  );
}

/// Abre directamente la carpeta exacta de los respaldos en la app de Archivos
/// del teléfono (`Descargas/Respaldo CataLog`).
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

/// Accesos directos desde Inicio: Wi-Fi local, Revisión de Supervisor y Respaldos.
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
    isScrollControlled: true,
    builder: (hoja) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(hoja).size.height * 0.84),
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  tr('Wi-Fi, Supervisor y Respaldos', 'Wi-Fi, Supervisor & Backups'),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.wifi_tethering, color: CatalogColors.naranja),
              title: Text(
                tr('Sincronizar por Wi-Fi', 'Sync over Wi-Fi'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                tr('Pasa compras de tu celular al del supervisor y viceversa', 'Transfer purchases between buyer & supervisor on the same Wi-Fi'),
              ),
              onTap: () => ir(hoja, sincronizarPorWifi),
            ),
            ListTile(
              leading: const Icon(Icons.fact_check_outlined, color: Color(0xFF0F8B8D)),
              title: Text(
                tr('Revisión de Supervisor', 'Supervisor Review'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                tr('Escáner de códigos para verificar catalíticos y generar Excel', 'Barcode/QR scanner to verify converters and export Excel'),
              ),
              onTap: () {
                Navigator.pop(hoja);
                abrir(context, const RevisionSupervisorScreen());
              },
            ),
            const Divider(),
            if (!revision)
              ListTile(
                leading: Icon(Icons.backup_outlined, color: CatalogColors.texto),
                title: Text(tr('Crear respaldo', 'Create backup')),
                subtitle: Text(tr('Se guarda en Descargas/Respaldo CataLog', 'Saved in Downloads/Respaldo CataLog')),
                onTap: () => ir(hoja, crearRespaldoYEnviar),
              ),
            if (!revision)
              ListTile(
                leading: Icon(Icons.send_to_mobile_outlined, color: CatalogColors.naranja),
                title: Text(
                  tr('Sincronizar por WhatsApp / Archivo (.zip)', 'Sync via WhatsApp / .zip file'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(tr('Elige por fechas (Hoy, 7 días, Mes…) sin enviar todo', 'Filter by dates (Today, 7 days, Month…) instead of sending all')),
                onTap: () => ir(hoja, enviarAOtroCelular),
              ),
            ListTile(
              leading: Icon(Icons.download_outlined, color: CatalogColors.texto),
              title: Text(tr('Recibir archivo .zip', 'Receive .zip file')),
              subtitle: Text(tr('Abrir un archivo de CataLog en revisión o poblar datos', 'Open a CataLog file in review or populate data')),
              onTap: () => ir(hoja, recibirDatos),
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
