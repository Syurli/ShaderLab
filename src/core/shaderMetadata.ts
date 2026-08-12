import type {
  ParameterValues,
  ShaderLabMetadata,
  ShaderParameterMetadata,
} from './types';

const METADATA_BLOCK = /\/\*\s*@shaderlab\s*([\s\S]*?)\s*@endshaderlab\s*\*\//m;

function assertLocalizedText(
  value: unknown,
  field: string,
): asserts value is { zh: string; en: string } {
  if (
    !value ||
    typeof value !== 'object' ||
    typeof (value as { zh?: unknown }).zh !== 'string' ||
    typeof (value as { en?: unknown }).en !== 'string'
  ) {
    throw new Error(`[ShaderLab] ${field} must contain { zh, en } strings.`);
  }
}

function validateParameter(name: string, value: unknown): ShaderParameterMetadata {
  if (!value || typeof value !== 'object') {
    throw new Error(`[ShaderLab] Parameter ${name} must be an object.`);
  }

  const param = value as ShaderParameterMetadata;
  const allowed = new Set(['float', 'int', 'boolean', 'color', 'enum']);
  if (!allowed.has(param.type)) {
    throw new Error(`[ShaderLab] Parameter ${name} has unsupported type: ${param.type}`);
  }

  if (param.default === undefined) {
    throw new Error(`[ShaderLab] Parameter ${name} requires a default value.`);
  }

  assertLocalizedText(param.label, `${name}.label`);
  if (param.description) assertLocalizedText(param.description, `${name}.description`);
  if (param.group) assertLocalizedText(param.group, `${name}.group`);

  return param;
}

export function parseShaderLabMetadata(source: string): ShaderLabMetadata {
  const match = source.match(METADATA_BLOCK);
  if (!match) {
    return { version: 1, parameters: {} };
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(match[1]);
  } catch (error) {
    throw new Error(
      `[ShaderLab] Invalid @shaderlab JSON: ${error instanceof Error ? error.message : String(error)}`,
    );
  }

  if (!parsed || typeof parsed !== 'object') {
    throw new Error('[ShaderLab] @shaderlab block must contain a JSON object.');
  }

  const data = parsed as Partial<ShaderLabMetadata>;
  if (data.version !== 1) {
    throw new Error(`[ShaderLab] Unsupported metadata version: ${String(data.version)}`);
  }

  const parameters = data.parameters ?? {};
  if (typeof parameters !== 'object' || Array.isArray(parameters)) {
    throw new Error('[ShaderLab] parameters must be an object keyed by shader variable name.');
  }

  return {
    version: 1,
    parameters: Object.fromEntries(
      Object.entries(parameters).map(([name, value]) => [name, validateParameter(name, value)]),
    ),
  };
}

export function createDefaultParameterValues(metadata: ShaderLabMetadata): ParameterValues {
  return Object.fromEntries(
    Object.entries(metadata.parameters).map(([name, config]) => [name, config.default]),
  );
}
