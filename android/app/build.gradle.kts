plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

import java.util.Properties
import java.io.FileInputStream

// Load keystore properties from key.properties file
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.hjapp.fightersurvival"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        // Set JVM target explicitly as string for compatibility
        jvmTarget = "17"
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.hjapp.fightersurvival"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Configure signing for release builds when a key.properties file is present at the project root
    if (keystorePropertiesFile.exists()) {
        signingConfigs {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                // storeFile is resolved relative to the module project dir (android/app). Common values:
                // - upload-keystore.jks (place file at android/app/upload-keystore.jks)
                // - ../key.jks (place file at android/key.jks)
                val storeFilePath = keystoreProperties["storeFile"] as String
                val resolvedStoreFile = file(storeFilePath)
                storeFile = resolvedStoreFile
                storePassword = keystoreProperties["storePassword"] as String
                // Helpful debug message to show the resolved path (avoids confusion about double 'app' in the path)
                println("Using signing keystore: ${resolvedStoreFile.absolutePath}")
            }
        }
    } else {
        println("WARNING: key.properties not found - release builds will be signed with the debug key."
            + " Create android/key.properties to sign with your release key.")
    }

    buildTypes {
        release {
            // Use the release signing config when available, otherwise fall back to debug
            signingConfig = if (keystorePropertiesFile.exists()) signingConfigs.getByName("release") else signingConfigs.getByName("debug")
            isMinifyEnabled = false
            // Explicitly disable resource shrinking unless code minification is enabled
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}
