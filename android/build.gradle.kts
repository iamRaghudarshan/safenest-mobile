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
subprojects {
    project.evaluationDependsOn(":app")
}

// Force every PLUGIN to compile against the same SDK as the app.
//
// Setting compileSdk in app/build.gradle.kts was not enough, and the second CI
// build failed the same way as the first. Each Flutter plugin is its own Gradle
// project with its own compileSdk, and several still ship 34 while
// flutter_plugin_android_lifecycle now demands that anything depending on it
// uses 36 or later. Gradle names the plugins in the error, so it reads as a
// dependency conflict rather than a setting that has to be applied in a second
// place.
//
// compileSdk only decides which APIs the code may reference. minSdk decides
// which phones can install the app, and this leaves that alone — so nobody
// loses support for their handset because of this block.
subprojects {
    afterEvaluate {
        extensions.findByName("android")?.let { android ->
            try {
                val setter = android.javaClass.getMethod("setCompileSdkVersion", Int::class.java)
                setter.invoke(android, 36)
            } catch (_: Exception) {
                // A subproject whose android extension does not expose it is not
                // worth failing the build over — it will surface in the AAR
                // check if it genuinely matters.
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
