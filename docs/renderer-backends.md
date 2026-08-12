# Renderer Backend Contract

ShaderLab separates the React workspace from GPU API details through `RendererBackend`.

## Lifecycle

Every backend implements:

- `initialize()` — create the API/device/context/pipeline.
- `resize()` — synchronize the drawing surface with the viewer size and device pixel ratio.
- `setPointer()` — receive normalized pointer coordinates.
- `setParameters()` — upload the current metadata-driven parameter values.
- `render()` — submit one frame.
- `getSurfaceInfo()` — expose resolution, draw calls, and the renderer label to the performance panel.
- `dispose()` — release GPU resources.

The React `ShaderCanvas` owns only lifecycle orchestration, `ResizeObserver`, pointer events, and frame timing.

## Current backends

### `webgl2`

Implemented by `WebGL2Backend`. It wraps `THREE.WebGLRenderer` and keeps compatibility with the existing GLSL fullscreen experiments.

### `raw-webgpu`

Implemented by `RawWebGPUBackend`. It owns `GPUAdapter`, `GPUDevice`, `GPUCanvasContext`, render pipeline, bind groups, and uniform buffers directly.

The backend injects two WGSL uniform structs before the experiment source:

```wgsl
struct ShaderLabFrame {
  timeResolution: vec4f,      // time, width, height, aspect
  pointerPixelRatio: vec4f,   // pointer.x, pointer.y, pixelRatio, reserved
};

struct ShaderLabParams {
  // one vec4f slot per @shaderlab parameter
};
```

Parameter keys stay in English and become WGSL struct fields, e.g. `params.uDensity.x`.

Each parameter owns a full `vec4f` slot. Scalars and booleans use `.x`; colors use `.xyz`. The deliberately simple 16-byte slot rule keeps WGSL uniform layout deterministic and lets metadata remain the source of truth for the parameter panel and GPU upload path.

## Adding another backend

1. Implement `RendererBackend`.
2. Register it in `createRendererBackend.ts`.
3. Keep API-specific objects out of React components.
4. Report a stable renderer label through `getSurfaceInfo()`.
5. Prefer the existing `@shaderlab` metadata rather than inventing backend-specific parameter schemas.
