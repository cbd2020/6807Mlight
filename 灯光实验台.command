#!/bin/bash
# 灯光实验台：直接对状态灯固件发命令，当场看效果。退出自动恢复 MLight。
# 已确认可用：GREEN / YELLOW / RED 配 ON / BLINK / BREATH / OFF，以及 OFF。
# 组合用 + 连接（如 RED_ON+YELLOW_BREATH）。未知颜色自己试：ORANGE、CYAN、BLUE、PURPLE……
PORT=$(ls /dev/cu.usbmodem* 2>/dev/null | head -1)
[ -z "$PORT" ] && { echo "没找到状态灯设备"; exit 1; }
echo "设备: $PORT —— 先暂停 MLight，退出时自动恢复"
launchctl bootout gui/$(id -u)/local.mlight.6807.autostart 2>/dev/null; sleep 3
python3 - "$PORT" <<'PYEOF'
import os, termios, time, sys
port = sys.argv[1]
fd = os.open(port, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
attrs = termios.tcgetattr(fd)
attrs[4] = termios.B115200; attrs[5] = termios.B115200
termios.tcsetattr(fd, termios.TCSANOW, attrs)
time.sleep(1.5)
print("直接输入命令回车发送，比如 GREEN_BREATH / RED_ON+YELLOW_BLINK / OFF")
print("输入 q 退出\n")
while True:
    cmd = input("灯> ").strip()
    if cmd in ("q", "quit", "exit", ""): break
    os.write(fd, (cmd + "\n").encode()); termios.tcdrain(fd)
    time.sleep(0.2)
os.write(fd, b"OFF\n"); termios.tcdrain(fd)
os.close(fd)
PYEOF
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/local.mlight.6807.autostart.plist 2>/dev/null || { sleep 4; launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/local.mlight.6807.autostart.plist; }
echo "MLight 已恢复"
