# Solar Prominence Particle Arcs / 太阳日珥粒子弧

一个面向 WebGL2 的实例化粒子实验。粒子围绕不可见球面缓慢差速旋转，多组独立事件在随机位置触发狭窄喷发束；喷发路径使用解析参数化弧线。球面粒子保持纯白，真正离开球面的粒子按离面距离映射为连续的阳光光谱彩虹色。

## 运动模型

- 基础球面：由 `gl_InstanceID` 的确定性 hash 生成均匀球面方向。
- 喷发事件：4 个独立事件通道，每个通道同时保留当前事件与前两代历史事件。旧事件在离开历史窗口之前先连续衰减，因此提高喷射频率不会再让仍在飞行或回落的粒子突然跳回球面。
- 条状源区：局部切线坐标中的窄 `across` 带 + 有限 `along` 长度，保持侧视时的细丝形态。
- 喷射密度：`uEjectionDensity` 调整细条内部有多少粒子参与，不通过简单加宽喷射条来堆数量，因此不会轻易重新变成薄面。
- 日珥轨迹：径向高度和切向位移都在 `p=0/1` 时严格归零，保证发射和落地位置连续。
- 回落：落地后使用 `exp(-damping*t) * sin(frequency*t)` 的阻尼振动，初始位移严格为 0，再逐步振荡衰减。
- 球面水波：喷发产生沿球面传播的波前。多个喷发波场可以互相干涉，使整个球面产生类似水面的持续起伏，而不只是在喷发点附近抖动。
- 颜色：静止/球面粒子为纯白；离面喷射粒子按位移连续映射为高饱和彩虹光谱。

## 主要参数

### 喷发

- `uEruptionRate`：喷射频率。
- `uEruptionChance`：每个时间槽实际发生喷发的概率。
- `uInfluenceRadius`：喷发点附近的局部初始波及范围。
- `uEjectionDensity`：细条内部参与喷射的粒子密度。

### 形状

- `uRibbonLength` / `uRibbonWidth`：真正被抛出的条状源区长度和宽度。
- `uArcHeight` / `uArcLength`：日珥的高度与横向弧形展开。
- `uShapeRandomness`：形态随机度与粒子发射时差。

### 回落与球面波浪

- `uFlightDuration`：一次完整抛出与回落的时长。
- `uReturnDamping` / `uReturnFrequency`：落地后的阻尼和振动频率。
- `uSurfaceWave`：整体球面波浪位移强度。
- `uWaveRange`：波浪沿球面的传播范围，`2.0` 接近传播到球体对侧。
- `uWaveSpeed`：波前传播速度。
- `uWaveDamping`：全局波场随时间衰减的速度。

### 性能与观察

- `uParticleCount`：总粒子数量，参数面板最高 200,000；移动端后端安全上限 120,000，桌面后端安全上限 240,000。
- `uParticleSize`：粒子视觉尺寸。
- `uRotationSpeed`：球面缓慢差速旋转速度。
- `uCameraDistance`：观察距离。

## HLSL 迁移

核心数学没有依赖 WebGL transform feedback 或 CPU 粒子状态，可直接迁移到 HLSL：

- `gl_InstanceID` → `SV_InstanceID`
- GLSL `vec*` → HLSL `float*`
- `mix` → `lerp`
- `fract` → `frac`
- `cross` / `dot` / `sin` / `smoothstep` 可直接对应

事件历史、参数化弧线、阻尼振动和球面传播波都只依赖确定性数学；渲染层当前使用 camera-facing instanced quad，在 HLSL 中可用 `SV_VertexID + SV_InstanceID` 或实例化顶点数据实现同样结构。
