#!/bin/bash
# KikoLocal 静态分析脚本
#
# flutter analyze 的 LSP 通道在含中文的项目路径下会崩溃（Flutter 工具
# 对非 ASCII 路径的 JSON 消息分帧 bug），本脚本把源码同步到 ASCII 临时
# 路径后执行分析。flutter build / flutter test 在中文路径下正常。
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="${TMPDIR:-/tmp}/kiko_analyze"

rsync -a --delete \
  --exclude build --exclude .dart_tool --exclude .gradle --exclude .git \
  "$PROJECT_DIR/" "$TMP_DIR/"

cd "$TMP_DIR"
flutter pub get > /dev/null
flutter analyze "$@"
