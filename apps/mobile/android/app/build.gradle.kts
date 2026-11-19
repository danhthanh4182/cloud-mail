plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "dev.danhthanh.cloudmail.nativeapp"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        val firebaseResources = mapOf(
            "APP_ID" to "google_app_id",
            "API_KEY" to "google_api_key",
            "PROJECT_ID" to "project_id",
            "SENDER_ID" to "gcm_defaultSenderId",
        ).mapValues { (key, name) -> name to System.getenv("CLOUD_MAIL_FCM_$key").orEmpty() }
        if (firebaseResources.values.all { (_, value) -> value.isNotBlank() }) {
            firebaseResources.values.forEach { (name, value) -> resValue("string", name, value) }
        }
        listOf("APP_ID", "API_KEY", "PROJECT_ID", "SENDER_ID").forEach { key ->
            resValue("string", "cloud_mail_fcm_${key.lowercase()}", System.getenv("CLOUD_MAIL_FCM_$key") ?: "")
        }
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "dev.danhthanh.cloudmail.nativeapp"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    val releaseStore = System.getenv("CLOUD_MAIL_SIGNING_STORE")
    if (releaseStore != null) {
        signingConfigs.create("cloudMailRelease") {
            storeFile = file(releaseStore)
            storePassword = System.getenv("CLOUD_MAIL_SIGNING_STORE_PASSWORD")
            keyAlias = System.getenv("CLOUD_MAIL_SIGNING_KEY_ALIAS")
            keyPassword = System.getenv("CLOUD_MAIL_SIGNING_KEY_PASSWORD")
        }
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("cloudMailRelease")
        }
    }
}

dependencies {
    implementation("com.google.firebase:firebase-messaging:25.0.1")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
