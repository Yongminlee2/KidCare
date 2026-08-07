package com.kidcare.family

import android.app.Application
import java.io.File
import org.osmdroid.config.Configuration

/**
 * 앱 진입점.
 *
 * osmdroid는 카카오맵과 달리 앱키 발급이 필요 없다 — OpenStreetMap 타일은 등록 없이
 * 누구나 받아올 수 있다. 대신 타일을 하나라도 요청하기 전에 사용자 에이전트(User-Agent)를
 * 반드시 지정해야 한다. OSM 공용 타일 서버는 User-Agent로 요청 주체를 구분하는데, 기본값을
 * 그대로 두는 앱이 많아지면 서버가 그 값 자체를 차단할 수 있다 — 그러면 이 앱뿐 아니라
 * osmdroid를 쓰는 다른 앱까지 함께 막히는 정책 위반이 된다. applicationId처럼 앱마다
 * 고유한 값을 넣는 것이 osmdroid 공식 정책이다.
 */
class KidCareApp : Application() {

    override fun onCreate() {
        super.onCreate()
        val config = Configuration.getInstance()
        config.userAgentValue = BuildConfig.APPLICATION_ID

        // 타일 캐시 위치를 앱 전용 캐시 폴더 아래로 고정한다. 지정하지 않으면 osmdroid가
        // 기기별로 "가장 여유 있는 쓰기 가능 저장소"를 스스로 탐색하는데(jar 역어셈블로
        // 확인 — StorageUtils.getBestWritableStorage), API 29 미만 기기에서는 그 후보에
        // 공용 외장 저장소 루트도 섞여 들어간다. 이 앱은 WRITE_EXTERNAL_STORAGE 권한이
        // 없어 그 경로는 결국 쓰기에 실패해 앱 전용 폴더로 되돌아가지만, 그 판단을 osmdroid
        // 내부 탐색에 맡기지 않고 처음부터 캐시 목적에 맞는 cacheDir 아래로 고정해 버린다
        // — 추가 권한이 전혀 필요 없고, 기기 저장공간이 부족하면 시스템이 알아서 비운다.
        val tileCacheDir = File(cacheDir, "osmdroid")
        config.osmdroidBasePath = tileCacheDir
        config.osmdroidTileCache = File(tileCacheDir, "tiles")
    }
}
