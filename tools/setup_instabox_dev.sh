#!/usr/bin/env bash
#
# setup_instabox_dev.sh  —  Instabox 云端开发机一键初始化
#
# 用法 (在 Instabox 终端里):
#   bash tools/setup_instabox_dev.sh
#
# 工作机制 (可重复运行):
#   第 1 次运行: 生成 SSH key -> 打印公钥 -> 提示你去 GitHub 添加 -> 退出
#   你添加公钥后, 第 2 次运行: 检测到已认证 -> clone 仓库 -> 安装 Godot -> 完成
#
# 说明:
#   - 本脚本只负责"拉起开发环境", 不改动你的游戏代码。
#   - Instabox 免费档空闲 30 分钟自动暂停, 但持久盘保留数据, 重连后重跑本脚本即可 (仓库已存在会改为 pull)。
#   - Godot 编辑器在云端多为软件渲染, 进桌面请用:  godot --rendering-driver opengl3
#
set -euo pipefail

REPO_SSH="git@github.com:hydrogen2289/sanguo-rougelike.git"
REPO_DIR="$HOME/sanguo-rougelike"
KEY="$HOME/.ssh/id_ed25519"

echo "==> Instabox 开发环境一键初始化"

# ---------- 1. 准备 SSH key ----------
if [ ! -f "$KEY" ]; then
  echo "==> 未检测到 SSH key, 生成: $KEY"
  ssh-keygen -t ed25519 -C "instabox-dev" -N ""
else
  echo "==> 已存在 SSH key: $KEY"
fi

# ---------- 2. 测试 GitHub SSH 认证 ----------
if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -T git@github.com 2>&1 | grep -q authenticated; then
  echo "==> GitHub SSH 认证已通过"
else
  echo ""
  echo "==> 尚未完成 GitHub 认证。请把下面这段公钥添加到 GitHub:"
  echo "    GitHub -> Settings -> SSH and GPG keys -> New SSH key"
  echo "------------------------------------------------------------"
  cat "$KEY.pub"
  echo "------------------------------------------------------------"
  echo "添加完成后, 重新运行本脚本:  bash tools/setup_instabox_dev.sh"
  exit 0
fi

# ---------- 3. clone 或更新仓库 ----------
if [ -d "$REPO_DIR/.git" ]; then
  echo "==> 仓库已存在, 执行 pull"
  git -C "$REPO_DIR" pull --ff-only
else
  echo "==> clone 仓库到 $REPO_DIR"
  git clone "$REPO_SSH" "$REPO_DIR"
fi

# ---------- 4. 安装 Godot 开发环境 ----------
echo "==> 安装 Godot 开发环境 (Debian 13)"
bash "$REPO_DIR/tools/setup_instabox.sh"

# ---------- 5. 完成 ----------
echo ""
echo "=============================================="
echo " 初始化完成!"
echo " 进 Web 桌面运行编辑器:"
echo "   cd $REPO_DIR && godot --rendering-driver opengl3"
echo " Headless 构建/测试:"
echo "   godot --headless --build"
echo "=============================================="
