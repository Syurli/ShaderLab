precision highp float;

in vec2 vUv;
in vec3 vColor;
in float vAlpha;
in float vSpark;
flat in float vSeed;
out vec4 outColor;

void main(){
  float r=length(vUv);
  float n1=sin(vUv.x*31.0+vUv.y*47.0+vSeed*91.7);
  float n2=sin(vUv.x*73.0-vUv.y*29.0+vSeed*37.3);
  float grain=clamp(0.5+0.32*n1+0.18*n2,0.0,1.0);
  float mask=1.0-smoothstep(0.48,1.0,r+(grain-0.5)*0.11);
  if(mask<0.01) discard;
  float core=1.0-smoothstep(0.0,0.72,r);
  float sparkle=vSpark*pow(max(core,0.0),5.0)*2.15;
  vec3 color=vColor*(0.76+0.66*core)+vec3(sparkle);
  outColor=vec4(color,mask*vAlpha*(0.78+0.22*grain));
}

/* @shaderlab
{
  "version":1,
  "parameters":{
    "uParticleCount":{"type":"int","default":10000,"min":6000,"max":200000,"step":2000,"label":{"zh":"粒子数量","en":"Particle Count"},"group":{"zh":"性能","en":"Performance"}},
    "uEruptionRate":{"type":"float","default":4.5,"min":0.25,"max":4.5,"step":0.05,"label":{"zh":"喷射频率","en":"Eruption Rate"},"group":{"zh":"喷发","en":"Eruption"}},
    "uEruptionChance":{"type":"float","default":1.0,"min":0.2,"max":1.0,"step":0.01,"label":{"zh":"喷发概率","en":"Eruption Chance"},"group":{"zh":"喷发","en":"Eruption"}},
    "uInfluenceRadius":{"type":"float","default":0.9,"min":0.12,"max":0.9,"step":0.01,"label":{"zh":"局部波及范围","en":"Local Influence Radius"},"group":{"zh":"喷发","en":"Eruption"}},
    "uEjectionDensity":{"type":"float","default":4.0,"min":0.5,"max":4.0,"step":0.05,"label":{"zh":"喷射粒子密度","en":"Ejection Density"},"group":{"zh":"喷发","en":"Eruption"}},
    "uSourceExcavation":{"type":"float","default":2.4,"min":0.8,"max":2.4,"step":0.05,"label":{"zh":"源区掀开范围","en":"Source Excavation"},"group":{"zh":"喷发","en":"Eruption"}},
    "uRibbonLength":{"type":"float","default":0.36,"min":0.045,"max":0.36,"step":0.005,"label":{"zh":"喷射条长度","en":"Ribbon Length"},"group":{"zh":"形状","en":"Shape"}},
    "uRibbonWidth":{"type":"float","default":0.07,"min":0.006,"max":0.07,"step":0.001,"label":{"zh":"喷射条宽度","en":"Ribbon Width"},"group":{"zh":"形状","en":"Shape"}},
    "uArcHeight":{"type":"float","default":0.39,"min":0.12,"max":1.3,"step":0.01,"label":{"zh":"日珥高度","en":"Arc Height"},"group":{"zh":"形状","en":"Shape"}},
    "uArcLength":{"type":"float","default":0.95,"min":0.05,"max":0.95,"step":0.01,"label":{"zh":"弧向展开","en":"Arc Span"},"group":{"zh":"形状","en":"Shape"}},
    "uShapeRandomness":{"type":"float","default":1.0,"min":0.0,"max":1.0,"step":0.01,"label":{"zh":"形状随机度","en":"Shape Randomness"},"group":{"zh":"形状","en":"Shape"}},
    "uShellCoverage":{"type":"float","default":0.32,"min":0.25,"max":0.95,"step":0.01,"label":{"zh":"球面覆盖率","en":"Shell Coverage"},"group":{"zh":"球面形态","en":"Shell Pattern"}},
    "uShellPatternScale":{"type":"float","default":1.8,"min":0.45,"max":2.5,"step":0.05,"label":{"zh":"大陆纹理尺度","en":"Continent Scale"},"group":{"zh":"球面形态","en":"Shell Pattern"}},
    "uFlightDuration":{"type":"float","default":2.45,"min":0.55,"max":3.5,"step":0.05,"label":{"zh":"飞行时长","en":"Flight Duration"},"group":{"zh":"运动","en":"Motion"}},
    "uRotationSpeed":{"type":"float","default":3.0,"min":0.0,"max":3.0,"step":0.05,"label":{"zh":"球面旋转速度","en":"Shell Rotation"},"group":{"zh":"运动","en":"Motion"}},
    "uReturnDamping":{"type":"float","default":1.55,"min":0.3,"max":6.0,"step":0.05,"label":{"zh":"回落阻尼","en":"Return Damping"},"group":{"zh":"回落","en":"Return"}},
    "uReturnFrequency":{"type":"float","default":1.05,"min":0.3,"max":4.0,"step":0.05,"label":{"zh":"回落振动频率","en":"Return Oscillation"},"group":{"zh":"回落","en":"Return"}},
    "uSurfaceWave":{"type":"float","default":0.075,"min":0.0,"max":0.4,"step":0.005,"label":{"zh":"球面波浪强度","en":"Surface Wave Strength"},"group":{"zh":"球面波浪","en":"Surface Waves"}},
    "uWaveRange":{"type":"float","default":2.0,"min":0.25,"max":2.0,"step":0.025,"label":{"zh":"球面波传播范围","en":"Wave Range"},"group":{"zh":"球面波浪","en":"Surface Waves"}},
    "uWaveSpeed":{"type":"float","default":0.5,"min":0.25,"max":4.0,"step":0.05,"label":{"zh":"球面波速度","en":"Wave Speed"},"group":{"zh":"球面波浪","en":"Surface Waves"}},
    "uWaveDamping":{"type":"float","default":0.3,"min":0.05,"max":2.5,"step":0.025,"label":{"zh":"球面波衰减","en":"Wave Damping"},"group":{"zh":"球面波浪","en":"Surface Waves"}},
    "uParticleSize":{"type":"float","default":1.4,"min":0.4,"max":2.2,"step":0.05,"label":{"zh":"粒子尺寸","en":"Particle Size"},"group":{"zh":"外观","en":"Appearance"}},
    "uShellColor":{"type":"color","default":"#ffffff","label":{"zh":"球面粒子颜色","en":"Shell Color"},"description":{"zh":"静止球面粒子的基础颜色。","en":"Base color of resting shell particles."},"group":{"zh":"颜色","en":"Color"}},
    "uShellBrightness":{"type":"float","default":1.75,"min":0.2,"max":4.0,"step":0.05,"label":{"zh":"球面亮度","en":"Shell Brightness"},"group":{"zh":"颜色","en":"Color"}},
    "uProminenceHueOffset":{"type":"float","default":0.0,"min":-1.0,"max":1.0,"step":0.01,"label":{"zh":"日珥光谱偏移","en":"Spectrum Hue Offset"},"description":{"zh":"整体平移日珥彩虹映射的色相。","en":"Shifts the whole prominence spectrum mapping."},"group":{"zh":"颜色","en":"Color"}},
    "uProminenceHueSpan":{"type":"float","default":0.88,"min":0.1,"max":2.0,"step":0.02,"label":{"zh":"日珥光谱范围","en":"Spectrum Hue Span"},"group":{"zh":"颜色","en":"Color"}},
    "uProminenceSaturation":{"type":"float","default":0.95,"min":0.0,"max":1.0,"step":0.01,"label":{"zh":"日珥饱和度","en":"Prominence Saturation"},"group":{"zh":"颜色","en":"Color"}},
    "uProminenceBrightness":{"type":"float","default":1.65,"min":0.2,"max":4.0,"step":0.05,"label":{"zh":"日珥亮度","en":"Prominence Brightness"},"group":{"zh":"颜色","en":"Color"}},
    "uOrbitLineColor":{"type":"color","default":"#ffffff","label":{"zh":"轨道线颜色","en":"Orbit Line Color"},"group":{"zh":"电子轨道","en":"Orbit Lines"}},
    "uOrbitLineBrightness":{"type":"float","default":2.2,"min":0.2,"max":4.0,"step":0.05,"label":{"zh":"轨道线亮度","en":"Orbit Brightness"},"group":{"zh":"电子轨道","en":"Orbit Lines"}},
    "uOrbitLineOpacity":{"type":"float","default":0.82,"min":0.05,"max":1.0,"step":0.01,"label":{"zh":"轨道线透明度","en":"Orbit Opacity"},"group":{"zh":"电子轨道","en":"Orbit Lines"}},
    "uOrbitRadius":{"type":"float","default":2.15,"min":1.75,"max":3.2,"step":0.05,"label":{"zh":"轨道半径","en":"Orbit Radius"},"group":{"zh":"电子轨道","en":"Orbit Lines"}},
    "uOrbitRotationSpeed":{"type":"float","default":1.0,"min":0.0,"max":3.0,"step":0.05,"label":{"zh":"轨道旋转速度","en":"Orbit Rotation"},"group":{"zh":"电子轨道","en":"Orbit Lines"}},
    "uOrbitPulse":{"type":"float","default":0.045,"min":0.0,"max":0.18,"step":0.005,"label":{"zh":"轨道律动幅度","en":"Orbit Pulse"},"group":{"zh":"电子轨道","en":"Orbit Lines"}},
    "uCameraDistance":{"type":"float","default":6.15,"min":3.3,"max":10.0,"step":0.05,"label":{"zh":"相机距离","en":"Camera Distance"},"group":{"zh":"观察","en":"View"}}
  }
}
@endshaderlab */
