package com.kidcare.family

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import com.kidcare.family.databinding.ActivityRouterBinding

/**
 * 런처 액티비티. 저장된 역할에 따라 보호자/자녀 화면으로 보내는 갈림길이다.
 * Task 4 에서 분기 로직이 들어간다. 지금은 뼈대가 도는지만 확인한다.
 */
class RouterActivity : AppCompatActivity() {

    private lateinit var binding: ActivityRouterBinding

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityRouterBinding.inflate(layoutInflater)
        setContentView(binding.root)
        binding.statusText.text = getString(R.string.app_name)
    }
}
