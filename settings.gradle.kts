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
        // 카카오로 되돌릴 때 쓴다 — 지금은 osmdroid(mavenCentral)로 교체돼 이 저장소가
        // 필요 없다. app/build.gradle.kts 도 kakao-map 의존성을 참조하지 않는다.
        // maven { url = uri("https://devrepo.kakao.com/nexus/repository/kakaomap-releases/") }
    }
}

rootProject.name = "KidCare"
include(":app")
