# AGENTS.md — 6807Mlight · AI 助手操作手册

> 本文件写给目标电脑上的 AI 助手（Claude Code / DSH / 其他 Agent）。人类用户请看 `README.md`。你的任务通常是：**安装/修复/诊断这套「6807AI状态灯MLight ↔ DSH/Claude Code」桥接**，或维护状态灯的七色固件。按下面做，不要自由发挥。

## 一、这套东西是什么（30 秒版）

6807AI状态灯MLight（下称 MLight，装在 `/Applications/6807AI状态灯MLight.app`，服务端口 6807）按「智能体」点亮 USB 灯。它对 ChatGPT（Codex）的识别是原厂自带；对 **DeepSeek Harness（DSH）和 Claude Code** 的识别有硬性前提（详见调试笔记），本工具包用三个手段补齐：

1. **骨架守护（隐私版 v1.8）**：`/Applications/灯光桥接.app/Contents/MacOS/dsh-bridge` 每 2 秒检查 `~/.dsh/sessions/**/session.v*.jsonl.zstd` 变动；在**内存中**解压解析（node 的 `zlib.zstdDecompressSync`，路径写在守护脚本 `NODE=` 里），只向 `~/.mlight-dsh-mirror` 追加「无内容骨架事件」：`turn/start`、`turn/end`（带真实 seq/turn 编号）、`ask_user_question` 的 `tool/call` 与对应 `tool/result`（带 callId）。**镜像里没有任何用户内容**——这是设计红线，改代码时不得把 content/text/path 等字段写进镜像。
   Claude 侧：同时监看 `~/.claude/projects/**/*.jsonl`，内存解析后把 user/assistant 骨架（内容全部替换为「.」，保留 timestamp/permissionMode/stop_reason）写进 `~/.mlight-claude-mirror/<项目>/<会话>/session.v1.jsonl`。**MLight 的 ClaudeMonitor 只认 `session.v*.jsonl` 文件名**（v1.7 及更早用 `<uuid>.jsonl` 原名，灯从未识别到 Claude，这是 v1.8 修复的关键坑）。增量靠 `~/.mlight-claude-mirror/.state.json` 记录每个文件已处理行数；守护每轮自动清理：旧命名镜像、14 天以上的过期骨架、空目录。
2. **环境变量**（写在 MLight 的 launchd plist `~/Library/LaunchAgents/local.mlight.6807.autostart.plist` 的 `EnvironmentVariables` 里，共 5 个）：
   - `MLIGHT_TEST_CONNECTED_APPS=DeepSeek Harness,Claude Code` —— MLight 官方的无头模式后门：把这些名字并入「已连接智能体」判定集合（与真实运行中的 App 名取并集）。这是 DSH/Claude 显示「连接正常」的唯一非 App 途径。
   - `MLIGHT_DSH_SESSIONS=~/.mlight-dsh-mirror` —— DSH 会话目录改读镜像。
   - `MLIGHT_DSH_SINCE=<安装时刻毫秒值>` —— 会话文件时间过滤基准，早于它的旧会话一律忽略。
   - `MLIGHT_CLAUDE_PROJECTS_ROOT=~/.mlight-claude-mirror` —— Claude 会话改读骨架镜像（真实 `~/.claude/projects` 不再被 MLight 接触）。骨架行形状：`{"type":"user","timestamp":T,"permissionMode":M,"message":{"role":"user","content":"."}}` 与 `{"type":"assistant","timestamp":T,"message":{"role":"assistant","content":[{"type":"text","text":"."}],"stop_reason":R,"stop_sequence":S}}`。运行判定=最后 user 之后无 end_turn；**timestamp 字段必须有**（缺了 MLight 不认）。
   - `MLIGHT_CLAUDE_NET_BYTES=<假数据文件绝对路径>`（内容恒为「0 0」）——绕过 MLight 每轮 30 秒的 nettop 本机流量统计读取。⚠️ 此变量的值必须是**存在且可读的文件路径**；若指向不存在的文件，MLight 整个监控循环会异常（所有智能体变「未检测」）。文件由守护自愈维持。
3. **常驻方式（v1.4 起）**：launchd 代理 `local.mlight.dsh-bridge`（配置 `~/Library/LaunchAgents/local.mlight.dsh-bridge.plist`，KeepAlive+RunAtLoad，launchd 输出在 `~/Library/Logs/灯光桥接/launchd.log`）。守护崩溃/被杀会自动拉起，登录自启。v1.3 的「登录项」方式已废弃，安装器升级时会顺手清掉。

## 二、标准操作命令

安装/修复（幂等，可无限重跑）：

```bash
cd /path/to/6807Mlight && bash 安装.command
```

