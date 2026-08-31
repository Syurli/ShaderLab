# Solar Prominence Particle Arcs / 太阳日珥粒子弧

一个面向 WebGL2 的实例化粒子实验。粒子围绕不可见球面缓慢差速旋转，多组独立事件在随机位置触发狭窄喷发束；喷发路径使用解析参数化弧线，外围只产生柔和球面波动。粒子落回球面后继续进行指数衰减的阻尼振动，因此不会在“喷发状态 / 球面状态”之间硬切换。

## 运动模型

- 基础球面：由 `gl_InstanceID` 的确定性 hash 生成均匀球面方向。
- 喷发源：5 个独立事件通道，使用黄金角序列与 hash 选择位置和时间槽。
- 条状源区：局部切线坐标中的窄 `across` 带 + 有限 `along` 长度，避免侧面观察时形成整片薄面。
- 日珥轨迹：径向高度和切向位移都使用 `sin(PI * p)`，在 `p=0/1` 时严格回到球面，在中段形成弧状细丝。
- 回落：落地后使用 `exp(-damping*t) * sin(frequency*t)` 的阻尼振动，并向周围传播衰减余波。
- 颜色：球面粒子保持沙金色，离球面后的粒子按高度连续映射为彩虹。

## 主要参数

- `uEruptionRate`：喷射频率。
- `uEruptionChance`：每个时间槽实际发生喷发的概率。
- `uInfluenceRadius`：喷发周围的柔和波及范围。
- `uRibbonLength` / `uRibbonWidth`：真正被抛出的条状源区长度和宽度。
- `uArcHeight` / `uArcLength`：日珥的高度与横向弧形展开。
- `uShapeRandomness`：形态随机度与粒子发射时差。
- `uFlightDuration`：一次完整抛出与回落的时长。
- `uReturnDamping` / `uReturnFrequency`：落地后的阻尼和振动频率。
- `uSurfaceWave`：外围与落地后的球面余波幅度。
- `uParticleCount` / `uParticleSize`：性能与粒子视觉尺寸。

## HLSL 迁移

核心数学没有依赖 WebGL transform feedback 或 CPU 粒子状态，可直接迁移到 HLSL：

- `gl_InstanceID` → `SV_InstanceID`
- GLSL `vec*` → HLSL `float*`
- `mix` → `lerp`
- `fract` → `frac`
- `cross` / `dot` / `sin` / `smoothstep` 可直接对应

渲染层当前使用 camera-facing instanced quad；在 HLSL 中可用 `SV_VertexID + SV_InstanceID` 或实例化顶点数据实现同样结构。
