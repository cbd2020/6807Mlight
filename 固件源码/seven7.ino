// 6807 状态灯 · 1007 七色实验固件 v1.0
// 规格：Waveshare RP2040 Zero + 3×WS2812B 串联，GPIO28(经330Ω)→DIN，GRB 800kHz
// 兼容：保留原 RED/YELLOW/GREEN 全部命令、上电绿色 30% 亮度、BRIGHTNESS_n、OFF
// 新增：CYAN/BLUE/PURPLE/WHITE 四色 × ON/BREATH/BLINK/OFF
// 串口：115200 8N1，一行一命令（\n 结尾），大小写不敏感，不回包，未知命令丢弃

#include <Adafruit_NeoPixel.h>

#define LED_PIN   28
#define N_LEDS    3
#define BLINK_MS  140     // 闪烁翻转间隔
#define BLINK_N   20      // 翻转次数，完后熄灭
#define BREATH_MS 2400    // 呼吸全周期

struct ColorDef { const char *name; uint8_t r, g, b; uint8_t gain; };
static const ColorDef COLORS[] = {
  {"RED",    255,   0,   0,  70},   // 增益 70%
  {"YELLOW", 255,  72,   0, 130},   // 增益 130%，>100 按 100
  {"GREEN",    0, 255,   0, 100},
  {"CYAN",     0, 255, 255, 100},
  {"BLUE",     0,   0, 255, 100},
  {"PURPLE", 148,   0, 255, 100},
  {"WHITE",  255, 255, 255, 100},
};
#define NCOLORS ((int)(sizeof(COLORS)/sizeof(COLORS[0])))

Adafruit_NeoPixel strip(N_LEDS, LED_PIN, NEO_GRB + NEO_KHZ800);

enum Mode { M_OFF, M_ON, M_BREATH, M_BLINK };
Mode mode = M_ON;
int active = 2;                 // 上电 = 绿色
int globalBright = 30;          // 上电 = 30%

char buf[64]; uint8_t blen = 0;

// 图案状态
uint32_t tBlink = 0; int blinkLeft = 0; bool blinkOn = false;
float breathPhase = 0; uint32_t breathLast = 0;

static int colorIndexByPrefix(const char *s, int len) {
  for (int i = 0; i < NCOLORS; i++) {
    int L = strlen(COLORS[i].name);
    if (len > L && strncasecmp(s, COLORS[i].name, L) == 0) return i;
  }
  return -1;
}

static void render(float scale) {
  const ColorDef &c = COLORS[active];
  long bright = (long)c.gain * globalBright / 100;
  if (bright > 100) bright = 100;
  uint8_t r = (uint8_t)min(255L, (long)c.r * bright * (long)(scale * 100) / 100 / 100);
  uint8_t g = (uint8_t)min(255L, (long)c.g * bright * (long)(scale * 100) / 100 / 100);
  uint8_t b = (uint8_t)min(255L, (long)c.b * bright * (long)(scale * 100) / 100 / 100);
  strip.fill(strip.Color(r, g, b));
  strip.show();
}

static void allOff() { strip.clear(); strip.show(); }

static void handleLine(char *s) {
  while (*s == ' ' || *s == '\t' || *s == '\r') s++;
  if (!*s) return;
  if (strncasecmp(s, "BRIGHTNESS_", 11) == 0) {
    int v = atoi(s + 11);
    if (v < 0) v = 0;
    if (v > 100) v = 100;
    globalBright = v;
    if (mode == M_ON) render(1.0f);
    return;
  }
  if (strcasecmp(s, "OFF") == 0) { mode = M_OFF; allOff(); return; }
  int idx = colorIndexByPrefix(s, strlen(s));
  if (idx < 0) return;                                   // 未知命令：丢弃
  const char *suffix = s + strlen(COLORS[idx].name);
  if (strcasecmp(suffix, "_ON") == 0)          { active = idx; mode = M_ON;     render(1.0f); }
  else if (strcasecmp(suffix, "_BREATH") == 0) { active = idx; mode = M_BREATH; }
  else if (strcasecmp(suffix, "_BLINK") == 0)  { active = idx; mode = M_BLINK;  blinkLeft = BLINK_N; blinkOn = true; tBlink = millis(); render(1.0f); }
  else if (strcasecmp(suffix, "_OFF") == 0)    { if (idx == active) { mode = M_OFF; allOff(); } }
}

void setup() {
  strip.begin();
  render(1.0f);                 // 上电：绿色常亮 @30%
  Serial.begin(115200);
}

void loop() {
  while (Serial.available()) {
    char ch = Serial.read();
    if (ch == '\n') { buf[blen] = 0; handleLine(buf); blen = 0; }
    else if (blen < sizeof(buf) - 1 && ch != '\r') buf[blen++] = ch;
  }
  uint32_t now = millis();
  if (mode == M_BLINK) {
    if (now - tBlink >= BLINK_MS) {
      tBlink = now;
      blinkOn = !blinkOn; blinkLeft--;
      if (blinkLeft <= 0) { mode = M_OFF; allOff(); }
      else render(blinkOn ? 1.0f : 0.0f);
    }
  } else if (mode == M_BREATH) {
    if (breathLast == 0) breathLast = now;
    if (now - breathLast >= 20) {
      float dt = (now - breathLast) / 1000.0f;
      breathLast = now;
      breathPhase += dt * 2.0f * 3.14159265f * 1000.0f / BREATH_MS;
      float s = 0.5f - 0.5f * cosf(breathPhase);
      render(powf(s, 2.2f));
    }
  }
}
