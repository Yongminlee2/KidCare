package com.kidcare.family.guardian

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import com.google.firebase.firestore.ListenerRegistration
import com.kakao.vectormap.KakaoMap
import com.kakao.vectormap.KakaoMapReadyCallback
import com.kakao.vectormap.LatLng
import com.kakao.vectormap.MapLifeCycleCallback
import com.kakao.vectormap.camera.CameraUpdateFactory
import com.kakao.vectormap.label.Label
import com.kakao.vectormap.label.LabelOptions
import com.kakao.vectormap.label.LabelStyle
import com.kakao.vectormap.label.LabelStyles
import com.kidcare.family.BuildConfig
import com.kidcare.family.R
import com.kidcare.family.core.FamilyRepository
import com.kidcare.family.core.RoleStore
import com.kidcare.family.core.model.ChildStatusDoc
import com.kidcare.family.databinding.FragmentMapTimelineBinding
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Locale

/**
 * 보호자 메인. 카카오맵 위에 아이의 현재 위치를 찍는다.
 *
 * children/{childUid} 문서(= status. 설계서는 별도 하위 문서로 그렸지만
 * StatusReporter 가 문서 자체를 status 로 쓰기로 했다)를 실시간 구독해
 * 상단 카드 문구와 지도 마커를 함께 갱신한다.
 *
 * 3단계에서 하루 경로 폴리라인과 아래쪽 타임라인 목록이 여기 붙는다.
 */
class MapTimelineFragment : Fragment() {

    private var _binding: FragmentMapTimelineBinding? = null
    private val binding get() = _binding!!

    private var kakaoMap: KakaoMap? = null
    private var childLabel: Label? = null
    private var statusListener: ListenerRegistration? = null

    // Firestore 스냅샷(특히 캐시 응답)은 onMapReady 보다 먼저 도착할 수 있다.
    // 그 사이에는 지도에 아무것도 그릴 수 없으니 여기 잠깐 담아뒀다가
    // onMapReady 에서 한 번 더 그린다. 반대로 onMapReady 가 먼저 끝나면
    // render() 가 매번 kakaoMap 이 있는지 보고 바로 그리므로 이 값은 안 쓰인다.
    private var pendingStatus: ChildStatusDoc? = null

    private val timeFormat = SimpleDateFormat("HH:mm", Locale.KOREA)

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?,
    ): View {
        _binding = FragmentMapTimelineBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        if (BuildConfig.KAKAO_APP_KEY.isEmpty()) {
            // 앱키가 없다(개발기에 아직 등록 전) — 지도를 아예 시작하지 않는다.
            // 안내만 띄우고, 페어링·위치 수집 등 이 화면과 무관한 기능은 그대로 돈다.
            binding.noKeyNotice.visibility = View.VISIBLE
            return
        }

        binding.mapView.start(
            object : MapLifeCycleCallback() {
                override fun onMapDestroy() = Unit
                override fun onMapError(error: Exception) {
                    _binding?.statusBar?.text = getString(R.string.map_error, error.message ?: "")
                }
            },
            object : KakaoMapReadyCallback() {
                override fun onMapReady(map: KakaoMap) {
                    // 늦게 도착한 콜백일 수 있다 — 화면이 이미 사라졌으면 무시한다.
                    if (_binding == null) return
                    kakaoMap = map
                    pendingStatus?.let { render(it) }
                }
            },
        )

        subscribe()
    }

    private fun subscribe() {
        val store = RoleStore(requireContext())
        val familyId = store.familyId ?: return
        // Fragment 자신의 lifecycleScope 가 아니라 viewLifecycleOwner 걸 써야 한다.
        // Fragment 스코프를 쓰면 configuration change 로 뷰만 다시 만들어질 때도
        // 이 코루틴이 안 끝나고 살아남아, 옛 리스너가 새로 생긴 뷰 위에 계속
        // 값을 흘려보내는 경합(=사실상 리스너 중복)이 생긴다.
        viewLifecycleOwner.lifecycleScope.launch {
            try {
                val childUid = FamilyRepository.findChildUid(familyId)
                if (childUid == null) {
                    _binding?.statusBar?.text = getString(R.string.map_no_child)
                    return@launch
                }
                statusListener = FamilyRepository.observeChildStatus(
                    familyId,
                    childUid,
                    onChange = { status -> render(status) },
                    onError = { e -> _binding?.statusBar?.text = getString(R.string.map_error, e.message ?: "") },
                )
            } catch (e: CancellationException) {
                // 화면 이탈로 인한 정상 취소다. 삼켜서 실패처럼 취급하면 안 되므로
                // 그대로 다시 던져 코루틴 취소를 완성시킨다(GuardianPairingActivity 와
                // 같은 패턴).
                throw e
            } catch (e: Exception) {
                _binding?.statusBar?.text = getString(R.string.map_error, e.message ?: "")
            }
        }
    }

    /** Firestore 콜백에서도 불릴 수 있어서, onDestroyView 이후엔 아무 뷰도 건드리지 않는다. */
    private fun render(status: ChildStatusDoc) {
        val b = _binding ?: return
        b.statusBar.text = getString(
            R.string.map_status_format,
            status.battery,
            timeFormat.format(status.at),
        )

        val map = kakaoMap
        if (map == null) {
            pendingStatus = status
            return
        }
        pendingStatus = null

        val position = LatLng.from(status.lat, status.lng)
        val label = childLabel
        if (label == null) {
            val styles = LabelStyles.from(
                "child",
                LabelStyle.from(R.drawable.marker_child).setAnchorPoint(0.5f, 1.0f),
            )
            childLabel = map.labelManager?.layer?.addLabel(
                LabelOptions.from("child", position).setStyles(styles)
            )
            map.moveCamera(CameraUpdateFactory.newCenterPosition(position, 16))
        } else {
            label.moveTo(position)
        }
    }

    override fun onResume() {
        super.onResume()
        if (BuildConfig.KAKAO_APP_KEY.isNotEmpty()) _binding?.mapView?.resume()
    }

    override fun onPause() {
        if (BuildConfig.KAKAO_APP_KEY.isNotEmpty()) _binding?.mapView?.pause()
        super.onPause()
    }

    override fun onDestroyView() {
        statusListener?.remove()
        statusListener = null
        kakaoMap = null
        childLabel = null
        pendingStatus = null
        _binding = null
        super.onDestroyView()
    }
}
