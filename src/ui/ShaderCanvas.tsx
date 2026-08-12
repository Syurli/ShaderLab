import { useEffect, useRef, useState } from 'react';
import type {
  ExperimentDefinition,
  ParameterValues,
  PerfSnapshot,
} from '../core/types';
import { createRendererBackend } from '../renderers/createRendererBackend';
import type { RendererBackend } from '../renderers/RendererBackend';

interface ShaderCanvasProps {
  experiment: ExperimentDefinition;
  values: ParameterValues;
  onPerf: (snapshot: PerfSnapshot) => void;
}

export function ShaderCanvas({ experiment, values, onPerf }: ShaderCanvasProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const valuesRef = useRef(values);
  const [error, setError] = useState<string | null>(null);
  valuesRef.current = values;

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    let backend: RendererBackend | null = null;
    let animationFrame = 0;
    let disposed = false;
    let pointerX = 0.5;
    let pointerY = 0.5;

    const resize = () => {
      if (!backend) return;
      const rect = canvas.getBoundingClientRect();
      backend.resize(
        Math.max(1, rect.width),
        Math.max(1, rect.height),
        window.devicePixelRatio,
      );
    };

    const observer = new ResizeObserver(resize);
    observer.observe(canvas);

    const onPointerMove = (event: PointerEvent) => {
      const rect = canvas.getBoundingClientRect();
      pointerX = (event.clientX - rect.left) / Math.max(rect.width, 1);
      pointerY = 1 - (event.clientY - rect.top) / Math.max(rect.height, 1);
      backend?.setPointer(pointerX, pointerY);
    };
    canvas.addEventListener('pointermove', onPointerMove);

    const startTime = performance.now();
    let lastFrameTime = startTime;
    let perfWindowStart = startTime;
    let perfFrames = 0;
    let perfAccumulated = 0;

    const render = (now: number) => {
      if (!backend || disposed) return;
      const elapsed = (now - startTime) / 1000;
      backend.setParameters(valuesRef.current);
      backend.render(elapsed);

      const frameMs = now - lastFrameTime;
      lastFrameTime = now;
      perfAccumulated += frameMs;
      perfFrames += 1;

      if (now - perfWindowStart >= 500) {
        const surface = backend.getSurfaceInfo();
        onPerf({
          fps: (perfFrames * 1000) / (now - perfWindowStart),
          frameMs: perfAccumulated / Math.max(perfFrames, 1),
          width: surface.width,
          height: surface.height,
          drawCalls: surface.drawCalls,
          renderer: surface.renderer,
        });
        perfFrames = 0;
        perfAccumulated = 0;
        perfWindowStart = now;
      }

      animationFrame = requestAnimationFrame(render);
    };

    const boot = async () => {
      try {
        setError(null);
        const nextBackend = createRendererBackend({
          canvas,
          experiment,
          initialValues: valuesRef.current,
        });
        await nextBackend.initialize();
        if (disposed) {
          nextBackend.dispose();
          return;
        }
        backend = nextBackend;
        backend.setPointer(pointerX, pointerY);
        resize();
        animationFrame = requestAnimationFrame(render);
      } catch (reason) {
        if (!disposed) {
          setError(reason instanceof Error ? reason.message : String(reason));
        }
      }
    };

    void boot();

    return () => {
      disposed = true;
      cancelAnimationFrame(animationFrame);
      canvas.removeEventListener('pointermove', onPointerMove);
      observer.disconnect();
      backend?.dispose();
    };
  }, [experiment, onPerf]);

  return (
    <>
      <canvas ref={canvasRef} className="shader-canvas" />
      {error && (
        <div
          role="alert"
          style={{
            position: 'absolute',
            inset: 24,
            display: 'grid',
            placeItems: 'center',
            pointerEvents: 'none',
          }}
        >
          <div
            style={{
              maxWidth: 720,
              padding: '18px 20px',
              border: '1px solid var(--danger)',
              borderRadius: 8,
              background: 'rgba(12, 15, 19, .94)',
              color: 'var(--text)',
              font: '12px SFMono-Regular, Consolas, monospace',
              lineHeight: 1.6,
              whiteSpace: 'pre-wrap',
            }}
          >
            <strong style={{ color: 'var(--danger)' }}>Renderer backend failed</strong>\n{error}
          </div>
        </div>
      )}
    </>
  );
}
