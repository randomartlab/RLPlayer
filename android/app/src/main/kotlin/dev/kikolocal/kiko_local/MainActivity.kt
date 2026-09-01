package dev.kikolocal.kiko_local

import com.ryanheise.audioservice.AudioServiceActivity

/// audio_service 要求宿主 Activity 提供 AudioService 的 FlutterEngine
/// 配置（官方 README 接入步骤），否则 AudioService.init 抛
/// IllegalStateException 导致启动卡 splash。
class MainActivity : AudioServiceActivity()
