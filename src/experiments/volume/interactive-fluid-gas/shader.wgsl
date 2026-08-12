struct VertexOut {
  @builtin(position) position: vec4f,
  @location(0) uv: vec2f,
};

@vertex
fn vsMain(@builtin(vertex_index) vertexIndex: u32) -> VertexOut {
  var positions = array<vec2f, 3>(
    vec2f(-1.0, -3.0),
    vec2f(-1.0, 1.0),
    vec2f(3.0, 1.0),
  );
  let p = positions[vertexIndex];
  var out: VertexOut;
  out.position = vec4f(p, 0.0, 1.0);
  out.uv = p * 0.5 + 0.5;
  return out;
}

fn fluidIndex(x: i32, y: i32) -> u32 {
  let hi = i32(FLUID_SIZE) - 1;
  let cx = clamp(x, 0, hi);
  let cy = clamp(y, 0, hi);
  return u32(cy) * FLUID_SIZE + u32(cx);
}

fn fluidCell(x: i32, y: i32) -> vec4f {
  return fluidIn.cells[fluidIndex(x, y)];
}

fn sampleFluid(uvInput: vec2f) -> vec4f {
  let uv = clamp(uvInput, vec2f(0.0), vec2f(1.0));
  let p = uv * f32(FLUID_SIZE - 1u);
  let i = vec2i(floor(p));
  let f = fract(p);
  let a = mix(fluidCell(i.x, i.y), fluidCell(i.x + 1, i.y), f.x);
  let b = mix(fluidCell(i.x, i.y + 1), fluidCell(i.x + 1, i.y + 1), f.x);
  return mix(a, b, f.y);
}

@compute @workgroup_size(8, 8)
fn csFluid(@builtin(global_invocation_id) gid: vec3u) {
  if (gid.x >= FLUID_SIZE || gid.y >= FLUID_SIZE) {
    return;
  }

  let uv = (vec2f(gid.xy) + 0.5) / f32(FLUID_SIZE);
  let dt = frame.pointerDelta.z;
  let texel = 1.0 / f32(FLUID_SIZE);
  let current = fluidCell(i32(gid.x), i32(gid.y));
  let previousUv = uv - current.xy * dt * params.uAdvection.x;
  let advected = sampleFluid(previousUv);

  var velocity = advected.xy * exp(-params.uVelocityDissipation.x * dt);
  var dye = advected.z * exp(-params.uDyeDissipation.x * dt);

  // Lightweight viscosity/diffusion step. Together with semi-Lagrangian advection this
  // forms the interactive 2D flow field that drives the 3D volume.
  let left = sampleFluid(uv - vec2f(texel, 0.0)).xy;
  let right = sampleFluid(uv + vec2f(texel, 0.0)).xy;
  let down = sampleFluid(uv - vec2f(0.0, texel)).xy;
  let up = sampleFluid(uv + vec2f(0.0, texel)).xy;
  let neighborAverage = (left + right + down + up) * 0.25;
  velocity = mix(velocity, neighborAverage, clamp(params.uViscosity.x * dt * 12.0, 0.0, 0.45));

  // Permanent unstable vortex forcing around the center keeps the gas rolling outward.
  let centerDelta = uv - vec2f(0.5);
  let centerRadius = max(length(centerDelta), 0.001);
  let tangent = vec2f(-centerDelta.y, centerDelta.x) / centerRadius;
  let centerFalloff = exp(-centerRadius * 4.2);
  let audioPulse = frame.pointer.w;
  velocity += tangent * centerFalloff * (0.08 + audioPulse * 0.14) * params.uTurbulence.x * dt;
  velocity += normalize(centerDelta + vec2f(0.0001)) * centerFalloff * params.uExpansion.x * 0.025 * dt;
  dye += centerFalloff * (0.025 + audioPulse * 0.035) * dt;

  // Click/drag injection: drag direction adds velocity, while a click also creates a
  // radial/tangential impulse so a stationary press is visible immediately.
  if (frame.pointer.z > 0.5) {
    let mouseDelta = uv - frame.pointer.xy;
    let radius = max(params.uMouseRadius.x, 0.005);
    let influence = exp(-dot(mouseDelta, mouseDelta) / (radius * radius));
    let radial = normalize(mouseDelta + vec2f(0.0001));
    let mouseTangent = vec2f(-radial.y, radial.x);
    let drag = frame.pointerDelta.xy * params.uMouseForce.x;
    velocity += influence * (drag + radial * 0.30 + mouseTangent * 0.18) * dt * 8.0;
    dye += influence * params.uMouseDye.x * dt * 4.0;
  }

  let speed = length(velocity);
  if (speed > 1.4) {
    velocity *= 1.4 / speed;
  }

  let index = gid.y * FLUID_SIZE + gid.x;
  fluidOut.cells[index] = vec4f(velocity, clamp(dye, 0.0, 2.5), 0.0);
}

