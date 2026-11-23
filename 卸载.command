#!/bin/bash
# 灯光桥接 · 卸载器 v1.4：只删本工具包装的东西，不动 6807AI状态灯MLight 本体
set -u
APP_NAME="灯光桥接"
APP="/Applications/$APP_NAME.app"
PLIST="$HOME/Library/LaunchAgents/local.mlight.6807.autostart.plist"
LABEL="local.mlight.dsh-bridge"
say(){ printf "\033[1;36m[卸载]\033[0m %s\n" "$*"; }

say "停止并移除 launchd 常驻代理"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"

say "清理 v1.3 旧版登录项与残留进程"
osascript -e "tell application \"System Events\" to delete login item \"$APP_NAME\"" >/dev/null 2>&1
pkill -f "$APP/Contents/MacOS" 2>/dev/null

say "移除 App 与两个镜像目录"
rm -rf "$APP" "$HOME/.mlight-dsh-mirror" "$HOME/.mlight-claude-mirror"

say "清理 MLight 环境变量"
if [ -f "$PLIST" ]; then
  python3 - "$PLIST" <<'PYEOF'
import plistlib, sys
p = sys.argv[1]
with open(p, "rb") as f: d = plistlib.load(f)
env = d.get("EnvironmentVariables", {})
for k in ("MLIGHT_TEST_CONNECTED_APPS", "MLIGHT_DSH_SESSIONS", "MLIGHT_DSH_SINCE",
          "MLIGHT_CLAUDE_NET_BYTES", "MLIGHT_CLAUDE_PROJECTS_ROOT"):
    env.pop(k, None)
if not env: d.pop("EnvironmentVariables", None)
with open(p, "wb") as f: plistlib.dump(d, f)
print("    已清理")
PYEOF
  launchctl bootout gui/$(id -u)/local.mlight.6807.autostart 2>/dev/null; sleep 4
  launchctl bootstrap gui/$(id -u) "$PLIST" 2>/dev/null || { sleep 4; launchctl bootstrap gui/$(id -u) "$PLIST"; }
fi
say "完成。MLight 恢复原状（DSH/Claude 会回到未识别状态，ChatGPT 不受影响）。"
