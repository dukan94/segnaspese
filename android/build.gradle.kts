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
// Forza compileSdk = 36 su TUTTI i moduli plugin. Alcune loro dipendenze
// (es. flutter_plugin_android_lifecycle, tirato da file_picker/camera)
// richiedono compileSdk >= 36, ma i plugin restano compilati contro la 34.
// Compilare contro un SDK più alto è retrocompatibile, quindi è sicuro.
// Va registrato PRIMA del blocco evaluationDependsOn(":app") sotto: quello
// valuta subito :app, e un afterEvaluate su un progetto già valutato darebbe
// errore. Usiamo withGroovyBuilder per non importare i tipi dell'AGP.
subprojects {
    afterEvaluate {
        extensions.findByName("android")?.withGroovyBuilder {
            "compileSdkVersion"(36)
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
