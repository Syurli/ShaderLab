import { useEffect, useRef } from 'react';
import * as THREE from 'three';
import type {
  ExperimentDefinition,
  ParameterValues,
  PerfSnapshot,
} from '../core/types';

interface ShaderCanvasProps {
  experiment: ExperimentDefinition;
  values: ParameterValues;
  onPerf: (snapshot: PerfSnapshot) => void;
}

function toUniformValue(value: number | boolean | string, type: string) {
  if (type === 'color') return new THREE.Color(String(value));
  return value;
}

export function ShaderCanvas({ experiment, values, onPerf }: ShaderCanvasProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const valuesRef = useRef(values);
  valuesRef.current = values;

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const renderer = new THREE.WebGLRenderer({
      canvas,
      antialias: true,
      powerPreference: 'high-performance',
    });
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    renderer.setClearColor(0x07090c, 1);

    const scene = new THREE.Scene();
    const camera = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1);
    const geometry = new THREE.PlaneGeometry(2, 2);

    const uniforms: Record<string, THREE.IUniform> = {
      uTime: { value: 0 },
      uResolution: { value: new THREE.Vector2(1, 1) },
      uPointer: { value: new THREE.Vector2(0.5, 0.5) },
    };

    Object.entries(experiment.metadata.parameters).forEach(([name, config]) => {
      uniforms[name] = {
        value: toUniformValue(config.default, config.type),
      };
    });

    const material = new THREE.ShaderMaterial({
      vertexShader: experiment.vertexShader,
      fragmentShader: experiment.fragmentShader,
      uniforms,
      depthWrite: false,
      depthTest: false,
    });

    const mesh = new THREE.Mesh(geometry, material);
    scene.add(mesh);

    const size = { width: 1, height: 1 };
    const resize = () => {
      const rect = canvas.getBoundingClientRect();
      const width = Math.max(1, Math.floor(rect.width));
      const height = Math.max(1, Math.floor(rect.height));
      size.width = width;
      size.height = height;
      renderer.setSize(width, height, false);
      uniforms.uResolution.value.set(width, height);
    };

    const observer = new ResizeObserver(resize);
    observer.observe(canvas);
    resize();

    const onPointerMove = (event: PointerEvent) => {
      const rect = canvas.getBoundingClientRect();
      uniforms.uPointer.value.set(
        (event.clientX - rect.left) / Math.max(rect.width, 1),
        1 - (event.clientY - rect.top) / Math.max(rect.height, 1),
      );
    };
    canvas.addEventListener('pointermove', onPointerMove);

    let animationFrame = 0;
    const startTime = performance.now();
    let lastFrameTime = startTime;
    let perfWindowStart = startTime;
    let perfFrames = 0;
    let perfAccumulated = 0;

    const render = (now: number) => {
      const elapsed = (now - startTime) / 1000;
      uniforms.uTime.value = elapsed;

      Object.entries(experiment.metadata.parameters).forEach(([name, config]) => {
        const next = valuesRef.current[name];
        if (config.type === 'color') {
          (uniforms[name].value as THREE.Color).set(String(next));
        } else {
          uniforms[name].value = next;
        }
      });

      renderer.render(scene, camera);

      const frameMs = now - lastFrameTime;
      lastFrameTime = now;
      perfAccumulated += frameMs;
      perfFrames += 1;

      if (now - perfWindowStart >= 500) {
        onPerf({
          fps: (perfFrames * 1000) / (now - perfWindowStart),
          frameMs: perfAccumulated / Math.max(perfFrames, 1),
          width: size.width,
          height: size.height,
          drawCalls: renderer.info.render.calls,
        });
        perfFrames = 0;
        perfAccumulated = 0;
        perfWindowStart = now;
      }

      animationFrame = requestAnimationFrame(render);
    };

    animationFrame = requestAnimationFrame(render);

    return () => {
      cancelAnimationFrame(animationFrame);
      canvas.removeEventListener('pointermove', onPointerMove);
      observer.disconnect();
      geometry.dispose();
      material.dispose();
      renderer.dispose();
    };
  }, [experiment, onPerf]);

  return <canvas ref={canvasRef} className="shader-canvas" />;
}
