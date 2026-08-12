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
    let previousPointerX = pointerX;
    let previousPointerY = pointerY;
    let pointerDown = false;
    let benchmarkQueued = false;

    // requestAnimationFrame is synchronized to the display refresh rate. The optional
    // benchmark mode uses MessageChannel and, when the backend supports it, waits for
    // submitted GPU work before immediately scheduling the next frame. This avoids
    // building an unbounded WebGPU queue while allowing throughput above display Hz.
    const benchmarkChannel = new MessageChannel();

    const pushPointerState = () => {
      const dx = pointerX - previousPointerX;
      const dy = pointerY - previousPointerY;
      if (backend?.setPointerState) {
        backend.setPointerState({ x: pointerX, y: pointerY, down: pointerDown, dx, dy });
      } else {
        backend?.setPointer(pointerX, pointerY);
      }
      previousPointerX = pointerX;
      previousPointerY = pointerY;
    };

    const updatePointerPosition = (event: PointerEvent) => {
      const rect = canvas.getBoundingClientRect();
      pointerX = (event.clientX - rect.left) / Math.max(rect.width, 1);
      pointerY = 1 - (event.clientY - rect.top) / Math.max(rect.height, 1);
    };

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
      updatePointerPosition(event);
      pushPointerState();
    };
    const onPointerDown = (event: PointerEvent) => {
      canvas.setPointerCapture(event.pointerId);
      updatePointerPosition(event);
      pointerDown = true;
      pushPointerState();
    };
    const onPointerUp = (event: PointerEvent) => {
      updatePointerPosition(event);
      pointerDown = false;
      pushPointerState();
      if (canvas.hasPointerCapture(event.pointerId)) canvas.releasePointerCapture(event.pointerId);
    };
    const onPointerCancel = () => {
      pointerDown = false;
      pushPointerState();
    };

    canvas.addEventListener('pointermove', onPointerMove);
    canvas.addEventListener('pointerdown', onPointerDown);
    canvas.addEventListener('pointerup', onPointerUp);
    canvas.addEventListener('pointercancel', onPointerCancel);

    const startTime = performance.now();
    let lastFrameTime = startTime;
    let perfWindowStart = startTime;
    let perfFrames = 0;
    let perfAccumulated = 0;

    const uncappedBenchmarkEnabled = () => valuesRef.current.uUncappedBenchmark === true;

    const queueBenchmarkFrame = () => {
      if (disposed || benchmarkQueued) return;
      benchmarkQueued = true;
      benchmarkChannel.port2.postMessage(0);
    };

    const scheduleNext = () => {
      if (!backend || disposed) return;
      if (uncappedBenchmarkEnabled() && !document.hidden) {
        if (backend.waitForSubmittedWork) {
          void backend.waitForSubmittedWork().then(queueBenchmarkFrame, queueBenchmarkFrame);
        } else {
          queueBenchmarkFrame();
        }
      } else {
        animationFrame = requestAnimationFrame(render);
      }
    };

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
        const uncapped = uncappedBenchmarkEnabled();
        onPerf({
          fps: (perfFrames * 1000) / (now - perfWindowStart),
          frameMs: perfAccumulated / Math.max(perfFrames, 1),
          width: surface.width,
          height: surface.height,
          drawCalls: surface.drawCalls,
          renderer: uncapped ? `${surface.renderer} / uncapped` : surface.renderer,
        });
        perfFrames = 0;
        perfAccumulated = 0;
        perfWindowStart = now;
      }

      scheduleNext();
    };

    benchmarkChannel.port1.onmessage = () => {
      benchmarkQueued = false;
      render(performance.now());
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
        pushPointerState();
        resize();
        scheduleNext();
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
      benchmarkChannel.port1.close();
      benchmarkChannel.port2.close();
      canvas.removeEventListener('pointermove', onPointerMove);
      canvas.removeEventListener('pointerdown', onPointerDown);
      canvas.removeEventListener('pointerup', onPointerUp);
      canvas.removeEventListener('pointercancel', onPointerCancel);
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
