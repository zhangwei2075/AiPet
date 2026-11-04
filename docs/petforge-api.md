# PetForge 接口

本地运行的 FastAPI 服务：照片 → 桌面宠物贴纸。默认 `http://127.0.0.1:8787`，
App 里的地址在「设置 → 形象工坊」可改（`forgeUrl`）。

## 启动

```powershell
powershell -ExecutionPolicy Bypass -File scripts\start-petforge.ps1        # 建 venv + 装依赖 + 起服务
powershell -ExecutionPolicy Bypass -File scripts\start-petforge.ps1 -WithRembg  # 额外装 rembg（约 170MB 模型）
```

等价于：

```bash
cd services/petforge
python -m venv .venv && .venv/Scripts/pip install -r requirements.txt
.venv/Scripts/python -m uvicorn petforge.api:app --host 127.0.0.1 --port 8787
```

启动后 <http://127.0.0.1:8787/docs> 是自动生成的 Swagger 页面。

依赖：`fastapi` / `uvicorn` / `python-multipart` / `pillow` / `numpy` / `opencv-python-headless`。
`rembg` + `onnxruntime` 是可选的，装上抠图质量明显更好。

## `GET /api/health`

```json
{
  "ok": true,
  "service": "petforge",
  "version": "0.1.0",
  "capabilities": {
    "opencv": "5.0.0",
    "rembg": false,
    "cutoutChain": ["rembg", "flat", "grabcut", "oval"],
    "animate": {
      "procedural": true,
      "comfyui": false,
      "comfyHost": "http://127.0.0.1:8188"
    }
  }
}
```

App 用它判断在线状态：拿不到 200 就切到本地徽章模式，`rembg: false` 时会在生成结果里提示「背景复杂时用圆形兜底」。
`capabilities.animate.comfyui` 为 `true` 表示检测到本机 ComfyUI（只在请求 `engine=comfyui` 时才会用到）。

## `POST /api/generate`

`multipart/form-data`：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `file` | 文件 | 必填，图片，≤ 15MB |
| `style` | 字符串 | `sticker`（默认，白描边贴纸）/ `soft`（轻微增强）/ `original`（原样） |
| `name` | 字符串 | 可选，不填由主色推导名字 |
| `removeBg` | 布尔 | 默认 `true` |
| `animate` | 布尔 | 默认 `false`；`true` 时额外生成 `walk` / `run` / `lie` 帧 |
| `engine` | 字符串 | `procedural`（默认，纯 CPU）/ `comfyui`（调用本机 ComfyUI，失败自动回退） |
| `atlas` | 布尔 | 默认 `false`；`true` 时额外返回 `atlas.png` 网格图集 |

响应就是一份 `petpack`（见 [petpack.md](petpack.md)），额外带：

```jsonc
{
  "schemaVersion": 1,
  "name": "蛋黄麻薯",
  "personality": { ... },
  "palette": ["#ed9b54", "#f9dbb8", ...],
  "anchors": { "head": [0.5, 0.24], "headRadius": 0.26, "body": [0.5, 0.72] },
  "metrics": { "cutout": "grabcut", "heightRatio": 0.9359, "style": "sticker" },
  "frames": { "idle": "base.png" },
  "animations": {
    "walk": { "fps": 8, "frames": ["walk_0.png", "walk_1.png", "..."] },
    "run": { "fps": 10, "frames": ["run_0.png", "..."] },
    "lie": { "fps": 3, "frames": ["lie_0.png", "lie_1.png"] }
  },
  "metrics": { "cutout": "grabcut", "heightRatio": 0.9359, "style": "sticker", "animate": "procedural" },

  "images": {
    "base": { "mimeType": "image/png", "data": "<base64>" },
    "walk_0": { "mimeType": "image/png", "data": "<base64>" }
  },
  "elapsedMs": 4317
}
```

错误：`400`（读不出图片 / 空文件）、`413`（> 15MB）、`422`（style / engine 非法）。

## `POST /api/preview`

同样收 `file` + `style`，只返回 `{"image": {<base64>}}`，用于生成过程中的快速预览。