fn hash31(p: vec3f) -> f32 {
  var q = fract(p * 0.1031);
  q += dot(q, q.yzx + vec3f(33.33));
  return fract((q.x + q.y) * q.z);
}

fn noise3(p: vec3f) -> f32 {
  let i = floor(p);
  var f = fract(p);
  f = f * f * (3.0 - 2.0 * f);

  let n000 = hash31(i + vec3f(0.0, 0.0, 0.0));
  let n100 = hash31(i + vec3f(1.0, 0.0, 0.0));
  let n010 = hash31(i + vec3f(0.0, 1.0, 0.0));
  let n110 = hash31(i + vec3f(1.0, 1.0, 0.0));
  let n001 = hash31(i + vec3f(0.0, 0.0, 1.0));
  let n101 = hash31(i + vec3f(1.0, 0.0, 1.0));
  let n011 = hash31(i + vec3f(0.0, 1.0, 1.0));
  let n111 = hash31(i + vec3f(1.0, 1.0, 1.0));

  let nx00 = mix(n000, n100, f.x);
  let nx10 = mix(n010, n110, f.x);
  let nx01 = mix(n001, n101, f.x);
  let nx11 = mix(n011, n111, f.x);
  return mix(mix(nx00, nx10, f.y), mix(nx01, nx11, f.y), f.z);
}

fn fbm(pInput: vec3f) -> f32 {
  var p = pInput;
  var sum = 0.0;
  var amplitude = 0.54;
  for (var octave = 0; octave < 5; octave += 1) {
    sum += noise3(p) * amplitude;
    p = p * 2.03 + vec3f(7.1, 13.7, 5.3);
    amplitude *= 0.48;
  }
  return sum;
}

fn rotateY(p: vec3f, angle: f32) -> vec3f {
  let c = cos(angle);
  let s = sin(angle);
  return vec3f(c * p.x + s * p.z, p.y, -s * p.x + c * p.z);
}

fn densityField(pInput: vec3f) -> f32 {
  let time = frame.timeResolution.x;
  let audio = frame.pointer.w;
  let fluidUv = clamp(pInput.xy * 0.33 + vec2f(0.5), vec2f(0.0), vec2f(1.0));
  let fluid = sampleFluid(fluidUv);

  var p = pInput;
  let radius = max(length(p), 0.001);
  let direction = p / radius;

  // WGSL swizzles are value expressions, not assignable l-values. Rebuild the
  // complete vec3 instead of assigning to p.xy.
  let fluidWarp = fluid.xy * params.uFluidInfluence.x * (0.7 + 0.3 * (1.0 - clamp(radius, 0.0, 1.0)));
  p = vec3f(p.xy + fluidWarp, p.z);

  // Radially travelling domain warp creates the outward rolling/billowing motion.
  let travel = time * params.uExpansion.x;
  let radialPhase = radius * 7.5 - travel * 3.2;
  let warpA = fbm(p * params.uNoiseScale.x + direction * (travel * 0.65));
  let warpB = fbm(p.yzx * (params.uNoiseScale.x * 1.73) - direction.zxy * (travel * 0.48));
  p += vec3f(warpA - 0.5, warpB - 0.5, warpA - warpB) * params.uTurbulence.x * 0.32;

  let detail = fbm(p * params.uNoiseScale.x * 1.35 + vec3f(
    sin(radialPhase),
    cos(radialPhase * 0.83),
    sin(radialPhase * 0.61),
  ));

  let breathingRadius = 0.70 + audio * params.uAudioInfluence.x * 0.18;
  let rollingBoundary = breathingRadius + (detail - 0.48) * 0.55 + sin(radialPhase + detail * 4.0) * 0.055;
  let envelope = 1.0 - smoothstep(rollingBoundary, rollingBoundary + 0.34, radius);
  let hollow = smoothstep(0.10, 0.42, radius + detail * 0.10);
  let rollingBands = 0.68 + 0.32 * sin(radialPhase * 1.15 + detail * 6.0);
  let breakup = smoothstep(params.uDetailCutoff.x, 0.92, detail + fluid.z * 0.20);

  let fluidDensity = fluid.z * params.uFluidInfluence.x * 0.28 * (1.0 - smoothstep(0.9, 1.45, radius));
  return max(0.0, (envelope * hollow * (0.48 + breakup * 0.78) * (0.80 + rollingBands * 0.28) + fluidDensity) * params.uDensity.x);
}

