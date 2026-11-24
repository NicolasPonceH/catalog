package cl.catalog.catalog

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import java.util.Calendar

/**
 * Muestra las notificaciones locales de CataLog (100 % sin internet) y
 * reprograma el recordatorio diario al reiniciar el teléfono o cada día.
 */
class RecordatorioReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val activo = prefs.getBoolean("activo", false)
        val hora = prefs.getInt("hora", 20)
        val minuto = prefs.getInt("minuto", 0)
        val titulo = prefs.getString("titulo", "") ?: ""
        val cuerpo = prefs.getString("cuerpo", "") ?: ""

        if (intent?.action == ACTION_RECORDATORIO && activo && cuerpo.isNotBlank()) {
            publicarNotificacion(
                context = context,
                id = ID_RECORDATORIO,
                canalId = CANAL_RECORDATORIOS,
                titulo = titulo.ifBlank { "CataLog" },
                cuerpo = cuerpo,
                enCurso = false,
            )
        }
        if (activo && cuerpo.isNotBlank()) {
            programarAlarma(context, hora, minuto)
        }
    }

    companion object {
        const val PREFS = "catalog_recordatorio"
        const val ACTION_RECORDATORIO = "cl.catalog.RECORDATORIO_DIARIO"
        const val CANAL_RESPALDO = "catalog_respaldo"
        const val CANAL_RECORDATORIOS = "catalog_recordatorios"
        const val ID_RESPALDO = 1001
        const val ID_RECORDATORIO = 1002

        fun asegurarCanales(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val respaldo = NotificationChannel(
                CANAL_RESPALDO,
                "Respaldos de CataLog",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Avisa cuando CataLog guarda un respaldo en el teléfono"
            }
            val recordatorios = NotificationChannel(
                CANAL_RECORDATORIOS,
                "Recordatorios de CataLog",
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                description = "Stickers sin imprimir, lotes abiertos, resumen del día y respaldo externo"
            }
            nm.createNotificationChannel(respaldo)
            nm.createNotificationChannel(recordatorios)
        }

        fun publicarNotificacion(
            context: Context,
            id: Int,
            canalId: String,
            titulo: String,
            cuerpo: String,
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
                android.app.Notification.Builder(context, canalId)
            } else {
                @Suppress("DEPRECATION")
                android.app.Notification.Builder(context)
            }

            builder
                .setSmallIcon(R.mipmap.launcher_icon)
                .setContentTitle(titulo)
                .setContentText(cuerpo)
                .setStyle(android.app.Notification.BigTextStyle().bigText(cuerpo))
                .setContentIntent(pi)
                .setAutoCancel(!enCurso)
                .setOngoing(enCurso)

            if (enCurso) {
                builder.setProgress(0, 0, true)
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
    }
}
