package dev.danhthanh.cloudmail.nativeapp

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

class MailNotificationService : FirebaseMessagingService() {
    companion object {
        const val OPEN_MAIL = "dev.danhthanh.cloudmail.nativeapp.OPEN_MAIL"
        private const val CHANNEL = "mail_updates"
    }

    override fun onNewToken(token: String) {
        try { MailPushRenewal.queue(this, token) } catch (_: Exception) {
            // App foreground renewal can recover a local storage failure.
        }
    }

    override fun onMessageReceived(message: RemoteMessage) {
        if (message.data["kind"] != "new_mail") return
        val id = message.data["email_id"]?.toIntOrNull()?.takeIf { it > 0 } ?: return
        val device = message.data["device_id"] ?: return
        val prefs = getSharedPreferences("cloud_mail_push", MODE_PRIVATE)
        if (device != prefs.getString("device", null)) return
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        if (!manager.areNotificationsEnabled()) return
        val vi = prefs.getString("language", "vi") == "vi"
        manager.createNotificationChannel(NotificationChannel(
            CHANNEL, if (vi) "Thư mới" else "New mail", NotificationManager.IMPORTANCE_DEFAULT
        ))
        val intent = Intent(this, MainActivity::class.java).setAction(OPEN_MAIL)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            .putExtra("email_id", id).putExtra("device_id", device)
        val tap = PendingIntent.getActivity(this, id, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        manager.notify(id, Notification.Builder(this, CHANNEL)
            .setSmallIcon(android.R.drawable.ic_dialog_email)
            .setContentTitle("Cloud Mail")
            .setContentText(if (vi) "Bạn có thư mới" else "You have new mail")
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setAutoCancel(true).setContentIntent(tap).build())
    }
}
