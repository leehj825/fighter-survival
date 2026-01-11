import com.android.build.gradle.LibraryExtension

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Ensure Android library modules that don't declare `namespace` get a default one.
// This avoids AGP errors when plugin packages in the pub cache (e.g. google_mobile_ads)
// were published without the `namespace` property.
subprojects {
    plugins.withId("com.android.library") {
        extensions.configure<LibraryExtension> {
            // Assign a deterministic namespace based on project name if missing.
            if (namespace.isNullOrBlank()) {
                // Special-case known plugins that expect a particular package for their R class
                namespace = when (project.name) {
                    "google_mobile_ads" -> "io.flutter.plugins.googlemobileads"
                    else -> "pub.${project.name.replace('-', '_')}"
                }
            }
        }
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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
