uniform float uTime;
uniform vec2 uResolution;
uniform vec2 uPointer;
uniform float uScale;
uniform float uSpeed;
uniform float uWarp;
uniform vec3 uTint;

varying vec2 vUv;

void main() {
  vec2 uv = vUv;
  vec2 centered = (uv - 0.5) * vec2(uResolution.x / max(uResolution.y, 1.0), 1.0);

  float wave = sin((centered.x + sin(centered.y * 2.0 + uTime * uSpeed) * uWarp) * uScale + uTime * uSpeed);
  float band = 0.5 + 0.5 * wave;
  float pointerGlow = exp(-8.0 * distance(uv, uPointer));

  vec3 base = vec3(uv.x, uv.y, band);
  vec3 color = mix(base, uTint, 0.28 + pointerGlow * 0.22);
  color += 0.08 * cos(uTime + vec3(0.0, 2.0, 4.0));

  gl_FragColor = vec4(color, 1.0);
}

/* @shaderlab
{
  "version": 1,
  "parameters": {
    "uScale": {
      "type": "float",
      "default": 8.0,
      "min": 1.0,
      "max": 24.0,
      "step": 0.1,
      "label": { "zh": "波形频率", "en": "Wave Frequency" },
      "description": { "zh": "控制横向波形的空间频率。", "en": "Controls the spatial frequency of the horizontal wave." },
      "group": { "zh": "图案", "en": "Pattern" }
    },
    "uSpeed": {
      "type": "float",
      "default": 0.8,
      "min": 0.0,
      "max": 4.0,
      "step": 0.01,
      "label": { "zh": "动画速度", "en": "Animation Speed" },
      "description": { "zh": "控制时间驱动的相位变化速度。", "en": "Controls the time-driven phase animation speed." },
      "group": { "zh": "动画", "en": "Animation" }
    },
    "uWarp": {
      "type": "float",
      "default": 0.35,
      "min": 0.0,
      "max": 1.5,
      "step": 0.01,
      "label": { "zh": "扭曲强度", "en": "Warp Amount" },
      "description": { "zh": "沿 Y 方向对波形进行相位扭曲。", "en": "Adds phase warping along the Y axis." },
      "group": { "zh": "图案", "en": "Pattern" }
    },
    "uTint": {
      "type": "color",
      "default": "#78a9ff",
      "label": { "zh": "强调色", "en": "Accent Tint" },
      "description": { "zh": "与基础 UV 颜色混合的强调色。", "en": "Accent color mixed into the base UV gradient." },
      "group": { "zh": "外观", "en": "Appearance" }
    }
  }
}
@endshaderlab */
