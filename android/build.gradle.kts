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

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
