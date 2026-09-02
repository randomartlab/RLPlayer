/// 主题模式枚举。
enum AppThemeMode {
  system, // 跟随系统
  light, // 浅色模式
  dark, // 深色模式
}

/// 颜色方案类型枚举（PRD §4.1：5 套手写 Scheme + 1 套动态取色）。
enum ColorSchemeType {
  oceanBlue, // 海洋蓝（默认，PRD 决策 9）
  forestGreen, // 森林绿
  sunsetOrange, // 日落橙
  lavenderPurple, // 薰衣草紫
  sakuraPink, // 樱花粉
  // ---- 2026-09-02 新增五款三方风格主题（凑满十款下拉）----
  inkBlack, // 墨玉黑（灰金暗调）
  roseGold, // 玫瑰金
  tealMint, // 青碧薄荷
  amberHoney, // 琥珀蜜黄
  deepSpace, // 深空紫夜
  dynamic, // 系统动态取色（Android 12+）
}
