package dev.danhthanh.cloudmail.nativeapp

import android.Manifest
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions
import com.google.firebase.messaging.FirebaseMessaging
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var permissionResult: MethodChannel.Result? = null
    private var channel: MethodChannel? = null
    private var pendingMail: Map<String, Any>? = null

    private fun initializeFirebase(): Boolean {
        if (FirebaseApp.getApps(this).any { it.name == FirebaseApp.DEFAULT_APP_NAME }) return true
        val appId = getString(R.string.cloud_mail_fcm_app_id)
        val apiKey = getString(R.string.cloud_mail_fcm_api_key)
        val project = getString(R.string.cloud_mail_fcm_project_id)
        val senderId = getString(R.string.cloud_mail_fcm_sender_id)
        if (listOf(appId, apiKey, project, senderId).any { it.isBlank() }) return false
        val options = FirebaseOptions.Builder().setApplicationId(appId).setApiKey(apiKey)
            .setProjectId(project).setGcmSenderId(senderId).build()
        FirebaseApp.initializeApp(this, options)
        return true
    }

    private fun permissionGranted() =
        (getSystemService(NotificationManager::class.java)?.areNotificationsEnabled() == true) &&
            (Build.VERSION.SDK_INT < 33 ||
                checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pendingMail = readMail(intent)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cloud_mail/push")
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "configured" -> result.success(listOf(R.string.cloud_mail_fcm_app_id, R.string.cloud_mail_fcm_api_key, R.string.cloud_mail_fcm_project_id, R.string.cloud_mail_fcm_sender_id).all { getString(it).isNotBlank() })
                "permission" -> result.success(permissionGranted())
                "requestPermission" -> {
                    if (Build.VERSION.SDK_INT < 33 || permissionGranted()) {
                        result.success(permissionGranted())
                    } else if (permissionResult != null) {
                        result.error("busy", "A permission request is already active", null)
                    } else {
                        permissionResult = result
                        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 70)
                    }
                }
                "token" -> {
                    if (!permissionGranted() || !initializeFirebase()) {
                        result.error("unavailable", "Push configuration or permission is missing", null)
                    } else {
                        FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
                            if (task.isSuccessful) result.success(task.result)
                            else result.error("registration", "FCM registration failed", null)
                        }
                    }
                }
                "enable" -> {
                    val device = call.argument<String>("device") ?: ""
                    val lang = call.argument<String>("language") ?: "vi"
                    val origin = call.argument<String>("origin") ?: ""
                    val rotation = call.argument<String>("rotation") ?: ""
                    try {
                        MailPushRenewal.enable(this, device, lang, origin, rotation)
                        FirebaseMessaging.getInstance().isAutoInitEnabled = true
                        result.success(null)
                    } catch (_: Exception) {
                        MailPushRenewal.disable(this)
                        result.error("storage", "Push registration could not be saved", null)
                    }
                }
                "disable" -> {
                    MailPushRenewal.disable(this)
                    getSystemService(NotificationManager::class.java)?.cancelAll()
                    pendingMail = null
                    if (FirebaseApp.getApps(this).any { it.name == FirebaseApp.DEFAULT_APP_NAME }) {
                        FirebaseMessaging.getInstance().isAutoInitEnabled = false
                        FirebaseMessaging.getInstance().deleteToken().addOnCompleteListener {
                            result.success(null)
                        }
                    } else {
                        result.success(null)
                    }
                }
                "takeIntent" -> {
                    result.success(pendingMail)
                    pendingMail = null
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun readMail(intent: Intent?): Map<String, Any>? {
        if (intent?.action != MailNotificationService.OPEN_MAIL) return null
        val id = intent.getIntExtra("email_id", 0)
        val device = intent.getStringExtra("device_id") ?: return null
        val registered = getSharedPreferences("cloud_mail_push", MODE_PRIVATE).getString("device", null)
        if (id <= 0 || device != registered) return null
        return mapOf("id" to id, "device" to device)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val mail = readMail(intent) ?: return
        pendingMail = mail
        channel?.invokeMethod("mail", null)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, results: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, results)
        if (requestCode == 70) {
            permissionResult?.success(permissionGranted())
            permissionResult = null
        }
    }
}
