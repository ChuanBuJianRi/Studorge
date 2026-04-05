#!/usr/bin/env bash
# =============================================================
#  build_windows.sh  —  Build Studorge-Windows.zip
#  Run on macOS/Linux; the zip is then distributed to Windows users.
# =============================================================
set -e

VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DIST_DIR="$SCRIPT_DIR/dist"
ZIP_NAME="Studorge-Windows-${VERSION}.zip"
ZIP_PATH="$DIST_DIR/$ZIP_NAME"
TMP_DIR=$(mktemp -d)
PKG_DIR="$TMP_DIR/Studorge-Windows"

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║   Building Studorge Windows Package      ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# ── 1. Prepare temp directory ─────────────────────────────────
mkdir -p "$PKG_DIR"
echo "→ Package dir: $PKG_DIR"

# ── 2. Copy source code ───────────────────────────────────────
echo "→ Copying source files..."
rsync -a --exclude='__pycache__' --exclude='*.pyc' --exclude='.git' \
      --exclude='dist' --exclude='build' --exclude='data' \
      --exclude='chroma_db' --exclude='*.db' --exclude='.env' \
      "$SCRIPT_DIR/backend/"  "$PKG_DIR/backend/"

rsync -a --exclude='*.DS_Store' \
      "$SCRIPT_DIR/frontend/" "$PKG_DIR/frontend/"

cp "$SCRIPT_DIR/requirements.txt" "$PKG_DIR/"
cp "$SCRIPT_DIR/run.py"           "$PKG_DIR/"
cp "$SCRIPT_DIR/.env.example"     "$PKG_DIR/"

# ── 3. Copy Windows installer scripts ────────────────────────
echo "→ Copying installer scripts..."
cp "$SCRIPT_DIR/scripts/windows/setup.bat"     "$PKG_DIR/安装_双击我.bat"
cp "$SCRIPT_DIR/scripts/windows/installer.ps1" "$PKG_DIR/installer.ps1"

# In the zip the installer.ps1 sits at the package root (next to backend/, etc.)
# so SrcRoot is the same as ScriptDir — patch the line in the copy.
sed -i '' \
    's/\$SrcRoot   = Split-Path (Split-Path \$ScriptDir)/\$SrcRoot   = \$ScriptDir/' \
    "$PKG_DIR/installer.ps1" 2>/dev/null || \
python3 -c "
import re, sys
path = '$PKG_DIR/installer.ps1'
txt  = open(path).read()
txt  = re.sub(
    r'\\\$SrcRoot\s+=\s+Split-Path \(Split-Path \\\$ScriptDir\).*',
    '\$SrcRoot   = \$ScriptDir',
    txt)
open(path,'w').write(txt)
print('  patched SrcRoot')
"

# ── 4. Write README ───────────────────────────────────────────
echo "→ Writing README..."
cat > "$PKG_DIR/README.txt" <<'README'
╔══════════════════════════════════════════════════════════════╗
║                 Studorge AI 学习助手  v1.0                   ║
╚══════════════════════════════════════════════════════════════╝

【安装步骤】
  1. 解压此压缩包到任意文件夹（如 C:\Users\你的名字\Downloads\Studorge-Windows）
  2. 双击  "安装_双击我.bat"
  3. 按提示安装 Python 3.10+（如已安装可跳过）
  4. 等待依赖自动下载安装（需保持网络连接，约 3–5 分钟）
  5. 在弹出的配置文件中填写您的 OPENAI_API_KEY，保存关闭
  6. 安装完成后桌面将出现快捷方式，双击即可启动

【API Key 获取】
  · OpenAI:    https://platform.openai.com/api-keys
  · DeepSeek:  https://platform.deepseek.com/
  · 通义千问:  https://dashscope.aliyun.com/

  配置文件（可随时修改）：
  %APPDATA%\Studorge\app\.env

  示例内容：
    OPENAI_API_KEY=sk-xxxxxxxxxxxxxx
    OPENAI_BASE_URL=https://api.openai.com/v1
    OPENAI_MODEL=gpt-4o

【系统要求】
  · Windows 10 / 11  (64-bit)
  · Python 3.10 或更高版本
  · 网络连接（首次安装时下载依赖）

【数据存储】
  所有学习记录保存在本地：%APPDATA%\Studorge\data\
  卸载时删除此文件夹即可清除全部数据。

【常见问题】
  Q: 双击 .bat 闪一下就消失了？
  A: 右键 → "以管理员身份运行" 查看错误信息，或在 PowerShell 中运行。

  Q: 提示"无法加载脚本"？
  A: 右键 setup.bat → 以管理员身份运行；
     或在 PowerShell 中执行：
       Set-ExecutionPolicy -Scope CurrentUser RemoteSigned

  Q: 安装后打开页面报错？
  A: 检查 .env 文件中的 API Key 是否正确填写。

README

# ── 5. Create zip ─────────────────────────────────────────────
echo "→ Creating $ZIP_NAME..."
mkdir -p "$DIST_DIR"
rm -f "$ZIP_PATH"
(cd "$TMP_DIR" && zip -r "$ZIP_PATH" "Studorge-Windows" -x "*.DS_Store")

# ── 6. Cleanup ────────────────────────────────────────────────
rm -rf "$TMP_DIR"

SIZE=$(du -sh "$ZIP_PATH" | cut -f1)
echo ""
echo "══════════════════════════════════════════"
echo "✅  Build complete!"
echo "   Package: $ZIP_PATH"
echo "   Size:    $SIZE"
echo ""
echo "发给 Windows 用户的步骤："
echo "  1. 发送此 zip 文件"
echo "  2. 解压后双击 '安装_双击我.bat'"
echo "  3. 按提示填写自己的 API Key"
echo "══════════════════════════════════════════"
echo ""
