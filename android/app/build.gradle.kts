import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing is loaded from android/key.properties for local builds, or from
// environment variables in CI. Absent both, the release build falls back to debug
// so `flutter run --release` still works on a machine with no keystore — but that
// APK is NOT distributable: the debug key is public, and Android refuses an
// in-place update whose signature changed, so shipping a debug APK once would lock
// every install out of every real update afterwards.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "online.raghudarshan.safenest"

    // Pinned, not flutter.compileSdkVersion. That default was 34, and the first
    // CI build failed on it: flutter_plugin_android_lifecycle now requires
    // everything depending on it to compile against 36 or later. The failure
    // names the plugin rather than this line, so it reads as a dependency
    // problem when it is a project setting.
    //
    // compileSdk only says which APIs the code may reference. It does not change
    // which phones can install the app — minSdk does that, and it stays low.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local_notifications, which uses java.time to work
        // out when an alarm should fire. minSdk here is 23, and java.time only
        // arrived in the platform at 26 — desugaring is what supplies it on the
        // older phones this app deliberately still supports.
        //
        // Without it the build fails at checkReleaseAarMetadata with
        // "requires core library desugaring to be enabled", which names the
        // setting but not where it goes.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // Deliberately NOT the same string as the iOS bundle id. Apple's had to
        // become safenest.raghudarshan.online because the reverse-DNS form was
        // taken globally; Android's is independent, already registered nowhere,
        // and changing it would mean moving the Kotlin package folders for no
        // gain.
        applicationId = "online.raghudarshan.safenest"

        // 23, not flutter.minSdkVersion. flutter_secure_storage needs it for
        // EncryptedSharedPreferences — which is the whole reason the sign-in
        // token is not sitting in a plain XML file readable by anything with
        // root. Android 6 and later, so about every phone still in use.
        minSdk = 23
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            // key.properties wins locally; env vars are how CI supplies it.
            val storePath = keystoreProperties.getProperty("storeFile")
                ?: System.getenv("ANDROID_KEYSTORE_PATH")
            if (storePath != null) {
                storeFile = file(storePath)
                storePassword = keystoreProperties.getProperty("storePassword")
                    ?: System.getenv("ANDROID_KEYSTORE_PASSWORD")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                    ?: System.getenv("ANDROID_KEY_ALIAS")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                    ?: System.getenv("ANDROID_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            // The release keystore when it is available (a machine with
            // key.properties, or CI with the secrets), debug otherwise so a
            // keyless dev build still runs. See the keystoreProperties note above
            // for why a debug-signed release must never be distributed.
            val rel = signingConfigs.getByName("release")
            signingConfig = if (rel.storeFile != null) rel
                            else signingConfigs.getByName("debug")
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

dependencies {
    // The other half of isCoreLibraryDesugaringEnabled above. Enabling the flag
    // without this fails with "core library desugaring is enabled but no
    // desugar_jdk_libs dependency was found" — the two are one setting written
    // in two places.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
