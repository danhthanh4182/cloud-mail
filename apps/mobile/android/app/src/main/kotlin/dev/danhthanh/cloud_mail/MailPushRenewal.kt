package dev.danhthanh.cloudmail.nativeapp

import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.ComponentName
import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import org.json.JSONObject
import java.net.URL
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import javax.net.ssl.HttpsURLConnection

internal object MailPushRenewal {
    private const val KEY = "cloud_mail_push_rotation"
    private const val JOB = 8124

    private fun secret(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(KEY, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").run {
            init(KeyGenParameterSpec.Builder(KEY, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
            generateKey()
        }
    }

    private fun encrypt(value: String): String {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, secret())
        return Base64.encodeToString(cipher.iv + cipher.doFinal(value.toByteArray()), Base64.NO_WRAP)
    }

    private fun decrypt(value: String): String {
        val data = Base64.decode(value, Base64.NO_WRAP)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, secret(), GCMParameterSpec(128, data.copyOfRange(0, 12)))
        return cipher.doFinal(data.copyOfRange(12, data.size)).decodeToString()
    }

    fun enable(context: Context, device: String, language: String, origin: String, rotationKey: String) {
        context.getSharedPreferences("cloud_mail_push", Context.MODE_PRIVATE).edit()
            .putString("device", device).putString("language", language)
            .putString("rotation", encrypt(rotationKey)).putString("origin", origin)
            .remove("pending_token").commit()
    }

    fun disable(context: Context) {
        context.getSharedPreferences("cloud_mail_push", Context.MODE_PRIVATE).edit().clear().commit()
        context.getSystemService(JobScheduler::class.java)?.cancel(JOB)
    }

    fun queue(context: Context, token: String) {
        val prefs = context.getSharedPreferences("cloud_mail_push", Context.MODE_PRIVATE)
        if (!prefs.contains("rotation")) return
        prefs.edit().putString("pending_token", encrypt(token)).commit()
        context.getSystemService(JobScheduler::class.java)?.schedule(
            JobInfo.Builder(JOB, ComponentName(context, MailPushRenewalService::class.java))
                .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY).build()
        )
    }

    fun renew(context: Context): Boolean {
        val prefs = context.getSharedPreferences("cloud_mail_push", Context.MODE_PRIVATE)
        val device = prefs.getString("device", null) ?: return false
        val origin = prefs.getString("origin", null) ?: return false
        val rotation = prefs.getString("rotation", null) ?: return false
        val pending = prefs.getString("pending_token", null) ?: return false
        val url = URL(origin.trimEnd('/') + "/api/mobile/push/renew")
        if (url.protocol != "https" || url.userInfo != null || url.host.isBlank()) return false
        val connection = url.openConnection() as HttpsURLConnection
        try {
            connection.requestMethod = "PUT"
            connection.connectTimeout = 7000
            connection.readTimeout = 7000
            connection.instanceFollowRedirects = false
            connection.doOutput = true
            connection.setRequestProperty("Content-Type", "application/json")
            val body = JSONObject().put("deviceId", device).put("rotationKey", decrypt(rotation))
                .put("token", decrypt(pending)).toString().toByteArray()
            connection.outputStream.use { it.write(body) }
            val status = connection.responseCode
            val code = if (status in 200..299) {
                val response = connection.inputStream.use { stream ->
                    val bytes = ByteArray(4096)
                    var length = 0
                    while (length < bytes.size) {
                        val count = stream.read(bytes, length, bytes.size - length)
                        if (count < 0) break
                        length += count
                    }
                    bytes.decodeToString(endIndex = length)
                }
                JSONObject(response).optInt("code", 502)
            } else status
            if (code == 200 || code in listOf(400, 401, 403, 404, 409)) {
                if (prefs.getString("pending_token", null) == pending) {
                    prefs.edit().remove("pending_token").commit()
                }
                return false
            }
            return true
        } finally {
            connection.disconnect()
        }
    }
}

class MailPushRenewalService : JobService() {
    override fun onStartJob(params: JobParameters): Boolean {
        Thread {
            val retry = try { MailPushRenewal.renew(this) } catch (_: Exception) { true }
            jobFinished(params, retry)
        }.start()
        return true
    }

    override fun onStopJob(params: JobParameters): Boolean = true
}
