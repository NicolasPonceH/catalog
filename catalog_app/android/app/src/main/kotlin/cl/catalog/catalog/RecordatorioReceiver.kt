package cl.catalog.catalog

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import java.util.Calendar

/**
 * Muestra las notificaciones locales de CataLog con diseño de marca (logo grande a color,
 * silueta monocroma, acento naranja y prioridad Heads-Up Pop-up) y mantiene activas tanto
 * la alarma de cierre diario como los recordatorios periódicos durante el día.
 */
class RecordatorioReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val activo = prefs.getBoolean("activo", false)
        val hora = prefs.getInt("hora", 20)
        val minuto = prefs.getInt("minuto", 0)
        val titulo = prefs.getString("titulo", "") ?: ""
        val cuerpo = prefs.getString("cuerpo", "") ?: ""

        val periodicoActivo = prefs.getBoolean("periodico_activo", false)
        val intervaloMin = prefs.getInt("intervalo_min", 60)
        val tituloPeriodico = prefs.getString("titulo_periodico", "") ?: ""
        val cuerpoPeriodico = prefs.getString("cuerpo_periodico", "") ?: ""

        when (intent?.action) {
            ACTION_RECORDATORIO -> {
                if (activo && cuerpo.isNotBlank()) {
                    publicarNotificacion(
                        context = context,
                        id = ID_RECORDATORIO,
                        canalId = CANAL_RECORDATORIOS,
                        titulo = titulo.ifBlank { "Resumen del día · CataLog" },
                        cuerpo = cuerpo,
                        subtitulo = "Cierre de jornada",
                        enCurso = false,
                    )
                }
                if (activo && cuerpo.isNotBlank()) {
                    programarAlarma(context, hora, minuto)
                }
            }
            ACTION_PERIODICO -> {
                if (periodicoActivo && intervaloMin > 0 && cuerpoPeriodico.isNotBlank()) {
                    val ahoraHora = Calendar.getInstance().get(Calendar.HOUR_OF_DAY)
                    // Avisa en horario diurno/laboral (07:00 a 22:59) para no despertar en la madrugada.
                    if (ahoraHora in 7..22) {
                        publicarNotificacion(
                            context = context,
                            id = ID_PERIODICO,
                            canalId = CANAL_RECORDATORIOS,
                            titulo = tituloPeriodico.ifBlank { "Pendientes en CataLog" },
                            cuerpo = cuerpoPeriodico,
                            subtitulo = "Recordatorio periódico",
                            enCurso = false,
                        )
                    }
                    programarPeriodica(context, intervaloMin)
                }
            }
            Intent.ACTION_BOOT_COMPLETED -> {
                if (activo && cuerpo.isNotBlank()) {
                    programarAlarma(context, hora, minuto)
                }
                if (periodicoActivo && intervaloMin > 0 && cuerpoPeriodico.isNotBlank()) {
                    programarPeriodica(context, intervaloMin)
                }
            }
        }
    }

    companion object {
        const val PREFS = "catalog_recordatorio"
        const val ACTION_RECORDATORIO = "cl.catalog.RECORDATORIO_DIARIO"
        const val ACTION_PERIODICO = "cl.catalog.RECORDATORIO_PERIODICO"
        const val CANAL_PROGRESO = "catalog_progreso_v4"
        const val CANAL_RECORDATORIOS = "catalog_alertas_popup_v4"
        const val ID_RESPALDO = 1001
        const val ID_RECORDATORIO = 1002
        const val ID_PERIODICO = 1003
        const val ID_AL_SALIR = 1004
        const val ID_ESCANEO = 1005

        private const val COLOR_MARINO = 0xFF0E2A47.toInt()
        private const val COLOR_NARANJA = 0xFFFF7A1A.toInt()

        @Volatile
        private var logoCache: Bitmap? = null

        /** Dibuja la insignia oficial de CataLog (fondo azul marino, aro naranja y logo nítido). */
        private fun obtenerLogoGrande(context: Context): Bitmap? {
            logoCache?.let { if (!it.isRecycled) return it }
            return try {
                val lado = 192
                val bmp = Bitmap.createBitmap(lado, lado, Bitmap.Config.ARGB_8888)
                val canvas = Canvas(bmp)
                val rect = RectF(4f, 4f, lado - 4f, lado - 4f)
                val pinturaFondo = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    color = COLOR_MARINO
                    style = Paint.Style.FILL
                }
                val pinturaBorde = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    color = COLOR_NARANJA
                    style = Paint.Style.STROKE
                    strokeWidth = 6f
                }
                canvas.drawRoundRect(rect, 46f, 46f, pinturaFondo)
                canvas.drawRoundRect(rect, 46f, 46f, pinturaBorde)

                val fg = context.resources.getDrawable(R.drawable.ic_launcher_foreground, context.theme)
                // El foreground adaptativo incluye margen interno (~18%), así que lo expandimos levemente para que el logo luzca grande.
                val sangria = -18
                fg.setBounds(sangria, sangria, lado - sangria, lado - sangria)
                fg.draw(canvas)
                logoCache = bmp
                bmp
            } catch (_: Exception) {
                null
            }
        }

        fun asegurarCanales(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            // Limpiar canales de versiones previas para no dejar duplicados en Ajustes de Android
            for (viejo in listOf(
                "catalog_respaldo",
                "catalog_recordatorios",
                "catalog_progreso_v2",
                "catalog_recordatorios_v2",
            )) {
                try {
                    nm.deleteNotificationChannel(viejo)
                } catch (_: Exception) {
                }
            }

            val progreso = NotificationChannel(
                CANAL_PROGRESO,
                "Respaldos en preparación",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Muestra la barra mientras se empaqueta un respaldo"
                setShowBadge(false)
            }

            val sonido = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            val audioAttr = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION_EVENT)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()

            // IMPORTANCE_HIGH + sonido de evento + vibración activan el banner emergente (Heads-Up Pop-up)
            val recordatorios = NotificationChannel(
                CANAL_RECORDATORIOS,
                "Alertas emergentes de CataLog",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "Pop-up en pantalla: stickers sin imprimir, lote abierto, escaneos y respaldos"
                setSound(sonido, audioAttr)
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 280, 140, 280)
                enableLights(true)
                lightColor = COLOR_NARANJA
                setShowBadge(true)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }

            nm.createNotificationChannel(progreso)
            nm.createNotificationChannel(recordatorios)
        }

        fun publicarNotificacion(
            context: Context,
            id: Int,
            canalId: String,
            titulo: String,
            cuerpo: String,
            subtitulo: String = "",
            enCurso: Boolean,
        ) {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && !nm.areNotificationsEnabled()) return
            asegurarCanales(context)

            val abrirApp = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val pi = PendingIntent.getActivity(
                context,
                id,
                abrirApp,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )

            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(context, canalId)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(context)
            }

            // Silueta nítida del catalítico en barra superior + insignia grande a todo color en la tarjeta
            builder
                .setSmallIcon(R.drawable.ic_launcher_monochrome)
                .setColor(COLOR_NARANJA)
                .setContentTitle(titulo)
                .setContentText(cuerpo)
                .setStyle(
                    Notification.BigTextStyle()
                        .setBigContentTitle(titulo)
                        .bigText(cuerpo)
                        .setSummaryText(subtitulo.ifBlank { "CataLog" })
                )
                .setContentIntent(pi)
                .setWhen(System.currentTimeMillis())
                .setShowWhen(true)
                .setAutoCancel(!enCurso)
                .setOngoing(enCurso)
                .setOnlyAlertOnce(enCurso)
                .setVisibility(Notification.VISIBILITY_PUBLIC)

            if (subtitulo.isNotBlank()) {
                builder.setSubText(subtitulo)
            }

            obtenerLogoGrande(context)?.let { builder.setLargeIcon(it) }

            if (enCurso) {
                builder.setProgress(0, 0, true)
                @Suppress("DEPRECATION")
                builder.setPriority(Notification.PRIORITY_LOW)
            } else {
                builder.setCategory(Notification.CATEGORY_REMINDER)
                val accionAbrir = Notification.Action.Builder(
                    R.drawable.ic_launcher_monochrome,
                    "Abrir CataLog",
                    pi,
                ).build()
                builder.addAction(accionAbrir)
                @Suppress("DEPRECATION")
                builder.setPriority(Notification.PRIORITY_MAX)
                @Suppress("DEPRECATION")
                builder.setDefaults(Notification.DEFAULT_ALL)
            }

            nm.notify(id, builder.build())
        }

        fun programarAlarma(context: Context, hora: Int, minuto: Int) {
            val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val intent = Intent(context, RecordatorioReceiver::class.java).apply {
                action = ACTION_RECORDATORIO
            }
            val pi = PendingIntent.getBroadcast(
                context,
                ID_RECORDATORIO,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val cal = Calendar.getInstance().apply {
                set(Calendar.HOUR_OF_DAY, hora.coerceIn(0, 23))
                set(Calendar.MINUTE, minuto.coerceIn(0, 59))
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
                if (timeInMillis <= System.currentTimeMillis() + 5_000L) {
                    add(Calendar.DAY_OF_YEAR, 1)
                }
            }
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, cal.timeInMillis, pi)
        }

        fun cancelarAlarma(context: Context) {
            val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val intent = Intent(context, RecordatorioReceiver::class.java).apply {
                action = ACTION_RECORDATORIO
            }
            val pi = PendingIntent.getBroadcast(
                context,
                ID_RECORDATORIO,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            am.cancel(pi)
        }

        fun programarPeriodica(context: Context, intervaloMinutos: Int) {
            val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val intent = Intent(context, RecordatorioReceiver::class.java).apply {
                action = ACTION_PERIODICO
            }
            val pi = PendingIntent.getBroadcast(
                context,
                ID_PERIODICO,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val saltoMs = intervaloMinutos.coerceAtLeast(15).toLong() * 60_000L
            val disparo = System.currentTimeMillis() + saltoMs
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, disparo, pi)
        }

        fun cancelarPeriodica(context: Context) {
            val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val intent = Intent(context, RecordatorioReceiver::class.java).apply {
                action = ACTION_PERIODICO
            }
            val pi = PendingIntent.getBroadcast(
                context,
                ID_PERIODICO,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            am.cancel(pi)
        }
    }
}
