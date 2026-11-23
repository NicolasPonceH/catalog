package cl.catalog.catalog

import android.Manifest
import android.content.ContentUris
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
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
 */
class MainActivity : FlutterFragmentActivity() {
    private var archivoPendiente: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
                        "listarRespaldos" -> result.success(listarRespaldos(call.argument<String>("carpeta") ?: "Respaldo CataLog"))
                        "leerArchivo" -> result.success(leerArchivo(call.argument<String>("uri")!!))
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("sistema", e.message, null)
                }
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
