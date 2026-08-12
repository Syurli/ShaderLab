# ShaderLab

Realtime shader experiments for WebGL / WebGPU.

一个用于长期积累实时图形实验的静态 Shader 实验库：WebGL、WebGPU、WGSL、GLSL、SDF、Ray Marching、体积渲染、Compute、后处理等。

## V0.1

- Vite + TypeScript + React
- Three.js WebGL2 experiment runner
- WebGPU capability detection and backend-ready experiment metadata
- Chinese / English UI switch with persisted locale
- Shader-source-driven parameter panel
- `@shaderlab` bilingual metadata block embedded in GLSL / WGSL comments
- Gallery + experiment workspace + View / Code / Info / Perf tabs
- GitHub Pages deployment through GitHub Actions
- Three starter experiments: UV, SDF ray marching, basic volume ray marching

## Development

```bash
npm install
npm run dev
```

Production build:

```bash
npm run build
```

## Adding an experiment

1. Add the shader under `src/experiments/<category>/<experiment>/`.
2. Put the `/* @shaderlab ... @endshaderlab */` block at the end of the shader.
3. Register the experiment in `src/core/experimentRegistry.ts`.
4. Parameter controls are generated from the shader metadata automatically.

See [`docs/shader-metadata.md`](docs/shader-metadata.md) for the bilingual parameter annotation convention.

## GitHub Pages

The Vite base path is `/ShaderLab/`. The included workflow builds `dist/` and deploys it with GitHub Pages Actions.

Routes use URL hashes (`#/experiment/...`) so direct experiment links work on static GitHub Pages without a rewrite server.
