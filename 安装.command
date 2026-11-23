#!/bin/bash
# ============================================================
# 灯光桥接 · 安装器  v1.4.1（隐私版 · launchd 常驻 · 可自动装原厂包）
# 作用：让 6807AI状态灯MLight 识别 DeepSeek Harness（DSH，命令行/Web版）
#       与 Claude Code 终端版的运行状态。
# 隐私原则：DSH/Claude 原文件只读；解压解析全部在内存完成；给状态灯
#           的镜像里只有「无内容骨架事件」（回合开始/结束、提问/应答
#           标记），不含任何用户文本、路径、命令、输出。
# 适用：macOS 13+，已安装 6807AI状态灯MLight 1.2.1，已安装 node（带 zstd 支持）
# 用法：双击本文件（或在终端里 bash 安装.command）
# v1.4（2026-11-23）相对 v1.3 的变化：
#   1) 守护升级 v1.8：Claude 镜像改为 <项目>/<会话>/session.v1.jsonl
#      （MLight 的 ClaudeMonitor 只认 session.v*.jsonl 文件名，v1.7 的
#      <uuid>.jsonl 原名灯从未识别过）；并自动清理旧命名镜像、14 天以上
#      过期骨架与空目录。
#   2) 常驻方式从「App + 登录项」改为 launchd 代理 local.mlight.dsh-bridge
#      （KeepAlive：崩溃/退出自动拉起，登录自启）。
#   3) 守护脚本不再内嵌在本安装器里，改由「桥接守护/」目录提供模板，
#      安装时只替换 node 路径占位符（改守护不再需要改安装器）。
# v1.4.1（2026-11-23）：
#   4) 收编原厂原始包（原厂原始包/：dmg + 官方安装说明 + 厂商 zip 原件）。
#      本机没装 MLight 时自动挂载仓库里的原厂 dmg 并弹出官方安装器
#      （厂商是 GUI 向导且有 Gatekeeper 校验，「开始安装」必须人工点），
#      装完自动继续；MLight 缺开机配置时自动启动一次补生成。
# ============================================================
set -u
cd "$(dirname "$0")"
APP_NAME="灯光桥接"
APP="/Applications/$APP_NAME.app"
PLIST="$HOME/Library/LaunchAgents/local.mlight.6807.autostart.plist"
LABEL="local.mlight.dsh-bridge"
BPLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
MLIGHT_APP="/Applications/6807AI状态灯MLight.app"
MLIGHT_LAUNCHER="/Applications/6807AI状态灯MLight启动.app"
MLIGHT_PLIST="$HOME/Library/LaunchAgents/local.mlight.6807.autostart.plist"

say(){ printf "\033[1;36m[安装]\033[0m %s\n" "$*"; }
err(){ printf "\033[1;31m[错误]\033[0m %s\n" "$*"; }
ok(){  printf "\033[1;32m[通过]\033[0m %s\n" "$*"; }

# ---------- 0. 前置检查 ----------
say "第0步 前置检查"

if [ ! -f "桥接守护/dsh-bridge" ] || [ ! -f "桥接守护/$LABEL.plist" ]; then
  err "缺「桥接守护」目录（dsh-bridge 与 launchd 配置模板）。请完整拷贝/克隆整个仓库后再安装。"
  exit 1
fi
if [ ! -d "$MLIGHT_APP" ]; then
  DMG="$(ls 原厂原始包/*/6807AI状态灯MLight-macOS-1.2.1.dmg 2>/dev/null | head -1)"
  if [ -z "$DMG" ]; then
    err "没有找到 $MLIGHT_APP，仓库里也没有原厂安装镜像（原厂原始包/）。请先按厂商说明安装 6807AI状态灯MLight 1.2.1。"
    exit 1
  fi
  say "本机没装 MLight，自动挂载仓库原厂镜像并启动官方安装器…"
  MNT="$(hdiutil attach "$DMG" -nobrowse -readonly | tail -1 | cut -f3)"
  if [ -z "$MNT" ] || [ ! -d "$MNT" ]; then err "原厂镜像挂载失败：$DMG"; exit 1; fi
  INSTALLER_APP="$(find "$MNT" -maxdepth 2 -name "安装*.app" | head -1)"
  [ -z "$INSTALLER_APP" ] && INSTALLER_APP="$(find "$MNT" -maxdepth 2 -name "*.app" | head -1)"
  [ -z "$INSTALLER_APP" ] && { hdiutil detach "$MNT" -quiet 2>/dev/null; err "镜像里没找到官方安装器"; exit 1; }
  open "$INSTALLER_APP"
  say "官方安装窗口已弹出。若系统提示「无法验证打开者」：系统设置 → 隐私与安全性 → 点「仍要打开」；然后在窗口里点「开始安装」。装好后这里自动继续（最多等 5 分钟）…"
  WAITED=0
  while [ ! -d "$MLIGHT_APP" ] && [ "$WAITED" -lt 300 ]; do sleep 5; WAITED=$((WAITED+5)); done
  hdiutil detach "$MNT" -quiet 2>/dev/null
  [ -d "$MLIGHT_APP" ] || { err "等了 5 分钟仍未检测到 MLight 装好。手动完成官方安装器后重跑本安装器。"; exit 1; }
