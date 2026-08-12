# ShaderLab Metadata Convention / ShaderLab 参数注释规范

ShaderLab keeps runtime variable names in English and stores editor-facing bilingual metadata inside a block comment at the end of the shader source.

ShaderLab 保持运行时变量名为英文，并将编辑器需要的中英文名称、说明、范围与分组信息放在 Shader 源码末尾的块注释中。

## Marker / 标记

```glsl
/* @shaderlab
{
  "version": 1,
  "parameters": {
    "uDensity": {
      "type": "float",
      "default": 1.0,
      "min": 0.0,
      "max": 4.0,
      "step": 0.01,
      "label": { "zh": "密度", "en": "Density" },
      "description": {
        "zh": "对体积密度场进行整体缩放。",
        "en": "Scales the overall volume density field."
      },
      "group": { "zh": "体积", "en": "Volume" }
    }
  }
}
@endshaderlab */
```

The block is valid comment syntax in GLSL and WGSL, so it does not change shader execution. ShaderLab parses it with `JSON.parse`; therefore the contents must be strict JSON (double quotes, no trailing commas, no comments inside the JSON object).

该块在 GLSL 与 WGSL 中都属于合法注释，因此不会影响 Shader 运行。ShaderLab 直接使用 `JSON.parse` 解析，所以内部必须是严格 JSON：使用双引号、不能有尾逗号、JSON 对象内部不能再写注释。

## Parameter key / 参数键

The key under `parameters` is the runtime shader variable name. The UI always shows this key as a small technical identifier while displaying the localized `label` as the user-facing name.

`parameters` 下的 key 就是运行时 Shader 变量名。UI 会把它作为小号技术标识显示，同时使用本地化的 `label` 作为面板主名称。

## Supported types / 支持类型

- `float`: number slider + numeric input
- `int`: integer slider + numeric input
- `boolean`: toggle
- `color`: color picker (hex string default)
- `enum`: select; `options` can provide localized labels

## Required fields / 必填字段

Every parameter requires:

- `type`
- `default`
- `label.zh`
- `label.en`

Recommended:

- `description.zh` / `description.en`
- `group.zh` / `group.en`
- `min`, `max`, `step` for numeric parameters

## Design rule / 设计原则

1. Shader variable names and code identifiers stay English.
2. Human-facing editor labels and descriptions are bilingual.
3. Metadata lives next to the shader it documents, not in a duplicated UI config file.
4. Runtime-specific bindings may be handled by the experiment adapter, but the metadata key remains the canonical parameter identifier.
5. A future metadata version must increment `version` and keep the parser backward compatible.
