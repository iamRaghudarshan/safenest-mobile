allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
// Force every PLUGIN to compile against the same SDK as the app.
//
// Setting compileSdk in app/build.gradle.kts alone was not enough: each Flutter
// plugin is its own Gradle project with its own compileSdk, and several still
// ship 34 while flutter_plugin_android_lifecycle now demands 36 from anything
// depending on it. Gradle names the plugins in that error, so it reads as a
// dependency conflict rather than a setting needing a second home.
//
// REGISTERED VIA plugins.withId, NOT afterEvaluate, and placed BEFORE the
// evaluationDependsOn block below. Both matter. The first attempt used
// afterEvaluate and failed with "Cannot run Project.afterEvaluate when the
// project is already evaluated" — evaluationDependsOn(":app") forces evaluation
// during configuration, so by the time that block ran there was nothing left to
// hook. plugins.withId fires as the Android plugin is applied, which is early
// enough to still be setting configuration.
//
// Reflection rather than a typed cast because the Android Gradle Plugin classes
// are not on this file's buildscript classpath — Flutter applies them through
// settings.gradle.kts.
//
// compileSdk only decides which APIs the code may reference. minSdk decides
// which phones can install the app, and nothing here touches it.
subprojects {
    val forceCompileSdk = {
        extensions.findByName("android")?.let { android ->
            // Two spellings, because which one exists depends on the Android
            // Gradle Plugin version: compileSdk (Int) on AGP 8's CommonExtension,
            // compileSdkVersion(int) on the older BaseExtension.
            val applied = listOf("setCompileSdk", "setCompileSdkVersion").any { name ->
                try {
                    android.javaClass.getMethod(name, Int::class.java).invoke(android, 36)
                    true
                } catch (_: NoSuchMethodException) {
                    false
                } catch (e: Exception) {
                    logger.warn("compileSdk override on ${project.path} failed: $e")
                    false
                }
            }
            // SAID OUT LOUD when it does not work. The first version of this
            // wrapped the whole thing in runCatching, so when the method name was
            // wrong it failed silently and the build died later blaming the
            // plugin — which cost two rounds of guessing at the wrong thing. A
            // flag that is never read is the same as no flag at all.
            if (!applied) {
                logger.warn("compileSdk override did NOT apply to ${project.path} " +
                            "— if the AAR metadata check fails, this is why")
            }
        }
    }
    plugins.withId("com.android.library") { forceCompileSdk() }
    plugins.withId("com.android.application") { forceCompileSdk() }
}

// COMPILE THE PLUGINS' KOTLIN. Without this the Android build cannot succeed,
// and it never had.
//
// file_picker's own android/build.gradle does:
//
//     def isAgp9OrAbove = ANDROID_GRADLE_PLUGIN_VERSION...toInteger() >= 9
//     apply plugin: 'com.android.library'
//     if (!isAgp9OrAbove) { apply plugin: 'org.jetbrains.kotlin.android' }
//
// so on AGP 9 — which this project uses — it deliberately does NOT apply the
// Kotlin plugin, expecting AGP 9's built-in Kotlin support to compile its
// sources. That support is opt-in and nothing here opts in, so
// FilePickerPlugin.kt was never compiled at all. The class then does not exist,
// and the APP's Java compile of the generated plugin registrant fails with:
//
//     GeneratedPluginRegistrant.java:24: error: cannot find symbol
//       symbol: class FilePickerPlugin
//
// which names our generated file and reads as a problem with our code. It is
// not; it is a plugin whose sources were silently skipped.
//
// Applied by us, to any library subproject that ships Kotlin and has no Kotlin
// plugin of its own. Scoped that way rather than applied blindly so a plugin
// that already handles itself is left alone.
subprojects {
    plugins.withId("com.android.library") {
        val shipsKotlin = file("src/main/kotlin").isDirectory
        if (shipsKotlin && !plugins.hasPlugin("org.jetbrains.kotlin.android")) {
            logger.lifecycle("applying the Kotlin plugin to ${project.path} " +
                             "— it ships .kt sources and did not apply one itself")
            plugins.apply("org.jetbrains.kotlin.android")
        }
    }
}

// Kotlin 2.x defaults to JVM target 1.8, and these plugins set their Java
// target to 17. Gradle fails that mismatch outright rather than warning, so
// applying the Kotlin plugin above without this trades one build error for
// another.
subprojects {
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