fi
ok "状态灯 MLight 已安装"

NODE_BIN="$(command -v node 2>/dev/null || true)"
if [ -z "$NODE_BIN" ]; then
  NODE_BIN="$(ls -t "$HOME"/.nvm/versions/node/*/bin/node 2>/dev/null | head -1 || true)"
fi
if [ -z "$NODE_BIN" ] || [ ! -x "$NODE_BIN" ]; then
  err "没有找到 node。请先安装 node（推荐 v24+），或设置好 PATH 后重试。"
  exit 1
fi
if ! "$NODE_BIN" -e 'require("zlib").zstdDecompressSync' 2>/dev/null; then
  err "当前 node（$NODE_BIN）不支持 zlib.zstdDecompressSync（需要 node v24 及以上）。请升级 node 后重试。"
  exit 1
fi
ok "node 可用：$NODE_BIN"

# ---------- 1. 生成灯光桥接.app（会话骨架守护 v1.8） ----------
say "第1步 生成 $APP_NAME.app（会话骨架守护 v1.8，隐私版）"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
# v1.3 老版本走的是「登录项」，升级时顺手清掉
osascript -e "tell application \"System Events\" to delete login item \"$APP_NAME\"" >/dev/null 2>&1
pkill -f "$APP/Contents/MacOS" 2>/dev/null
sleep 1
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$HOME/Library/Logs/灯光桥接"

cat > "$APP/Contents/Info.plist" <<'PLISTEOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>灯光桥接</string>
  <key>CFBundleDisplayName</key><string>灯光桥接</string>
  <key>CFBundleIdentifier</key><string>local.dsh.mlight-bridge</string>
  <key>CFBundleExecutable</key><string>dsh-bridge</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.4</string>
  <key>LSBackgroundOnly</key><true/>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLISTEOF

cp "桥接守护/dsh-bridge" "$APP/Contents/MacOS/dsh-bridge"
sed -i '' "s|__NODE_PATH__|$NODE_BIN|g" "$APP/Contents/MacOS/dsh-bridge"
chmod +x "$APP/Contents/MacOS/dsh-bridge"
plutil -lint "$APP/Contents/Info.plist" >/dev/null || { err "Info.plist 生成失败"; exit 1; }
ok "App 已生成（隐私版守护 v1.8，node 路径：$NODE_BIN）"

# ---------- 2. 安装 launchd 常驻代理 ----------
say "第2步 安装 launchd 常驻代理 $LABEL"
sed "s|__HOME__|$HOME|g" "桥接守护/$LABEL.plist" > "$BPLIST"
plutil -lint "$BPLIST" >/dev/null || { err "launchd 配置生成失败：$BPLIST"; exit 1; }
launchctl bootstrap "gui/$(id -u)" "$BPLIST" 2>/dev/null || { sleep 3; launchctl bootstrap "gui/$(id -u)" "$BPLIST"; }
sleep 2
if ! pgrep -f "$APP/Contents/MacOS/dsh-bridge" >/dev/null; then
  err "守护进程没能启动，请查看 $HOME/Library/Logs/灯光桥接/launchd.log 与 mirror.log"
  exit 1
fi
ok "守护已由 launchd 拉起（崩溃/退出会自动重启，登录自启）"

