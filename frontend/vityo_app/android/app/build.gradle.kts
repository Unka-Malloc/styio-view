plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

fun gradleIntOverride(propertyName: String, envName: String): Int? =
    providers.gradleProperty(propertyName)
        .orElse(providers.environmentVariable(envName))
        .orNull
        ?.toInt()

fun gradleStringOverride(propertyName: String, envName: String): String? =
    providers.gradleProperty(propertyName)
        .orElse(providers.environmentVariable(envName))
        .orNull

android {
    namespace = "io.vityo.app"
    compileSdk = gradleIntOverride("vityoAndroidCompileSdk", "VITYO_ANDROID_COMPILE_SDK")
        ?: flutter.compileSdkVersion
    ndkVersion = gradleStringOverride("vityoAndroidNdkVersion", "VITYO_ANDROID_NDK_VERSION")
        ?: flutter.ndkVersion
    gradleStringOverride("vityoAndroidBuildToolsVersion", "VITYO_ANDROID_BUILD_TOOLS")
        ?.let { buildToolsVersion = it }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "io.vityo.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = gradleIntOverride("vityoAndroidMinSdk", "VITYO_ANDROID_MIN_SDK")
            ?: flutter.minSdkVersion
        targetSdk = gradleIntOverride("vityoAndroidTargetSdk", "VITYO_ANDROID_TARGET_SDK")
            ?: flutter.targetSdkVersion
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

flutter {
    source = "../.."
}
