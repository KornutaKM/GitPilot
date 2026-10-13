plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "dev.gitpilot.app"
    compileSdk = 36

    defaultConfig {
        applicationId = "dev.gitpilot.app"
        minSdk = 26
        targetSdk = 35
        versionCode = 9
        versionName = "1.0.0-alpha"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        val githubClientId = providers.gradleProperty("gitpilot.githubClientId").orElse("").get()
        require(githubClientId.matches(Regex("[A-Za-z0-9_-]*"))) { "Invalid GitHub App client ID" }
        buildConfigField("String", "GITHUB_CLIENT_ID", "\"$githubClientId\"")
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
