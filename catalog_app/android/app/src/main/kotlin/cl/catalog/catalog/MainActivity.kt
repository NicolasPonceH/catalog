package cl.catalog.catalog

import android.Manifest
import android.app.DownloadManager
import android.app.NotificationManager
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.net.ConnectivityManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.provider.Settings
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.net.Inet4Address
import kotlin.math.max

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
                                call.argument<Int>("expirarDias"),
                            )
                        )
                        "listarRespaldos" -> result.success(
                            listarRespaldos(call.argument<String>("carpeta") ?: "Respaldo CataLog")
                        )
                        "leerArchivo" -> result.success(leerArchivo(call.argument<String>("uri")!!))
                        "abrirCarpetaRespaldos" -> result.success(
                            abrirCarpetaRespaldos(call.argument<String>("carpeta") ?: "Respaldo CataLog")
                        )
                        "optimizarFotos" -> result.success(
                            optimizarFotos(
                                call.argument<String>("carpeta")!!,
                                call.argument<Int>("maxLado") ?: 1024,
                                call.argument<Int>("calidad") ?: 62,
                            )
                        )
                        "abrirAjustesNotificaciones" -> result.success(abrirAjustesNotificaciones())
                        "obtenerIpLocal" -> result.success(obtenerIpLocal())
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
                                subtitulo = call.argument<String>("subtitulo") ?: "",
                                enCurso = enCurso,
                            )
                            result.success(true)
                        }
                        "programarRecordatorio" -> {
                            val activo = call.argument<Boolean>("activo") ?: false
                            val hora = call.argument<Int>("hora") ?: 20
                            val minuto = call.argument<Int>("minuto") ?: 0
                            val intervaloMin = call.argument<Int>("intervaloMinutos") ?: 0
                            val titulo = call.argument<String>("titulo") ?: "CataLog"
                            val cuerpo = call.argument<String>("cuerpo") ?: ""
                            val tituloPeriodico = call.argument<String>("tituloPeriodico") ?: titulo
                            val cuerpoPeriodico = call.argument<String>("cuerpoPeriodico") ?: ""
                            val tieneDiario = activo && cuerpo.isNotBlank()
                            val tienePeriodico = activo && intervaloMin > 0 && cuerpoPeriodico.isNotBlank()
                            getSharedPreferences(RecordatorioReceiver.PREFS, Context.MODE_PRIVATE)
                                .edit()
                                .putBoolean("activo", tieneDiario)
                                .putInt("hora", hora)
                                .putInt("minuto", minuto)
                                .putString("titulo", titulo)
                                .putString("cuerpo", cuerpo)
                                .putBoolean("periodico_activo", tienePeriodico)
                                .putInt("intervalo_min", intervaloMin)
                                .putString("titulo_periodico", tituloPeriodico)
                                .putString("cuerpo_periodico", cuerpoPeriodico)
                                .apply()
                            if (tieneDiario) {
                                RecordatorioReceiver.programarAlarma(this, hora, minuto)
                            } else {
                                RecordatorioReceiver.cancelarAlarma(this)
                            }
                            if (tienePeriodico) {
                                RecordatorioReceiver.programarPeriodica(this, intervaloMin)
                            } else {
                                RecordatorioReceiver.cancelarPeriodica(this)
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

    private fun guardarEnDescargas(
        nombre: String,
        bytes: ByteArray,
        carpeta: String,
        prefijoBorrar: String?,
        conservar: Int,
        expirarDias: Int?,
    ): String {
        val limiteSeg = if (expirarDias != null && expirarDias > 0) {
            (System.currentTimeMillis() / 1000L) - (expirarDias.toLong() * 86400L)
        } else {
            null
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val resolver = contentResolver
            val coleccion = MediaStore.Downloads.EXTERNAL_CONTENT_URI
            val relativa = rutaRelativa(carpeta)
            val columnaNombre = MediaStore.MediaColumns.DISPLAY_NAME
            val columnaRuta = MediaStore.MediaColumns.RELATIVE_PATH
            val columnaFecha = MediaStore.MediaColumns.DATE_MODIFIED

            // Si ya existe uno con el mismo nombre (de esta app), se sobrescribe limpio.
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
                val encontrados = mutableListOf<Triple<Long, String, Long>>()
                resolver.query(
                    coleccion,
                    arrayOf(MediaStore.MediaColumns._ID, columnaNombre, columnaFecha),
                    "$columnaNombre LIKE ? AND $columnaRuta LIKE ?",
                    arrayOf("$prefijoBorrar%", "$relativa%"),
                    "$columnaFecha DESC",
                )?.use { c ->
                    while (c.moveToNext()) {
                        encontrados.add(Triple(c.getLong(0), c.getString(1), c.getLong(2)))
                    }
                }
                for ((idx, item) in encontrados.withIndex()) {
                    val (id, nom, fechaMod) = item
                    if (nom == nombre && idx == 0) continue
                    val sobraPorCantidad = idx >= conservar
                    val expirado = limiteSeg != null && fechaMod < limiteSeg
                    if (sobraPorCantidad || expirado) {
                        try {
                            resolver.delete(ContentUris.withAppendedId(coleccion, id), null, null)
                        } catch (_: Exception) {
                        }
                    }
                }
            }
        } else {
            pedirPermisoAntiguo()
            val dir = carpetaPublica(carpeta)
            dir.mkdirs()
            File(dir, nombre).writeBytes(bytes)
            if (prefijoBorrar != null) {
                val archivos = dir.listFiles { f -> f.name.startsWith(prefijoBorrar) && f.name.endsWith(".zip") }
                    ?.sortedByDescending { it.lastModified() }
                    ?: emptyList()
                for ((idx, f) in archivos.withIndex()) {
                    if (f.name == nombre && idx == 0) continue
                    val sobraPorCantidad = idx >= conservar
                    val expirado = limiteSeg != null && (f.lastModified() / 1000L) < limiteSeg
                    if (sobraPorCantidad || expirado) {
                        f.delete()
                    }
                }
            }
        }
        return "Descargas/$carpeta/$nombre"
    }

    /** Recomprime fotos JPEG antiguas que pesen más del objetivo para ahorrar espacio. */
    private fun optimizarFotos(rutaCarpeta: String, maxLado: Int, calidad: Int): Map<String, Long> {
        val dir = File(rutaCarpeta)
        if (!dir.exists() || !dir.isDirectory) return mapOf("optimizadas" to 0L, "ahorrados" to 0L)
        var optimizadas = 0L
        var ahorrados = 0L
        val umbralBytes = if (calidad <= 65) 95_000L else if (calidad <= 75) 210_000L else 380_000L

        for (archivo in dir.listFiles().orEmpty()) {
            if (!archivo.isFile) continue
            val nombre = archivo.name.lowercase()
            if (!nombre.endsWith(".jpg") && !nombre.endsWith(".jpeg")) continue
            val pesoOriginal = archivo.length()
            if (pesoOriginal <= umbralBytes) continue
            try {
                val orientacion = try {
                    ExifInterface(archivo.absolutePath).getAttributeInt(
                        ExifInterface.TAG_ORIENTATION,
                        ExifInterface.ORIENTATION_NORMAL,
                    )
                } catch (_: Exception) {
                    ExifInterface.ORIENTATION_NORMAL
                }

                val optsBounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeFile(archivo.absolutePath, optsBounds)
                val anchoOrig = optsBounds.outWidth
                val altoOrig = optsBounds.outHeight
                if (anchoOrig <= 0 || altoOrig <= 0) continue

                var sample = 1
                while (max(anchoOrig / sample, altoOrig / sample) > maxLado * 2) {
                    sample *= 2
                }
                val decoded = BitmapFactory.decodeFile(
                    archivo.absolutePath,
                    BitmapFactory.Options().apply { inSampleSize = sample },
                ) ?: continue

                val m = Matrix()
                when (orientacion) {
                    ExifInterface.ORIENTATION_ROTATE_90 -> m.postRotate(90f)
                    ExifInterface.ORIENTATION_ROTATE_180 -> m.postRotate(180f)
                    ExifInterface.ORIENTATION_ROTATE_270 -> m.postRotate(270f)
                }
                val mayor = max(decoded.width, decoded.height)
                if (mayor > maxLado) {
                    val escala = maxLado.toFloat() / mayor.toFloat()
                    m.postScale(escala, escala)
                }
                val finalBmp = if (!m.isIdentity) {
                    val nuevo = Bitmap.createBitmap(decoded, 0, 0, decoded.width, decoded.height, m, true)
                    if (nuevo !== decoded) decoded.recycle()
                    nuevo
                } else {
                    decoded
                }

                val out = ByteArrayOutputStream()
                finalBmp.compress(Bitmap.CompressFormat.JPEG, calidad.coerceIn(40, 92), out)
                finalBmp.recycle()
                val nuevosBytes = out.toByteArray()
                if (nuevosBytes.isNotEmpty() && nuevosBytes.size + 4096 < pesoOriginal) {
                    archivo.writeBytes(nuevosBytes)
                    optimizadas++
                    ahorrados += (pesoOriginal - nuevosBytes.size)
                }
            } catch (_: Exception) {
            }
        }
        return mapOf("optimizadas" to optimizadas, "ahorrados" to ahorrados)
    }

    /** Abre directamente los ajustes del canal de notificaciones emergentes en Android. */
    private fun abrirAjustesNotificaciones(): Boolean {
        RecordatorioReceiver.asegurarCanales(this)
        val intents = buildList {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                add(
                    Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS).apply {
                        putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                        putExtra(Settings.EXTRA_CHANNEL_ID, RecordatorioReceiver.CANAL_RECORDATORIOS)
                    }
                )
                add(
                    Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                        putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                    }
                )
            }
            add(
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = Uri.parse("package:$packageName")
                }
            )
        }
        for (i in intents) {
            try {
                startActivity(i)
                return true
            } catch (_: Exception) {
            }
        }
        return false
    }

    /** Devuelve la IPv4 local (Wi-Fi o zona portátil) del teléfono, si existe. */
    private fun obtenerIpLocal(): String? {
        try {
            val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            val red = cm.activeNetwork
            val props = if (red != null) cm.getLinkProperties(red) else null
            props?.linkAddresses?.forEach { la ->
                val addr = la.address
                if (addr is Inet4Address && !addr.isLoopbackAddress && addr.isSiteLocalAddress) {
                    return addr.hostAddress
                }
            }
        } catch (_: Exception) {
        }
        return null
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