fn intersectSphere(ro: vec3f, rd: vec3f, radius: f32) -> vec2f {
  let b = dot(ro, rd);
  let c = dot(ro, ro) - radius * radius;
  let h = b * b - c;
  if (h < 0.0) {
    return vec2f(1e6, -1e6);
  }
  let root = sqrt(h);
  return vec2f(-b - root, -b + root);
}

fn waveform(x: f32, time: f32) -> f32 {
  return sin(x * 31.0 + time * 5.2) * 0.46
    + sin(x * 57.0 - time * 8.1 + 1.7) * 0.25
    + sin(x * 13.0 + time * 2.4) * 0.18;
}

@fragment
fn fsMain(in: VertexOut) -> @location(0) vec4f {
  let resolution = frame.timeResolution.yz;
  let aspect = frame.timeResolution.w;
  let screen = vec2f((in.uv.x * 2.0 - 1.0) * aspect, in.uv.y * 2.0 - 1.0);
  let time = frame.timeResolution.x;

  var ro = vec3f(0.0, 0.0, 3.15);
  var rd = normalize(vec3f(screen * vec2f(0.88, 0.88), -1.65));
  let cameraAngle = sin(time * 0.11) * 0.10;
  ro = rotateY(ro, cameraAngle);
  rd = rotateY(rd, cameraAngle);

  let hit = intersectSphere(ro, rd, 1.48);
  var background = mix(vec3f(0.008, 0.012, 0.020), vec3f(0.035, 0.055, 0.080), in.uv.y);
  let vignette = 1.0 - 0.24 * dot(screen * 0.48, screen * 0.48);
  background *= max(vignette, 0.55);

  var color = background;
  if (hit.y > max(hit.x, 0.0)) {
    let steps = clamp(i32(params.uSteps.x), 24, 192);
    let startT = max(hit.x, 0.0);
    let travel = hit.y - startT;
    let stepLength = travel / f32(steps);
    let jitter = (hash31(vec3f(in.position.xy, fract(time))) - 0.5) * stepLength * params.uJitter.x;
    var t = startT + jitter;
    var transmittance = 1.0;
    var scattering = vec3f(0.0);
    let lightDir = normalize(vec3f(-0.55, 0.72, 0.42));
    let gasColor = params.uGasColor.xyz;

    for (var i = 0; i < 192; i += 1) {
      if (i >= steps) { break; }
      let p = ro + rd * t;
      let density = densityField(p);
      if (density > 0.004) {
        let shadowDensity = densityField(p + lightDir * 0.10)
          + densityField(p + lightDir * 0.22) * 0.62
          + densityField(p + lightDir * 0.38) * 0.34;
        let light = 0.22 + 0.78 * exp(-shadowDensity * params.uShadow.x);
        let rim = pow(1.0 - abs(dot(normalize(p + vec3f(0.0001)), -rd)), 2.2);
        let sampleColor = gasColor * (light + rim * 0.22 + frame.pointer.w * params.uAudioInfluence.x * 0.08);
        let alpha = 1.0 - exp(-density * params.uAbsorption.x * stepLength);
        scattering += transmittance * alpha * sampleColor;
        transmittance *= 1.0 - alpha;
        if (transmittance < 0.018) { break; }
      }
      t += stepLength;
    }
    color = scattering + background * transmittance;
  }

  // Audio-reactive waveform overlay. It is deliberately synthetic and deterministic so
  // the demo works on GitHub Pages without microphone permissions.
  let waveX = in.uv.x * 2.0 - 1.0;
  let wave = -0.79 + waveform(waveX, time) * (0.025 + frame.pointer.w * 0.018) * params.uAudioInfluence.x;
  let lineDistance = abs(screen.y - wave);
  let line = exp(-lineDistance * max(resolution.y, 1.0) * 0.42);
  let baseline = exp(-abs(screen.y + 0.79) * max(resolution.y, 1.0) * 0.16) * 0.16;
  color += params.uWaveColor.xyz * (line * 0.78 + baseline);

  color = color / (color + vec3f(1.0));
  color = pow(max(color, vec3f(0.0)), vec3f(1.0 / 2.2));
  return vec4f(color, 1.0);
}

