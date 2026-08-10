plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
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

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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