> 安装器 v1.4.1 起自动处理原厂包：本机没装 MLight 时，自动挂载仓库 `原厂原始包/` 里的 dmg 并弹出**官方 GUI 安装器**（厂商向导无法静默，「开始安装」必须人工点；Gatekeeper 拦截时在「系统设置 → 隐私与安全性」点「仍要打开」），装完自动继续；MLight 缺开机配置（`~/Library/LaunchAgents/local.mlight.6807.autostart.plist`）时自动启动一次 MLight 补生成后再写入环境变量。

体检：

```bash
bash 自检.command
```

只重启桥接守护（改完守护脚本后用；注意 KeepAlive 下直接杀进程也会被 launchd 自动拉起，所以换代码必须先 bootout）：

```bash
launchctl bootout gui/$(id -u)/local.mlight.dsh-bridge
# 改完 /Applications/灯光桥接.app/Contents/MacOS/dsh-bridge 后：
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/local.mlight.dsh-bridge.plist
```

只重启 MLight 服务（改完 plist 必须这样，**`launchctl kickstart -k` 不会重新读 plist**，这是本方案最大的坑）：

```bash
launchctl bootout gui/$(id -u)/local.mlight.6807.autostart
sleep 4
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/local.mlight.6807.autostart.plist
```

看 MLight 的判定原文（哪个智能体连没连、在不在跑）：

```bash
curl -s http://127.0.0.1:6807/api/status | python3 -m json.tool
# 证据在 evidence 数组：agent.<key>.connected / .running / .attention
# 人类可读版：curl -s http://127.0.0.1:6807/ai
```

直接对灯发命令试色（绕过 MLight，退出自动恢复）：

```bash
bash 灯光实验台.command
```

## 三、故障对照表

| 症状 | 根因 | 修复 |
|---|---|---|
| DSH/Claude 显示「未运行」 | plist 里 5 个环境变量丢了（典型：升级 MLight 被其安装器重写） | 重跑 `安装.command`，或手工把 `EnvironmentVariables` 合并回去后按上面方式重启服务 |
| DSH 显示「会话读取失败」 | MLight 在解压 zstd（说明 `MLIGHT_DSH_SESSIONS` 没生效，它在读原始目录） | 确认变量在进程里：`ps eww <MLight的PID> \| tr ' ' '\n' \| grep MLIGHT_DSH_SESSIONS`；没有就 bootout+bootstrap |
| 镜像不更新 | 守护死了或 node 路径失效（nvm 换版本） | `launchctl print gui/$(id -u)/local.mlight.dsh-bridge`；看 `~/Library/Logs/灯光桥接/mirror.log` 与 `launchd.log`；重跑 `安装.command` 刷新 node 路径 |
| 守护反复重启/起不来 | 守护脚本语法错或 launchd 配置坏 | `launchd.log` 看报错；`bash -n 守护脚本` 验语法；重跑 `安装.command` |
| Claude 灯不亮（v1.7 及以前的老版本） | 镜像文件名不是 `session.v*.jsonl`，MLight 的 ClaudeMonitor 不认 | 升级到 v1.8 守护（重跑 `安装.command`），它会自动清理旧命名镜像 |
| 守护在跑但状态永远不变/灯卡色 | 守护内的 find/date 命令在该系统上方言不兼容（如 GNU 的 `-newermt @epoch`，macOS 不认）且报错被吞 | 看守护脚本里有无 `2>/dev/null` 吞错；手动跑一遍里面的 find 验证；已改为时间戳文件+扫描前预盖 |
| 出现 nettop 子进程 / 灯响应又变慢（10-30秒） | `MLIGHT_CLAUDE_NET_BYTES` 丢失或假数据文件被删 | `自检.command` 定位；重跑 `安装.command`；确认环境变量指向 `~/.mlight-dsh-mirror/.claude-net-bytes` |
| 所有智能体变「未检测」 | 假数据文件路径失效（读文件抛错拖死监控循环） | 重建文件（守护会自愈）或重跑 `安装.command` |
| 黄灯不亮但 DSH 在干活 | 原厂增量设计：只统计「监视开始后新开且未结束的回合」 | 正常现象。发条新消息（新回合）即亮 |
| 环境变量改了不生效 | 用了 `kickstart -k` | 必须 bootout + bootstrap（kickstart 不重读 plist） |
| 装完 MLight 起不来 | plist 被改坏（曾发生过用 plutil 重定向把 plist 写成裸 JSON） | 用 python `plistlib` 重建，字段见调试笔记第 5 节 |
| 灯只亮红黄绿三色 | 固件是原厂三色版 | 刷 `固件源码/七色固件v1.uf2`（按住 BOOT 插 USB 拖入），刷完用 `灯光实验台.command` 验证 |

