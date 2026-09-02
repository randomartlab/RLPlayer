/// 用户指南（帮助页，2026-09-02）：汇总本地识别、补 RJ、翻译、
/// 评论、封面、镜像/登录、搜索、播放条等周边功能用法。
library;

import 'package:flutter/material.dart';

import '../utils/ui_tokens.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('帮助与指南')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            UiSpacing.large, UiSpacing.small, UiSpacing.large, UiSpacing.xLarge),
        children: [
          _Section(
            scheme: scheme,
            title: '一、本地音频识别与准备',
            items: const [
              '扫描根目录可包含任意层级：建议按作品建文件夹，RJ 号写进文件夹名，如「RJ123456 作品标题」。',
              '无 RJ 的音频/文件夹也能入库：以文件夹名/文件名作标题，标注「未识别 RJ」。',
              '文件夹内有图片会自动用作封面；也可在文件树中浏览/查看非封面图片（「图」徽章行）。',
              '支持格式：mp3 / m4a / flac / wav / ogg / opus / aac / wma。',
              '点击「作品」页空态的「如何准备音频文件与文件夹？」可随时查看此说明。',
            ],
          ),
          _Section(
            scheme: scheme,
            title: '二、手动补录 RJ 号',
            items: const [
              '打开「未识别 RJ 号」作品 → 点「填写 RJ」→ 直接输数字（如 416816）或完整 RJ 号。',
              '保存后自动拉取网络元数据/封面/评论并刷新显示；重新扫描不会丢失补录结果。',
            ],
          ),
          _Section(
            scheme: scheme,
            title: '三、翻译功能',
            items: const [
              '详情页标题右侧「译」按钮：翻译非中文标题；网络参考信息 CV 行旁可翻译 CV 名。',
              '文件树「译文/原文」按钮：一键翻译整树非中文文件名，再点切回原文。',
              '评论区每条评论可点翻译（译文在原文下方淡色块中显示）。',
            ],
          ),
          _Section(
            scheme: scheme,
            title: '四、封面规则',
            items: const [
              '本地封面优先级：封面关键词图片（cover/表紙 等）→ 与音频同名 → 文件夹内最大图片。',
              '无本地封面时自动拉网络封面（asmr.one / DLsite）落盘缓存。',
              '换封面后重扫一次即可生效。',
            ],
          ),
          _Section(
            scheme: scheme,
            title: '五、评论区',
            items: const [
              '详情页点「评论」打开底部抽屉（上拉/下拉调整高度）。',
              '数据源：asmr.one → DLsite 官方评论接口；本地与在线作品均支持。',
              '评论接口需登录 asmr.one 账号；DLsite 直抓不受登录限制但依赖网络可达。',
            ],
          ),
          _Section(
            scheme: scheme,
            title: '六、镜像与账号',
            items: const [
              '设置 → 服务器与账号：镜像可测速、自动选最低延迟，也可手动固定。',
              '登录用 asmr.one（kikoeru）账号；「DLsite 代理」只对 DLsite 元数据请求生效，'
                  '留空直连；「测试 DLsite 连接」可诊断可达性。',
              '规则 VPN 用户若 DLsite 不通：把 dlsite.com 加入代理规则，或填本地代理端口。',
            ],
          ),
          _Section(
            scheme: scheme,
            title: '七、搜索与筛选',
            items: const [
              '搜索页「本地/全网」切换：全网按 关键词/RJ/标签/社团/声优 全表选择器搜索。',
              '输入单字即弹候选（CV/社团/标签/标题聚合）。',
              '本地作品页工具栏：排序（评分/销量/评价量等 + 正逆序）、筛选（社团/CV/标签）。',
              '「组合」搜索类型可叠加多条件并切换 全部满足/任一满足。',
            ],
          ),
          _Section(
            scheme: scheme,
            title: '八、播放与界面',
            items: const [
              '任何页面底部有迷你播放条（播放中），点击回到播放页；全屏播放页自动隐藏。',
              '播放页封面与歌词左右滑动切换，点封面也可切换。',
              '主题：设置 → 主题下拉选 10 款预设；界面字体大小可调。',
              '文件树里「词/字」徽章行 = 歌词/字幕文件（点击预览）；「图」= 图片（点击大图）。',
            ],
          ),
          _Section(
            scheme: scheme,
            title: '九、作品状态',
            items: const [
              '详情页「想听 / 在听 / 听过」+「评分」用于个人标记，本地保存。',
            ],
          ),
          const SizedBox(height: UiSpacing.medium),
          Text(
            '仍有问题？告诉我具体场景，我来定位修复。',
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.scheme, required this.title, required this.items});

  final ColorScheme scheme;
  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: UiSpacing.medium),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: scheme.primary)),
          const SizedBox(height: UiSpacing.xSmall),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: scheme.onSurfaceVariant,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(item,
                        style: const TextStyle(fontSize: 13, height: 1.5)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
