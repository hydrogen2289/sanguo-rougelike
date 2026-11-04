#!/usr/bin/env bash
#
# setup_instabox.sh
# 在 Instabox (Debian 13, Firecracker microVM) 上搭建 Godot 4 开发环境
# 用法:
#   chmod +x setup_instabox.sh
#   ./setup_instabox.sh            # 安装默认版本 (GODOT_VERSION)
#   GODOT_VERSION=4.7 ./setup_instabox.sh
#
# 说明:
#   - Instabox 预装桌面 + Chromium，可通过其 Web 桌面远程进入。
#   - 云端 VM 多为软件渲染 (llvmpipe)，跑 Godot 4 Forward Plus 编辑器可能卡顿或报错。
#     进桌面跑编辑器时建议加参数:  godot --rendering-driver opengl3
#     若仍异常，把项目渲染器改为 Compatibility (project.godot -> rendering_method=gl_compatibility)。
#   - 构建/跑测试一律用 headless，不需要 GUI:
#       godot --headless --build
#       godot --headless --quit
#       godot --headless --script tests/run.gd   # 若用 gut 等测试框架
#   - 权限: 以 root 运行可直接执行；以普通用户运行需 passwordless sudo
#     (sudo -n true 可用)，否则脚本会提前报错退出。
#   - 下载: Godot 官方 release 已验证 4.7-stable 该 URL 返回 200 (~72MB)；
#     wget 用 --tries/--timeout/--continue 增强云端弱网健壮性，下载后 unzip -t 校验完整性。
#
set -euo pipefail

GODOT_VERSION="${GODOT_VERSION:-4.7}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/godot}"
BIN="$INSTALL_DIR/Godot_v${GODOT_VERSION}-stable_linux.x86_64"

echo "==> 目标 Godot 版本: $GODOT_VERSION"
echo "==> 安装目录: $INSTALL_DIR"

# ---------- 0. 权限检查: 确定是否使用 sudo ----------
if [ "$(id -u)" -eq 0 ]; then
  SUDO=""
  echo "==> 以 root 运行，无需 sudo"
else
  if ! command -v sudo >/dev/null 2>&1; then
    echo "!! 当前为非 root 且未安装 sudo，无法继续。请以 root 运行或先安装 sudo。"
    exit 1
  fi
  if ! sudo -n true 2>/dev/null; then
    echo "!! 需要 passwordless sudo (sudo -n true 失败)。请在 /etc/sudoers 配置 NOPASSWD 或以 root 运行。"
    exit 1
  fi
  SUDO="sudo"
  echo "==> 使用 sudo 提权"
fi

# 1. 基础依赖 (Debian 13)
$SUDO apt-get update -y
$SUDO apt-get install -y wget unzip libgl1 libx11-6 libxcursor1 libxrandr2 \
  libxi6 libxinerama1 libxxf86vm1 alsa-utils ca-certificates

# 2. 下载 Godot Linux 二进制 (弱网健壮: 重试 + 续传 + 完整性校验)
#    Godot 4.7-stable 该 URL 已验证返回 200 (~72MB)。若升级版本后 404，
#    到 https://github.com/godotengine/godot/releases/tag/${GODOT_VERSION}-stable
#    核对实际的 linux.x86_64.zip 文件名后修改下方 URL。
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"
URL="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip"
echo "==> 下载: $URL"
wget --tries=3 --timeout=30 --continue -O godot.zip "$URL"

# 校验 zip 完整性，避免云端下到半截/损坏文件后在 unzip 阶段才报错
if ! unzip -t godot.zip >/dev/null 2>&1; then
  echo "!! 下载的 godot.zip 不完整或损坏 (unzip -t 失败)。请手动下载: $URL"
  exit 1
fi
unzip -o godot.zip
rm -f godot.zip
chmod +x "Godot_v${GODOT_VERSION}-stable_linux.x86_64"

# 3. 放到 PATH
$SUDO ln -sf "$BIN" /usr/local/bin/godot
echo "==> 创建软链: /usr/local/bin/godot -> $BIN"

# 4. 校验
godot --version || echo "!! godot --version 失败，请检查渲染驱动/依赖"

echo ""
echo "==> 安装完成。"
echo "    桌面里运行编辑器:  godot --rendering-driver opengl3"
echo "    Headless 构建:     godot --headless --build"
echo "    查看版本:          godot --version"
