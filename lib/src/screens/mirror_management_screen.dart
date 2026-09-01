import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/mirror_provider.dart';
import '../utils/ui_tokens.dart';

/// 镜像站点管理 + 登录页（PRD §5.10 服务器与账号分组 / 决策 1、2）。
///
/// - 镜像列表：内置 asmr.one + 自定义（增/删/启用）；手动测速展示延迟排序；
/// - 自动选优开关（关闭 = 手动固定当前镜像）；
/// - Token 登录 / 登出（flutter_secure_storage 加密存储）。
class MirrorManagementScreen extends StatefulWidget {
  const MirrorManagementScreen({super.key});

  @override
  State<MirrorManagementScreen> createState() =>
      _MirrorManagementScreenState();
}

class _MirrorManagementScreenState extends State<MirrorManagementScreen> {
  bool _testing = false;

  Future<void> _runSpeedTest() async {
    setState(() => _testing = true);
    try {
      await context.read<MirrorProvider>().speedTest();
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _addMirror() async {
    final controller = TextEditingController();
    final host = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加镜像实例'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: '域名（如 api.example.com）',
            labelText: '镜像地址',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(controller.text.trim()),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    if (host == null || host.isEmpty || !mounted) return;
    final mirror = context.read<MirrorProvider>();
    final added = await mirror.addMirror(host);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(added ? '已添加 $host' : '该镜像已存在'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _showLoginDialog() async {
    final nameController = TextEditingController();
    final passwordController = TextEditingController();
    final mirror = context.read<MirrorProvider>();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('登录 ${mirror.activeHost}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: '用户名'),
            ),
            const SizedBox(height: UiSpacing.medium),
            TextField(
              controller: passwordController,
              decoration: const InputDecoration(labelText: '密码'),
              obscureText: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(dialogContext);
              final navigator = Navigator.of(dialogContext);
              try {
                final user = await mirror.login(
                  nameController.text.trim(),
                  passwordController.text,
                );
                navigator.pop();
                messenger.showSnackBar(
                  SnackBar(
                    content: Text('登录成功：${user.name}'),
                    duration: const Duration(seconds: 2),
                  ),
                );
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text('登录失败：$e'),
                    duration: const Duration(seconds: 4),
                  ),
                );
              }
            },
            child: const Text('登录'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mirror = context.watch<MirrorProvider>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('服务器与账号')),
      body: ListView(
        padding: const EdgeInsets.all(UiSpacing.medium),
        children: [
          // ---- 账号 ----
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: UiSpacing.small),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: UiSpacing.large),
                    child: Text('账号',
                        style: UiTextStyles.supporting
                            .copyWith(color: scheme.onSurfaceVariant)),
                  ),
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: scheme.primaryContainer,
                      child: Icon(
                          mirror.currentUser != null
                              ? Icons.person
                              : Icons.person_outline,
                          color: scheme.onPrimaryContainer),
                    ),
                    title: Text(mirror.currentUser != null
                        ? mirror.currentUser!.name
                        : '未登录（游客浏览）'),
                    subtitle: Text('当前镜像：${mirror.activeHost}'),
                    trailing: mirror.currentUser != null
                        ? TextButton(
                            onPressed: () => mirror.logout(),
                            child: const Text('登出'),
                          )
                        : FilledButton.tonal(
                            onPressed: _showLoginDialog,
                            child: const Text('登录'),
                          ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: UiSpacing.medium),

          // ---- 镜像测速选优 ----
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: UiSpacing.small),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: UiSpacing.large),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text('镜像站点',
                              style: UiTextStyles.supporting.copyWith(
                                  color: scheme.onSurfaceVariant)),
                        ),
                        TextButton.icon(
                          onPressed: _testing ? null : _runSpeedTest,
                          icon: _testing
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                              : const Icon(Icons.speed, size: 18),
                          label: const Text('测速'),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add, size: 20),
                          tooltip: '添加镜像',
                          onPressed: _addMirror,
                        ),
                      ],
                    ),
                  ),
                  SwitchListTile(
                    title: const Text('自动测速选优'),
                    subtitle: const Text('冷启动与连续失败 3 次后自动切换到延迟最低镜像'),
                    value: mirror.autoSelect,
                    onChanged: (value) =>
                        mirror.pinMirror(value ? null : mirror.activeHost),
                  ),
                  RadioGroup<String>(
                    groupValue: mirror.activeHost,
                    onChanged: (host) {
                      if (host != null) {
                        // 用户手动选镜像 = 关闭自动选优 + 固定（实机反馈：
                        // 之前被 autoSelect 守卫挡住导致点不了）。
                        mirror.pinMirror(host);
                      }
                    },
                    child: Column(
                      children: [
                        for (final instance in mirror.mirrors)
                          ListTile(
                            dense: true,
                            leading: Radio<String>(
                              value: instance.host,
                            ),
                            title: Text(instance.label),
                            subtitle: Text(
                              instance.latencyMs != null
                                  ? '${instance.host} · ${instance.latencyMs}ms'
                                  : instance.host,
                              style: UiTextStyles.supporting,
                            ),
                            isThreeLine: false,
                            trailing: instance.host ==
                                    MirrorProvider.defaultHost
                                ? const Text('内置',
                                    style: TextStyle(fontSize: 11))
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Switch(
                                        value: instance.enabled,
                                        onChanged: (v) => mirror
                                            .setMirrorEnabled(
                                                instance.host, v),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline,
                                            size: 20),
                                        onPressed: () => mirror
                                            .removeMirror(instance.host),
                                      ),
                                    ],
                                  ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