## 抠图链路

`pipeline.remove_background` 按顺序尝试，命中即返回，结果里 `metrics.cutout` 记录用了哪种：

| 方法 | 适用 | 说明 |
| --- | --- | --- |
| `rembg` | 任意照片 | 装了 rembg 才可用，质量最好 |
| `flat` | 纯色 / 渐变背景 | 采样边框颜色做距离阈值 |
| `grabcut` | 主体居中、背景复杂 | OpenCV GrabCut，迭代几次 |
| `oval` | 全都失败时 | 椭圆裁剪兜底，永远不会崩 |

之外还有 alpha 清理（去碎点）、LAB 色彩最近邻精修、贴纸描边（`apply_sticker_style`）。

## 人格推导

`persona.py` 由调色板哈希决定名字 / 性格，同样的照片永远得到同一只宠物：

- 色相分组选名字池（暖橙→橘子/焦糖，绿→抹茶/青柠，蓝→湖水/蓝莓，紫→芋泥/葡萄，粉→桃桃/草莓…）
- 后缀池（团子 / 布丁 / 年糕 / 麻薯…）
- 性格三元组 + `systemPrompt`（含 `[情绪]正文` 的输出约定）

Flutter 端的 `lib/services/persona.dart` 是同一套规则的精简实现，用于离线徽章模式。

## CLI

```bash
python -m petforge.cli photo.jpg -o out/ --name 小橘 --style sticker --no-remove-bg
python -m petforge.cli photo.jpg -o out/ --animate                 # 程序化动画
python -m petforge.cli photo.jpg -o out/ --animate --engine comfyui  # 本地 ComfyUI
```

输出 `out/<名字>/base.png` + `petpack.json`（`--animate` 时再加 `walk_* / run_* / lie_*`），
可以直接当宠物包用。动画方案与免费生成途径见 [pet-generation.md](pet-generation.md)。

## 已做的验证

- `GET /api/health`：`ok: true`，`cutoutChain` 正常返回（opencv 5.0.0；rembg 装好后 `rembg: true`）。
- `POST /api/generate`：用 `tests/sample_photo.jpg` 上传，4.3 秒返回，`cutout=grabcut`，
  贴纸描边干净，`base.png` 234KB，`anchors` / `palette` / `personality` 均正常。
- `python -m petforge.cli`：同图生成 `out/测试团子/{petpack.json,base.png}` 成功。
- `animate=true`（2026-11-01）：同图生成 `walk` 6 帧 / `run` 6 帧 / `lie` 2 帧，
  512×512，合计约 3.1 MB；`petpack.json` 带 `animations`，HTTP 响应 4.2 MB，
  `metrics.animate=procedural`。单元测试 `tests/test_animate.py` 覆盖帧去重、图集、
  占位符注入与 ComfyUI 不可达回退；`tests/test_comfy.py` 用本地假服务验证了
  上传 / 提交 / 轮询 / 下载全链路。
- **真实照片（草地背景 + 灰白毛发的狗）实测**，很有代表性：

  | 场景 | 抠图方式 | 结果 | 耗时 |
  | --- | --- | --- | --- |
  | 未装 rembg | `grabcut` | **狗头被切掉**（毛色和枯草太接近，颜色模型分不清） | 24.3s |
  | 装上 rembg | `rembg` | 狗头、耳朵、毛边、四肢完整，白描边干净 | 首次 89.9s（含下载 170MB 模型），稳态 16.7s |

  结论：**复杂背景的照片强烈依赖 rembg**，`requirements-optional.txt` 实际是必装项。
  应用里已按抠图方式给出提示：`oval` 提醒装 rembg，非 `rembg` 也提示毛发边缘可能不干净。
- 端到端测试 `app/test/petforge_e2e_test.dart`：用应用真实的 `PetForgeClient` 上传 →
  生成 → `Pet.fromPack` 解析，服务未启动时自动跳过；
  `PETFORGE_TEST_IMAGE=<图片>` 可指定测试照片。

> 客户端超时已从 60s 放宽到 **3 分钟**：rembg 首次推理要下载模型，60s 会误判失败。
