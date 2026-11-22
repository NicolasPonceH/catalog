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
 *  - guardarEnDescargas: guarda el respaldo diario en Descargas/CataLog.
 */
class MainActivity : FlutterFragmentActivity() {
    private var archivoPendiente: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cl.catalog/sistema")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "archivoRecibido" -> {
                        val ruta = archivoPendiente
                        archivoPendiente = null
                        result.success(ruta)
                    }
                    "guardarEnDescargas" -> {
                        try {
                            val nombre = call.argument<String>("nombre")!!
                            val bytes = call.argument<ByteArray>("bytes")!!
                            val prefijoBorrar = call.argument<String>("prefijoBorrar")
                            val conservar = call.argument<Int>("conservar") ?: 3
                            result.success(guardarEnDescargas(nombre, bytes, prefijoBorrar, conservar))
                        } catch (e: Exception) {
                            result.error("descargas", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
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

    private fun guardarEnDescargas(nombre: String, bytes: ByteArray, prefijoBorrar: String?, conservar: Int): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val resolver = contentResolver
            val coleccion = MediaStore.Downloads.EXTERNAL_CONTENT_URI
            val relativa = Environment.DIRECTORY_DOWNLOADS + "/CataLog"
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
            if (checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED) {
                requestPermissions(arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), 7)
                throw Exception("Falta el permiso de almacenamiento")
            }
            @Suppress("DEPRECATION")
            val carpeta = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), "CataLog")
            carpeta.mkdirs()
            File(carpeta, nombre).writeBytes(bytes)
            if (prefijoBorrar != null) {
                carpeta.listFiles { f -> f.name.startsWith(prefijoBorrar) }
                    ?.sortedByDescending { it.name }
                    ?.drop(conservar)
                    ?.forEach { it.delete() }
            }
        }
        return "Descargas/CataLog/$nombre"
    }
}
