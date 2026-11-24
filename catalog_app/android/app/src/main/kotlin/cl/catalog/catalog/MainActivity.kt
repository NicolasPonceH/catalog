package cl.catalog.catalog

import android.Manifest
import android.app.DownloadManager
import android.app.NotificationManager
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * FlutterFragmentActivity: lo necesita el bloqueo con huella (local_auth).
 *
 * Canal "cl.catalog/sistema":
 *  - archivoRecibido: ruta del .zip que se abrió con CataLog desde otra app.
 *  - guardarEnDescargas: guarda un respaldo en Descargas/<carpeta>.
 *  - listarRespaldos: respaldos que esta app guardó en Descargas/<carpeta>.
 *  - leerArchivo: bytes de un archivo (por su uri).
 *  - abrirCarpetaRespaldos: abre el explorador de archivos del teléfono directo en Descargas/<carpeta>.
 *  - pedirPermisoNotificaciones: solicita permiso POST_NOTIFICATIONS en Android 13+.
 *  - mostrarNotificacion: publica una notificación local inmediata (p. ej. respaldo en curso o listo).
 *  - programarRecordatorio: guarda y programa la notificación diaria local (sin internet).
 */
class MainActivity : FlutterFragmentActivity() {
    private var archivoPendiente: String? = null
    private var resultadoPermisoNotif: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        RecordatorioReceiver.asegurarCanales(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cl.catalog/sistema")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "archivoRecibido" -> {
                            val ruta = archivoPendiente
                            archivoPendiente = null
                            result.success(ruta)
                        }
                        "guardarEnDescargas" -> result.success(
                            guardarEnDescargas(
                                call.argument<String>("nombre")!!,
                                call.argument<ByteArray>("bytes")!!,
                                call.argument<String>("carpeta") ?: "Respaldo CataLog",
                                call.argument<String>("prefijoBorrar"),
                                call.argument<Int>("conservar") ?: 3,
                            )
                        )
                        "listarRespaldos" -> result.success(
                            listarRespaldos(call.argument<String>("carpeta") ?: "Respaldo CataLog")
                        )
                        "leerArchivo" -> result.success(leerArchivo(call.argument<String>("uri")!!))
                        "abrirCarpetaRespaldos" -> result.success(
                            abrirCarpetaRespaldos(call.argument<String>("carpeta") ?: "Respaldo CataLog")
                        )
                        "pedirPermisoNotificaciones" -> pedirPermisoNotificaciones(result)
                        "mostrarNotificacion" -> {
                            val esRespaldo = call.argument<Boolean>("esRespaldo") ?: false
                            val enCurso = call.argument<Boolean>("enCurso") ?: false
                            val canalId = if (enCurso) {
                                RecordatorioReceiver.CANAL_PROGRESO
                            } else {
                                RecordatorioReceiver.CANAL_RECORDATORIOS
                            }
                            RecordatorioReceiver.publicarNotificacion(
                                context = this,
                                id = call.argument<Int>("id")
                                    ?: if (esRespaldo) RecordatorioReceiver.ID_RESPALDO else RecordatorioReceiver.ID_RECORDATORIO,
                                canalId = canalId,
                                titulo = call.argument<String>("titulo") ?: "CataLog",
                                cuerpo = call.argument<String>("cuerpo") ?: "",
                                enCurso = enCurso,
                            )
                            result.success(true)
                        }
                        "programarRecordatorio" -> {
                            val activo = call.argument<Boolean>("activo") ?: false
                            val hora = call.argument<Int>("hora") ?: 20
                            val minuto = call.argument<Int>("minuto") ?: 0
                            val titulo = call.argument<String>("titulo") ?: "CataLog"
                            val cuerpo = call.argument<String>("cuerpo") ?: ""
                            getSharedPreferences(RecordatorioReceiver.PREFS, Context.MODE_PRIVATE)
                                .edit()
                                .putBoolean("activo", activo && cuerpo.isNotBlank())
                                .putInt("hora", hora)
                                .putInt("minuto", minuto)
                                .putString("titulo", titulo)
                                .putString("cuerpo", cuerpo)
                                .apply()
                            if (activo && cuerpo.isNotBlank()) {
                                RecordatorioReceiver.programarAlarma(this, hora, minuto)
                            } else {
                                RecordatorioReceiver.cancelarAlarma(this)
                            }
                            result.success(true)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("sistema", e.message, null)
                }
            }
    }

    private fun pedirPermisoNotificaciones(result: MethodChannel.Result) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
                result.success(nm.areNotificationsEnabled())
                return
            }
            resultadoPermisoNotif?.success(false)
            resultadoPermisoNotif = result
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 19)
        } else {
            val habilitadas = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) nm.areNotificationsEnabled() else true
            result.success(habilitadas)
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 19) {
            val concedido = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            resultadoPermisoNotif?.success(concedido)
            resultadoPermisoNotif = null
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        leerIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        leerIntent(intent)
    }

    /** Copia el archivo compartido o abierto con CataLog a la caché de la app. */
    private fun leerIntent(intent: Intent?) {
        if (intent == null) return
        val uri: Uri? = when (intent.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND ->
                if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                else @Suppress("DEPRECATION") intent.getParcelableExtra(Intent.EXTRA_STREAM)
            else -> null
        }
        if (uri == null) return
        try {
            val destino = File(cacheDir, "recibido-${System.currentTimeMillis()}.zip")
            contentResolver.openInputStream(uri)?.use { entrada ->
                destino.outputStream().use { salida -> entrada.copyTo(salida) }
            }
            archivoPendiente = destino.absolutePath
        } catch (e: Exception) {
            archivoPendiente = null
        }
        // Para no volver a procesarlo si Android recrea la pantalla.
        intent.action = null
    }

    private fun rutaRelativa(carpeta: String) = Environment.DIRECTORY_DOWNLOADS + "/" + carpeta

    @Suppress("DEPRECATION")
    private fun carpetaPublica(carpeta: String) =
        File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), carpeta)

    private fun pedirPermisoAntiguo() {
        if (checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), 7)
            throw Exception("Falta el permiso de almacenamiento")
        }
    }

    /**
     * Asegura que la carpeta exista en Descargas y abre el explorador de archivos
     * del teléfono directamente sobre Descargas/<carpeta>.
     */
    private fun abrirCarpetaRespaldos(carpeta: String): Boolean {
        // Si todavía no había ningún respaldo, crea una guía mínima para que la carpeta ya exista en Archivos.
        try {
            if (listarRespaldos(carpeta).isEmpty()) {
                val nota = "Aquí guarda CataLog tus respaldos (.zip).\r\nNo se borran aunque desinstales la app.\r\n".toByteArray()
                guardarTextoSiNoExiste("DONDE-ESTAN-MIS-RESPALDOS.txt", nota, carpeta)
            }
        } catch (_: Exception) {
        }

        val docUri = DocumentsContract.buildDocumentUri(
            "com.android.externalstorage.documents",
            "primary:Download/$carpeta",
        )

        val candidatos = listOf(
            Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(docUri, DocumentsContract.Document.MIME_TYPE_DIR)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            },
            Intent(Intent.ACTION_VIEW).apply {
                val raizDescargas = DocumentsContract.buildDocumentUri(
                    "com.android.externalstorage.documents",
                    "primary:Download",
                )
                setDataAndType(raizDescargas, DocumentsContract.Document.MIME_TYPE_DIR)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            },
            Intent(DownloadManager.ACTION_VIEW_DOWNLOADS),
        )

        for (intent in candidatos) {
            try {
                startActivity(intent)
                return true
            } catch (_: Exception) {
            }
        }
        return false
    }

    private fun guardarTextoSiNoExiste(nombre: String, bytes: ByteArray, carpeta: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val resolver = contentResolver
            val coleccion = MediaStore.Downloads.EXTERNAL_CONTENT_URI
            val relativa = rutaRelativa(carpeta)
            val columnaNombre = MediaStore.MediaColumns.DISPLAY_NAME
            val columnaRuta = MediaStore.MediaColumns.RELATIVE_PATH
            var existe = false
            resolver.query(
                coleccion,
                arrayOf(MediaStore.MediaColumns._ID),
                "$columnaNombre = ? AND $columnaRuta LIKE ?",
                arrayOf(nombre, "$relativa%"),
                null,
            )?.use { c -> existe = c.moveToFirst() }
            if (existe) return
            val valores = ContentValues().apply {
                put(columnaNombre, nombre)
                put(MediaStore.MediaColumns.MIME_TYPE, "text/plain")
                put(columnaRuta, relativa)
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val uri = resolver.insert(coleccion, valores) ?: return
            resolver.openOutputStream(uri)?.use { it.write(bytes) }
            valores.clear()
            valores.put(MediaStore.MediaColumns.IS_PENDING, 0)
            resolver.update(uri, valores, null, null)
        } else {
            val dir = carpetaPublica(carpeta)
            dir.mkdirs()
            val f = File(dir, nombre)
            if (!f.exists()) f.writeBytes(bytes)
        }
    }

    private fun guardarEnDescargas(nombre: String, bytes: ByteArray, carpeta: String, prefijoBorrar: String?, conservar: Int): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val resolver = contentResolver
            val coleccion = MediaStore.Downloads.EXTERNAL_CONTENT_URI
            val relativa = rutaRelativa(carpeta)
            val columnaNombre = MediaStore.MediaColumns.DISPLAY_NAME
            val columnaRuta = MediaStore.MediaColumns.RELATIVE_PATH

            // Si ya existe uno con el mismo nombre (de esta app), se reemplaza.
            resolver.delete(coleccion, "$columnaNombre = ? AND $columnaRuta LIKE ?", arrayOf(nombre, "$relativa%"))

            val valores = ContentValues().apply {
                put(columnaNombre, nombre)
                put(MediaStore.MediaColumns.MIME_TYPE, "application/zip")
                put(columnaRuta, relativa)
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val uri = resolver.insert(coleccion, valores) ?: throw Exception("No se pudo crear el archivo en Descargas")
            resolver.openOutputStream(uri)?.use { it.write(bytes) }
            valores.clear()
            valores.put(MediaStore.MediaColumns.IS_PENDING, 0)
            resolver.update(uri, valores, null, null)

            if (prefijoBorrar != null) {
                val viejos = mutableListOf<Long>()
                resolver.query(
                    coleccion,
                    arrayOf(MediaStore.MediaColumns._ID),
                    "$columnaNombre LIKE ? AND $columnaRuta LIKE ?",
                    arrayOf("$prefijoBorrar%", "$relativa%"),
                    "$columnaNombre DESC",
                )?.use { c -> while (c.moveToNext()) viejos.add(c.getLong(0)) }
                for (id in viejos.drop(conservar)) {
                    try {
                        resolver.delete(ContentUris.withAppendedId(coleccion, id), null, null)
                    } catch (_: Exception) {
                    }
                }
            }
        } else {
            pedirPermisoAntiguo()
            val dir = carpetaPublica(carpeta)
            dir.mkdirs()
            File(dir, nombre).writeBytes(bytes)
            if (prefijoBorrar != null) {
                dir.listFiles { f -> f.name.startsWith(prefijoBorrar) }
                    ?.sortedByDescending { it.name }
                    ?.drop(conservar)
                    ?.forEach { it.delete() }
            }
        }
        return "Descargas/$carpeta/$nombre"
    }

    /** Respaldos (.zip) de la carpeta, el más nuevo primero. */
    private fun listarRespaldos(carpeta: String): List<Map<String, Any>> {
        val lista = mutableListOf<Map<String, Any>>()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val coleccion = MediaStore.Downloads.EXTERNAL_CONTENT_URI
            contentResolver.query(
                coleccion,
                arrayOf(
                    MediaStore.MediaColumns._ID,
                    MediaStore.MediaColumns.DISPLAY_NAME,
                    MediaStore.MediaColumns.DATE_MODIFIED,
                    MediaStore.MediaColumns.SIZE,
                ),
                "${MediaStore.MediaColumns.RELATIVE_PATH} LIKE ? AND ${MediaStore.MediaColumns.DISPLAY_NAME} LIKE ?",
                arrayOf("${rutaRelativa(carpeta)}%", "%.zip"),
                "${MediaStore.MediaColumns.DATE_MODIFIED} DESC",
            )?.use { c ->
                while (c.moveToNext()) {
                    lista.add(
                        mapOf(
                            "nombre" to c.getString(1),
                            "uri" to ContentUris.withAppendedId(coleccion, c.getLong(0)).toString(),
                            "fecha" to c.getLong(2) * 1000,
                            "tamano" to c.getLong(3),
                        )
                    )
                }
            }
        } else {
            carpetaPublica(carpeta).listFiles { f -> f.name.endsWith(".zip") }
                ?.sortedByDescending { it.lastModified() }
                ?.forEach { f ->
                    lista.add(
                        mapOf(
                            "nombre" to f.name,
                            "uri" to Uri.fromFile(f).toString(),
                            "fecha" to f.lastModified(),
                            "tamano" to f.length(),
                        )
                    )
                }
        }
        return lista
    }

    private fun leerArchivo(uri: String): ByteArray =
        contentResolver.openInputStream(Uri.parse(uri))?.use { it.readBytes() }
            ?: throw Exception("No se pudo abrir el archivo")
}
