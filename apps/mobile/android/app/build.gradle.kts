import java.io.FileInputStream
import java.util.Properties

/**
 * Signature de release lue depuis `android/key.properties`, jamais versionné
 * (voir `.gitignore`) : un keystore ou son mot de passe dans le dépôt, c'est
 * la clé de publication de l'app perdue pour de bon — Google n'accepte
 * qu'une seule clé de signature par application, à vie.
 *
 * Le fichier est absent chez qui n'a pas à publier : la release retombe
 * alors sur la clé de debug, exactement comme avant, pour que
 * `flutter run --release` continue de fonctionner en local.
 */
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        FileInputStream(keystorePropertiesFile).use { load(it) }
    }
}
val hasReleaseKeystore = keystorePropertiesFile.exists()

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.echango.promo"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // Identifiant définitif, aligné sur le domaine `promo.echango.com`
        // utilisé par les App Links. Ne plus jamais le changer : Android et
        // iOS traitent un identifiant différent comme une autre application,
        // ce qui couperait la mise à jour pour tous les utilisateurs déjà
        // installés. Doit rester identique à `ANDROID_PACKAGE_NAME` côté
        // backend (`/.well-known/assetlinks.json`).
        applicationId = "com.echango.promo"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = keystoreProperties.getProperty("storeFile")?.let { file(it) }
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // Clé de debug en repli : sans `key.properties`, un `flutter run
            // --release` local doit continuer de marcher. Un artefact signé
            // avec cette clé est en revanche refusé par Google Play — c'est
            // volontaire, ça rend l'oubli impossible à ignorer.
            signingConfig = signingConfigs.getByName(if (hasReleaseKeystore) "release" else "debug")
        }
    }
}

flutter {
    source = "../.."
}