/* @shaderlab
{
  "version": 1,
  "parameters": {
    "uDensity": {
      "type": "float", "default": 1.55, "min": 0.2, "max": 4.0, "step": 0.01,
      "label": { "zh": "气体密度", "en": "Gas Density" },
      "description": { "zh": "整体缩放体积密度。", "en": "Scales the overall gas density." },
      "group": { "zh": "体积", "en": "Volume" }
    },
    "uAbsorption": {
      "type": "float", "default": 3.1, "min": 0.2, "max": 8.0, "step": 0.01,
      "label": { "zh": "吸收", "en": "Absorption" },
      "description": { "zh": "Beer-Lambert 吸收强度。", "en": "Beer-Lambert absorption strength." },
      "group": { "zh": "体积", "en": "Volume" }
    },
    "uSteps": {
      "type": "int", "default": 112, "min": 48, "max": 192, "step": 1,
      "label": { "zh": "光线步数", "en": "Ray Steps" },
      "description": { "zh": "体积 raymarch 的采样步数。", "en": "Ray-marching sample count." },
      "group": { "zh": "采样", "en": "Sampling" }
    },
    "uJitter": {
      "type": "float", "default": 0.78, "min": 0.0, "max": 1.0, "step": 0.01,
      "label": { "zh": "采样抖动", "en": "Jitter" },
      "description": { "zh": "减弱固定步长造成的带状伪影。", "en": "Reduces fixed-step banding." },
      "group": { "zh": "采样", "en": "Sampling" }
    },
    "uNoiseScale": {
      "type": "float", "default": 2.55, "min": 0.8, "max": 6.0, "step": 0.01,
      "label": { "zh": "噪声尺度", "en": "Noise Scale" },
      "description": { "zh": "控制翻滚云团的空间细节尺寸。", "en": "Controls the spatial size of rolling detail." },
      "group": { "zh": "形态", "en": "Shape" }
    },
    "uTurbulence": {
      "type": "float", "default": 1.20, "min": 0.0, "max": 2.5, "step": 0.01,
      "label": { "zh": "翻涌扰动", "en": "Turbulence" },
      "description": { "zh": "同时增强三维域扭曲和二维中心涡旋。", "en": "Strengthens both 3D domain warping and the central 2D vortex." },
      "group": { "zh": "形态", "en": "Shape" }
    },
    "uExpansion": {
      "type": "float", "default": 0.82, "min": 0.0, "max": 2.0, "step": 0.01,
      "label": { "zh": "向外扩散", "en": "Expansion" },
      "description": { "zh": "控制径向传播速度和中心外推力。", "en": "Controls radial travelling speed and central outward force." },
      "group": { "zh": "形态", "en": "Shape" }
    },
    "uDetailCutoff": {
      "type": "float", "default": 0.42, "min": 0.15, "max": 0.75, "step": 0.01,
      "label": { "zh": "细节侵蚀", "en": "Detail Erosion" },
      "description": { "zh": "提高后会得到更破碎、更不稳定的边缘。", "en": "Higher values produce more broken, unstable edges." },
      "group": { "zh": "形态", "en": "Shape" }
    },
    "uFluidInfluence": {
      "type": "float", "default": 1.15, "min": 0.0, "max": 2.5, "step": 0.01,
      "label": { "zh": "流体影响", "en": "Fluid Influence" },
      "description": { "zh": "二维速度/染料场对三维气体域扭曲与密度的影响。", "en": "How strongly the 2D velocity/dye field bends and thickens the 3D gas." },
      "group": { "zh": "流体", "en": "Fluid" }
    },
    "uAdvection": {
      "type": "float", "default": 1.0, "min": 0.1, "max": 2.0, "step": 0.01,
      "label": { "zh": "平流速度", "en": "Advection" },
      "description": { "zh": "二维半拉格朗日平流的回溯距离。", "en": "Backtrace distance for 2D semi-Lagrangian advection." },
      "group": { "zh": "流体", "en": "Fluid" }
    },
    "uViscosity": {
      "type": "float", "default": 0.18, "min": 0.0, "max": 1.0, "step": 0.01,
      "label": { "zh": "粘性", "en": "Viscosity" },
      "description": { "zh": "控制速度场的邻域扩散。", "en": "Controls neighborhood diffusion of the velocity field." },
      "group": { "zh": "流体", "en": "Fluid" }
    },
    "uVelocityDissipation": {
      "type": "float", "default": 0.48, "min": 0.0, "max": 3.0, "step": 0.01,
      "label": { "zh": "速度耗散", "en": "Velocity Dissipation" },
      "description": { "zh": "速度随时间衰减的速度。", "en": "Rate at which velocity decays over time." },
      "group": { "zh": "流体", "en": "Fluid" }
    },
    "uDyeDissipation": {
      "type": "float", "default": 0.34, "min": 0.0, "max": 3.0, "step": 0.01,
      "label": { "zh": "染料耗散", "en": "Dye Dissipation" },
      "description": { "zh": "交互注入密度随时间消散的速度。", "en": "Rate at which injected dye density fades." },
      "group": { "zh": "流体", "en": "Fluid" }
    },
    "uMouseForce": {
      "type": "float", "default": 5.5, "min": 0.0, "max": 14.0, "step": 0.1,
      "label": { "zh": "鼠标力度", "en": "Mouse Force" },
      "description": { "zh": "按住并拖动时注入二维速度场的力度。", "en": "Velocity injected while pressing and dragging." },
      "group": { "zh": "交互", "en": "Interaction" }
    },
    "uMouseRadius": {
      "type": "float", "default": 0.085, "min": 0.02, "max": 0.22, "step": 0.001,
      "label": { "zh": "交互半径", "en": "Interaction Radius" },
      "description": { "zh": "鼠标流体注入区域的半径。", "en": "Radius of the mouse fluid injection area." },
      "group": { "zh": "交互", "en": "Interaction" }
    },
    "uMouseDye": {
      "type": "float", "default": 1.25, "min": 0.0, "max": 3.0, "step": 0.01,
      "label": { "zh": "交互密度", "en": "Interaction Dye" },
      "description": { "zh": "点击/拖动向流场注入的染料密度。", "en": "Dye density injected by clicking or dragging." },
      "group": { "zh": "交互", "en": "Interaction" }
    },
    "uAudioInfluence": {
      "type": "float", "default": 1.0, "min": 0.0, "max": 2.5, "step": 0.01,
      "label": { "zh": "音频联动", "en": "Audio Influence" },
      "description": { "zh": "合成音频包络对气体呼吸、涡旋和波形的影响。", "en": "Influence of the synthetic audio envelope on breathing, vortices, and waveform." },
      "group": { "zh": "音频", "en": "Audio" }
    },
    "uShadow": {
      "type": "float", "default": 1.35, "min": 0.0, "max": 4.0, "step": 0.01,
      "label": { "zh": "体积阴影", "en": "Volume Shadow" },
      "description": { "zh": "近似自阴影的强度。", "en": "Strength of approximate self-shadowing." },
      "group": { "zh": "光照", "en": "Lighting" }
    },
    "uGasColor": {
      "type": "color", "default": "#78a6c7",
      "label": { "zh": "气体颜色", "en": "Gas Color" },
      "description": { "zh": "体积散射颜色。", "en": "Volumetric scattering color." },
      "group": { "zh": "外观", "en": "Appearance" }
    },
    "uWaveColor": {
      "type": "color", "default": "#55d8ff",
      "label": { "zh": "波形颜色", "en": "Wave Color" },
      "description": { "zh": "底部音频波动曲线颜色。", "en": "Color of the audio waveform drawn at the bottom." },
      "group": { "zh": "外观", "en": "Appearance" }
    }
  }
}
@endshaderlab */