## 四、验证清单（按序执行，全绿才算好）

1. `launchctl print gui/$(id -u)/local.mlight.dsh-bridge` 能打印，且 `pgrep -f dsh-bridge` 有进程。
2. 给 DSH 发一条消息让它干活，2 秒内 `~/.mlight-dsh-mirror` 里出现/更新对应 `session.vN.jsonl`。
3. MLight 进程环境里有全部 5 个 `MLIGHT_*` 变量（注意 `ps eww` 显示含空格的变量值会被截断，是显示问题不是真丢了；确认存在即可）。
4. `~/.mlight-claude-mirror` 里骨架文件名是 `<项目>/<会话>/session.v1.jsonl`（不是裸 `<uuid>.jsonl`）。
5. `/api/status` 里 `agent.deepseek.connected=yes`、`agent.claude.connected=yes`，且 detail 不是「未运行/读取失败」。
6. DSH 新回合期间 `decision.logicalCommand` 含 `YELLOW_BREATH`。

## 五、不要做的事

- 不要改 MLight 应用包内的任何文件（有代码签名，改了整个应用打不开）。
- 不要给 MLight 的 plist 里塞其他 `MLIGHT_TEST_*` 变量（`MLIGHT_TEST_HTTP_PORT` 等会进「测试模式」，行为不同）。
- 不要用 `plutil -o` 这类输出重定向碰 plist（曾把 plist 写坏）；改 plist 一律用 python `plistlib` 读改写。
- 不要把守护的 node 换成 `zstd` 命令依赖（MLight 的 zstd 回退路径 `/opt/homebrew/bin/zstd` 等都需要管理员权限创建，且 vendor 逻辑不受我们控制）。
- 不要把用户内容写进镜像目录（设计红线，见第一节）。
- 固件改动先在 `灯光实验台.command` 里逐条验证，再提交；uf2 是编译产物，改代码后要重新编译替换。

## 六、MLight 内部机制速查（逆向 1.2.1 build 27 所得，详细证据见调试笔记）

- 判定循环 `Model.refreshApps()`：集合 = 运行中 App 的 `localizedName`（小写）∪ `MLIGHT_TEST_CONNECTED_APPS`（逗号分隔、小写）；智能体的候选名单：DSH=`["DeepSeek Harness"]`，Claude=`["Claude","Claude Code"]`，ChatGPT/Codex=ChatGPT.app 名。命中才轮询其 Monitor。
- `DeepSeekMonitor`：目录 `~/.dsh/sessions`（`MLIGHT_DSH_SESSIONS`/`DSH_HOME` 可覆盖），只认文件名 `session.v数字.jsonl`（可带 `.zstd`）；文件按修改时间过滤（`MLIGHT_DSH_SINCE`，毫秒）；`.zstd` 要用它找到的 node 跑内嵌 JS 解压——找不到 node 且系统无 zstd 命令就抛「会话读取失败」。
- 事件语义：`turn/start`（回合开始，字段 `turn`）→ `turn/end`（结束）；`tool/call` 的 `name` 是 `ask_user_question` 类 → 计入待确认，`tool/result` 回来 → 解除。**每个文件有 seq 游标，首次见到只初始化游标不回溯历史**。
- `ClaudeMonitor`：桌面版看 `~/Library/Logs/Claude/*.log` 网络流量；命令行版（`codeActivity`）扫 `~/.claude/projects/**/*.jsonl`（`MLIGHT_CLAUDE_PROJECTS_ROOT` 可覆盖），**只认 `session.v数字.jsonl` 文件名**。
- 灯优先级：红（待确认）> 黄（运行）> 绿（空闲/连接）。`AgentActivity` 没有 connected 字段，前端把 running/attention 双否显示为「连接正常」。

## 七、状态灯固件（固件源码/）

- 硬件：Waveshare RP2040 Zero + 3×WS2812B 串联，GPIO28（经 330Ω）→ DIN，GRB 800kHz；串口 115200 8N1，一行一命令，大小写不敏感，不回包，未知命令丢弃。
- 兼容原厂命令全集：`RED/YELLOW/GREEN × ON/BREATH/BLINK/OFF`、`BRIGHTNESS_n`、上电默认绿色 30% 亮度；新增 `CYAN/BLUE/PURPLE/WHITE × ON/BREATH/BLINK/OFF`（七色）。
- `seven7.ino` 是源码；`七色固件v1.uf2` 是编译产物（刷写：按住 BOOT 插 USB，把 uf2 拖进出现的 `RPI-RP2` 盘）。
- 验证工具：`bash 灯光实验台.command`（会先暂停 MLight 服务，退出自动恢复）。
