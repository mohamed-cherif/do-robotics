import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: put storeFile/storePassword/keyAlias/keyPassword in
// android/key.properties (git-ignored, see https://flutter.dev/to/reference-keystore).
// Without it, release builds are signed with the debug key so that
// `flutter run --release` keeps working for contributors.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

android {
    namespace = "com.example.do_robotics"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO(owner): choose the final application ID before the first store
        // release; it can never change afterwards. See docs/AUDIT_2026-09.md.
        applicationId = "com.example.do_robotics"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keystoreProperties.containsKey("storeFile")) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
                ?: signingConfigs.getByName("debug")
        }
    }

    packaging {
        jniLibs {
            // The TFLite GPU delegate (2.5 MB per ABI) is never used: detection
            // runs on the CPU with XNNPack. tflite_flutter opens this library
            // lazily, only when a GpuDelegateV2 is created. Remove this line if
            // you add a GPU option.
            excludes += "**/libtensorflowlite_gpu_jni.so"
        }
    }
}

flutter {
    source = "../.."
}
