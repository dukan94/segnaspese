plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.dukan94.segnaspese"
    // Alcune dipendenze (flutter_plugin_android_lifecycle, tirato da
    // file_picker/camera) richiedono compileSdk >= 36. Lo fissiamo a 36 invece
    // di flutter.compileSdkVersion (che qui vale 34).
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.dukan94.segnaspese"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        getByName("debug") {
            // Keystore fisso e committato (v. .github/workflows/android-build.yml),
            // non quello generato di default in ~/.android — così ogni build CI
            // firma allo stesso modo e gli aggiornamenti sul telefono si
            // installano sopra quello esistente invece di andare in conflitto.
            storeFile = file("debug.keystore")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
    }

    buildTypes {
        release {
            // Firmato con le stesse chiavi di debug per ora (nessuna
            // distribuzione su store): vedi signingConfigs sopra.
            signingConfig = signingConfigs.getByName("debug")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