# ---------- 3. 给 MLight 的启动配置注入环境变量 ----------
say "第3步 配置 MLight 环境变量"
if [ ! -f "$MLIGHT_PLIST" ]; then
  say "MLight 还没生成开机启动配置，自动启动一次 MLight 补生成…"
  if [ -d "$MLIGHT_LAUNCHER" ]; then open "$MLIGHT_LAUNCHER"; else open "$MLIGHT_APP"; fi
  WAITED=0
  while [ ! -f "$MLIGHT_PLIST" ] && [ "$WAITED" -lt 120 ]; do sleep 3; WAITED=$((WAITED+3)); done
  osascript -e 'quit app "6807AI状态灯MLight"' >/dev/null 2>&1
  sleep 2
fi
if [ ! -f "$MLIGHT_PLIST" ]; then
  err "没找到 MLight 的启动配置 $MLIGHT_PLIST —— 请先启动一次 6807AI状态灯MLight（它会自动注册）再重跑本安装器。"
  exit 1
fi
PLIST="$MLIGHT_PLIST"
SINCE_MS="$(date +%s)000"
python3 - "$PLIST" "$SINCE_MS" <<'PYEOF'
import plistlib, sys, subprocess
p, since = sys.argv[1], sys.argv[2]
with open(p, "rb") as f:
    d = plistlib.load(f)
env = d.setdefault("EnvironmentVariables", {})
env["MLIGHT_TEST_CONNECTED_APPS"] = "DeepSeek Harness,Claude Code"
user = subprocess.run(["id","-un"],capture_output=True,text=True).stdout.strip()
env["MLIGHT_DSH_SESSIONS"] = "/Users/__USER__/.mlight-dsh-mirror".replace("__USER__", user)
env["MLIGHT_CLAUDE_NET_BYTES"] = "/Users/__USER__/.mlight-dsh-mirror/.claude-net-bytes".replace("__USER__", user)
env["MLIGHT_CLAUDE_PROJECTS_ROOT"] = "/Users/__USER__/.mlight-claude-mirror".replace("__USER__", user)
env["MLIGHT_DSH_SINCE"] = since
with open(p, "wb") as f:
    plistlib.dump(d, f)
print("    已写入:", env)
PYEOF
plutil -lint "$PLIST" >/dev/null || { err "plist 校验失败，中止"; exit 1; }
ok "环境变量已写入（时间基准 $SINCE_MS）"

# ---------- 4. 重启 MLight 服务（必须 bootout+bootstrap，kickstart 不重读配置！） ----------
say "第4步 重启 MLight 服务加载新配置"
mkdir -p "$HOME/.mlight-dsh-mirror" "$HOME/.mlight-claude-mirror"; printf '0 0\n' > "$HOME/.mlight-dsh-mirror/.claude-net-bytes"
launchctl bootout gui/$(id -u)/local.mlight.6807.autostart 2>/dev/null; sleep 4
launchctl bootstrap gui/$(id -u) "$PLIST" 2>/dev/null || { sleep 4; launchctl bootstrap gui/$(id -u) "$PLIST"; }
sleep 5

# ---------- 5. 验证 ----------
say "第5步 验证"
pgrep -f "$APP/Contents/MacOS/dsh-bridge" >/dev/null && ok "灯光桥接守护运行中" || err "守护不在跑（launchd 会自动再拉，稍后用自检.command 确认）"
MP=""
for i in $(seq 1 10); do
  MP=$(lsof -ti :6807 -sTCP:LISTEN 2>/dev/null | head -1)
  [ -n "$MP" ] && break
  sleep 2
done
if [ -z "$MP" ]; then
  err "MLight 没有在 6807 端口起来。可打开 /Applications/6807AI状态灯MLight启动.app 看看报错，或重跑本安装器。"
  exit 1
fi
ok "MLight 运行中（PID $MP）"
ENVOK=$(ps eww "$MP" | tr ' ' '\n' | grep -c "MLIGHT_DSH_SESSIONS" || true)
[ "$ENVOK" -ge 1 ] && ok "环境变量已生效" || err "环境变量未生效！请手动执行：launchctl bootout gui/$(id -u)/local.mlight.6807.autostart && sleep 4 && launchctl bootstrap gui/$(id -u) $PLIST"

echo ""
echo "----------------------------------------------------------"
echo " 安装完成（隐私版：状态灯只能读到无内容骨架事件）。"
echo " 等 1~2 分钟（MLight 刷新周期较长），然后："
echo "   浏览器打开 http://127.0.0.1:6807/  看三个勾选项的状态；"
echo "   或跑工具包里的「自检.command」。"
echo " 注意：DSH 要等「下一条新消息/新回合」才会亮黄灯。"
echo "----------------------------------------------------------"
