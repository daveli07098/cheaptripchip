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

// Some plugins (e.g. receive_sharing_intent 1.8.1) set no JVM target, so Java
// defaults to 1.8 while Kotlin uses the JDK's (21) and Gradle rejects the
// mismatch. Pin every Android library subproject to 17, matching :app.
subprojects {
    val pinJvm17 = {
        extensions.findByType<com.android.build.gradle.LibraryExtension>()?.compileOptions {
            sourceCompatibility = JavaVersion.VERSION_17
            targetCompatibility = JavaVersion.VERSION_17
        }
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
            compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }
    if (state.executed) pinJvm17() else afterEvaluate { pinJvm17() }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
