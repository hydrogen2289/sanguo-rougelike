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
#
set -euo pipefail

GODOT_VERSION="${GODOT_VERSION:-4.7}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/godot}"
BIN="$INSTALL_DIR/Godot_v${GODOT_VERSION}-stable_linux.x86_64"

echo "==> 目标 Godot 版本: $GODOT_VERSION"
echo "==> 安装目录: $INSTALL_DIR"

# 1. 基础依赖 (Debian 13)
sudo apt-get update -y
sudo apt-get install -y wget unzip libgl1 libx11-6 libxcursor1 libxrandr2 \
  libxi6 libxinerama1 libxxf86vm1 alsa-utils ca-certificates

# 2. 下载 Godot Linux 二进制
#    注意: asset 命名随版本可能变化；若 404，请到
#    https://github.com/godotengine/godot/releases/tag/${GODOT_VERSION}-stable
#    核对实际的 linux.x86_64.zip 文件名后修改下方 URL。
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"
URL="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip"
echo "==> 下载: $URL"
wget -O godot.zip "$URL"
unzip -o godot.zip
rm -f godot.zip
chmod +x "Godot_v${GODOT_VERSION}-stable_linux.x86_64"

# 3. 放到 PATH
sudo ln -sf "$BIN" /usr/local/bin/godot
echo "==> 创建软链: /usr/local/bin/godot -> $BIN"

# 4. 校验
godot --version || echo "!! godot --version 失败，请检查渲染驱动/依赖"

echo ""
echo "==> 安装完成。"
echo "    桌面里运行编辑器:  godot --rendering-driver opengl3"
echo "    Headless 构建:     godot --headless --build"
echo "    查看版本:          godot --version"
