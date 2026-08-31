# Solar Prominence Particle Arcs / 太阳日珥粒子弧

一个面向 WebGL2 的实例化粒子实验。粒子围绕不可见球面缓慢差速旋转，多组独立事件在随机位置触发日珥喷发。当前版本进一步把基础球面改成大陆式不规则粒子占据：球面本身存在大块连续空洞，喷发源附近的现有球面粒子会被真实掀起，因此原位置会留下可见空缺，再在上升过程中向窄束收拢形成日珥。

## 运动与形态模型

- 基础球面：由 `gl_InstanceID` 的确定性 hash 生成均匀球面方向。
- 大陆式镂空：在粒子的材质球面方向上计算低频混合方向场，形成连续岛屿、海湾与空洞；纹理会随球面一起旋转。
- 喷发事件：4 个独立事件通道，每个通道保留当前事件和两代历史事件，避免高频参数下的时间槽闪切。
- 源区掀开：喷发不再只移动一小撮细丝粒子，而是先从球面上选出更大的椭圆形源区，把其中真实存在的粒子整体抬起。
- 日珥收束：被掀起的宽源区在上升阶段同时沿两个球面切线方向向中心线收拢，因此源区会明显镂空，但空中的结构仍收束成细长的三维日珥束，而不是一张薄面。
- 连续回落：所有抛出、收束和侧向偏移都包含 `sin(PI*p)` 型包络，在 `p=0/1` 严格回到原球面位置；落地后再进行指数衰减的阻尼振动。
- 球面波：喷发与落地会产生沿球面传播的水波式波前，多组波可叠加干涉；波只移动已有粒子，不会填补大陆式空洞。
- 颜色：静止/波动球面粒子保持纯白；真正离开球面的粒子按离面距离映射为阳光散射式连续彩虹。

## 当前默认预设

默认值按 2026-08-31 调试参数固化：

- `uParticleCount = 18000`
- `uEruptionRate = 4.5`
- `uEruptionChance = 1.0`
- `uInfluenceRadius = 0.9`
- `uEjectionDensity = 4.0`
- `uRibbonLength = 0.36`
- `uRibbonWidth = 0.07`
- `uArcHeight = 1.0`
- `uArcLength = 0.95`
- `uShapeRandomness = 1.0`
- `uFlightDuration = 2.45`
- `uRotationSpeed = 1.0`
- `uReturnDamping = 1.55`
- `uReturnFrequency = 1.05`
- `uSurfaceWave = 0.075`
- `uWaveRange = 2.0`
- `uWaveSpeed = 0.5`
- `uWaveDamping = 0.3`
- `uParticleSize = 2.2`

新增形态参数：

- `uShellCoverage`：大陆式粒子区域覆盖率，降低会出现更多镂空。
- `uShellPatternScale`：大陆/岛屿块状尺度。
- `uSourceExcavation`：相对于条带尺寸，真正从球面被掀起的源区范围；越高源区空洞越明显。

## HLSL 迁移

核心数学仍然不依赖 WebGL transform feedback 或 CPU 粒子状态，可直接迁移到 HLSL：

- `gl_InstanceID` → `SV_InstanceID`
- GLSL `vec*` → HLSL `float*`
- `mix` → `lerp`
- `fract` → `frac`
- `cross` / `dot` / `sin` / `smoothstep` / `exp` 可直接对应
- 低频大陆场、源区椭圆掩码、收束偏移、参数化日珥弧和球面传播波都只依赖解析数学

渲染层当前使用 camera-facing instanced quad；在 HLSL 中可用 `SV_VertexID + SV_InstanceID` 或实例化顶点数据实现同样结构。
