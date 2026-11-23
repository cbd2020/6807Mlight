#!/bin/bash
# 灯光桥接 · 自检 v1.4：逐项检查链路，哪项 ✗ 就按提示处理
set -u
APP_NAME="灯光桥接"
LABEL="local.mlight.dsh-bridge"
say(){ printf "%s\n" "$*"; }
ok(){ printf "  ✅ %s\n" "$*"; }
bad(){ printf "  ❌ %s\n" "$*"; }

say "== 1. 灯光桥接守护进程（launchd 常驻）=="
if launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then
  ok "launchd 代理已加载（$LABEL）"
else
  bad "launchd 代理未加载 → 重跑 安装.command，或手动：launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/$LABEL.plist"
fi
if pgrep -f "$APP_NAME.app/Contents/MacOS/dsh-bridge" >/dev/null; then
  ok "运行中（PID $(pgrep -f "$APP_NAME.app/Contents/MacOS/dsh-bridge" | head -1)）"
else
  bad "守护进程不在跑 → 看 ~/Library/Logs/灯光桥接/launchd.log，重跑 安装.command"
fi

say "== 2. node 与镜像 =="
NODE_BIN=$(grep -m1 '^NODE=' "/Applications/$APP_NAME.app/Contents/MacOS/dsh-bridge" 2>/dev/null | cut -d'=' -f2)
if [ -n "$NODE_BIN" ] && [ -x "$NODE_BIN" ] && "$NODE_BIN" -e 'require("zlib").zstdDecompressSync' 2>/dev/null; then
  ok "node 正常：$NODE_BIN"
else
  bad "node 不可用或版本太旧（$NODE_BIN）→ 升级 node 后重跑 安装.command"
fi
SRC_NEW=$(find "$HOME/.dsh/sessions" -name "session.v*.jsonl.zstd" -mmin -2 2>/dev/null | head -1)
if [ -n "$SRC_NEW" ]; then
  rel="${SRC_NEW#$HOME/.dsh/sessions/}"
  mir="$HOME/.mlight-dsh-mirror/${rel%.zstd}"
  if [ -f "$mir" ]; then
    ok "镜像跟得上：${rel%.zstd}"
  else
    bad "镜像缺失：$rel → 看 ~/Library/Logs/灯光桥接/mirror.log"
  fi
else
  ok "（最近2分钟没有 DSH 会话写入，跳过镜像对比）"
fi

say "== 2.5 网络统计隔离（nettop 必须为0） =="
NB="$HOME/.mlight-dsh-mirror/.claude-net-bytes"
[ -f "$NB" ] && [ "$(cat "$NB")" = "0 0" ] && ok "假数据文件正常（MLight 不会去读本机流量统计）" || bad "缺 $NB → 重跑 安装.command"
MP0=$(lsof -ti :6807 -sTCP:LISTEN 2>/dev/null | head -1)
if [ -n "$MP0" ]; then
  NT=$(ps -axo ppid,command | awk -v p=$MP0 '$1==p' | grep -c nettop)
  [ "$NT" = "0" ] && ok "nettop 零运行" || bad "发现 nettop 子进程！检查环境变量 MLIGHT_CLAUDE_NET_BYTES 是否指向 $NB"
fi

say "== 2.6 Claude 骨架镜像（session.v1.jsonl 命名）=="
CM="$HOME/.mlight-claude-mirror"
if [ -d "$CM" ]; then
  NV=$(find "$CM" -name "session.v1.jsonl" 2>/dev/null | wc -l | tr -d ' ')
  [ "${NV:-0}" -ge 1 ] && ok "骨架镜像 $NV 个（<项目>/<会话>/session.v1.jsonl）" || ok "镜像目录存在（暂无骨架，Claude 跑一轮后自动生成）"
else
  bad "缺 $CM → 重跑 安装.command"
fi
MPX=$(lsof -ti :6807 -sTCP:LISTEN 2>/dev/null | head -1)
if [ -n "$MPX" ]; then
  C=$(ps eww "$MPX" | tr ' ' '\n' | grep -c "MLIGHT_CLAUDE_PROJECTS_ROOT" || true)
  [ "${C:-0}" -ge 1 ] && ok "Claude 已指向骨架镜像（真实会话不再被读）" || bad "缺 MLIGHT_CLAUDE_PROJECTS_ROOT → MLight 还在读 ~/.claude/projects 真文件！重跑 安装.command"
fi

say "== 3. MLight 服务与环境变量 =="
MP=$(lsof -ti :6807 -sTCP:LISTEN 2>/dev/null | head -1)
if [ -n "$MP" ]; then ok "MLight 运行中（PID $MP）"; else bad "6807 端口无服务 → 打开 6807AI状态灯MLight启动.app"; fi
if [ -n "$MP" ]; then
  N=$(ps eww "$MP" | tr ' ' '\n' | grep -c "MLIGHT_DSH_SESSIONS" || true)
N2=$(ps eww "$MP" | tr ' ' '\n' | grep -c "MLIGHT_CLAUDE_NET_BYTES" || true)
[ "${N2:-0}" -ge 1 ] || bad "缺少 MLIGHT_CLAUDE_NET_BYTES → nettop 隔离未生效，重跑 安装.command"
  [ "${N:-0}" -ge 1 ] && ok "环境变量已加载" || bad "环境变量未加载 → 终端执行：launchctl bootout gui/$(id -u)/local.mlight.6807.autostart; sleep 4; launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/local.mlight.6807.autostart.plist（注意 kickstart -k 无效）"
fi

say "== 4. MLight 眼中的三个智能体 =="
curl -s -m 4 http://127.0.0.1:6807/api/status 2>/dev/null | python3 -c "
import json,sys
try: d=json.load(sys.stdin)
except Exception: print('  ❌ /api/status 读不到'); sys.exit()
for key,name in [('codex','ChatGPT'),('claude','Claude'),('deepseek','DeepSeek Harness')]:
    e=[x for x in d['evidence'] if x['key']=='agent.%s.connected'%key]
    print(('  ✅ ' if e and e[0]['state']=='yes' else '  ❌ ')+name+('：'+e[0].get('detail','') if e else '：无数据')))
print('  当前灯光指令:', d['decision']['logicalCommand'])
" || bad "接口无响应"

say "提示：DSH 黄灯只在「新回合开始后」亮；Claude 状态来自骨架镜像（守护自动生成，内容全为占位符）。"
