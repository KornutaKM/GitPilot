plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

// Release signing values come only from the build environment and are never committed.
// With no values configured, bundleRelease is deliberately unsigned for local verification.
private val signingKeys = listOf(
    "GITPILOT_SIGNING_STORE_FILE", "GITPILOT_SIGNING_STORE_PASSWORD",
    "GITPILOT_SIGNING_KEY_ALIAS", "GITPILOT_SIGNING_KEY_PASSWORD"
)
private val signingValues = signingKeys.associateWith { providers.environmentVariable(it).orNull }
private val signingRequested = signingValues.values.any { !it.isNullOrBlank() }
require(!signingRequested || signingValues.values.all { !it.isNullOrBlank() }) {
    "Incomplete release signing configuration. Supply all four GITPILOT_SIGNING_* variables."
}

android {
    namespace = "dev.gitpilot.app"
    compileSdk = 36

    defaultConfig {
        applicationId = "dev.gitpilot.app"
        minSdk = 26
        targetSdk = 36
        versionCode = 12
        versionName = "1.3.0-alpha"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        val githubClientId = providers.gradleProperty("gitpilot.githubClientId").orElse("").get()
        require(githubClientId.matches(Regex("[A-Za-z0-9_-]*"))) { "Invalid GitHub App client ID" }
        buildConfigField("String", "GITHUB_CLIENT_ID", "\"$githubClientId\"")
    }

    signingConfigs {
        if (signingRequested) {
            create("publisher") {
                storeFile = file(signingValues.getValue("GITPILOT_SIGNING_STORE_FILE")!!)
                storePassword = signingValues.getValue("GITPILOT_SIGNING_STORE_PASSWORD")!!
                keyAlias = signingValues.getValue("GITPILOT_SIGNING_KEY_ALIAS")!!
                keyPassword = signingValues.getValue("GITPILOT_SIGNING_KEY_PASSWORD")!!
            }
        }
    }

    buildTypes {
        getByName("release") {
            if (signingRequested) signingConfig = signingConfigs.getByName("publisher")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlin {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }

    buildFeatures { compose = true; buildConfig = true }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2025.12.00")
    implementation(composeBom)
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.activity:activity-compose:1.11.0")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.9.4")
    debugImplementation("androidx.compose.ui:ui-tooling")
    testImplementation("junit:junit:4.13.2")
}
