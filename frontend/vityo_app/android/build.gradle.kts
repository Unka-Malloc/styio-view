import org.gradle.api.provider.Provider

fun providerString(propertyName: String, envName: String): Provider<String> =
    providers.gradleProperty(propertyName)
        .orElse(providers.environmentVariable(envName))

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val vityoAndroidBuildRoot =
    providerString("vityoAndroidBuildRoot", "VITYO_ANDROID_BUILD_ROOT")
        .orElse("../../build")

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir(vityoAndroidBuildRoot)
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
