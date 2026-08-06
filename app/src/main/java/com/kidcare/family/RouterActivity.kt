package com.kidcare.family

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.kidcare.family.core.AuthGateway
import com.kidcare.family.databinding.ActivityRouterBinding
import kotlinx.coroutines.launch

/**
 * 런처 액티비티. 저장된 역할에 따라 보호자/자녀 화면으로 보내는 갈림길이다.
 * Task 4 에서 분기 로직이 들어간다. 지금은 익명 로그인이 되는지, uid 를
 * 받아오는지만 화면에 찍어서 확인한다.
 */
class RouterActivity : AppCompatActivity() {

    private lateinit var binding: ActivityRouterBinding

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityRouterBinding.inflate(layoutInflater)
        setContentView(binding.root)

        binding.statusText.text = getString(R.string.connecting)
        lifecycleScope.launch {
            binding.statusText.text = try {
                getString(R.string.uid_format, AuthGateway.signIn())
            } catch (e: Exception) {
                getString(R.string.connect_failed, e.message ?: "")
            }
        }
    }
}
