pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
        // 네이버 지도 Android SDK 공식 저장소.
        maven { url = uri("https://repository.map.naver.com/archive/maven") }
    }
}

rootProject.name = "KidCare"
include(":app")
