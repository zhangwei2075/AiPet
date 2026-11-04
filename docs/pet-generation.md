# 宠物动画素材生成（免费路线）

> 面向「上传一张照片 → 生成桌面宠物」的流水线。目标是用 **零边际成本** 的途径，
> 把单张抠图变成可用的逐帧动画素材。
>
> 记录时间：2026-11。价格与免费额度会变，正式分发前请复核服务条款。

## 结论

| 路线 | 成本 | 角色一致性 | 适用场景 |
| --- | --- | --- | --- |
| **A. 本地 ComfyUI + SD1.5 / SDXL** | 0 元/张（电费 + 显存） | 好（需 IP-Adapter / ControlNet / 低 denoise） | 正式流水线、批量、隐私敏感 |
| **B. 云免费额度** | 0 元但有配额、限速、排队 | 中 | 验证效果、临时生成少量素材 |
| **C. 单图程序化变形** | 0 元、纯 CPU、毫秒级 | 完美（始终是同一张图） | 兜底、第一批动作、实时微动 |

推荐组合：**C 保底 → A 补关键动作 → B 只做效果验证**。
照片宠物不应依赖 Live2D / Spine 的人工分层绑定；也不应把「几秒生成」押在云端免费额度上。

> 当前状态（2026-11-01）：C 已落地（`services/petforge/petforge/animate.py`），
> A 的客户端与模板已落地（`comfy.py` + `workflows/img2img_frames.api.json`），
> App 生成时默认请求 `animate=true`，走程序化引擎。

---

## A. 本地 ComfyUI（真免费）

### 硬件与模型

| 模型 | 显存 | 备注 |
| --- | --- | --- |
| SD 1.5 | ~6 GB | 生态最全，IP-Adapter / ControlNet 权重最多 |
| SDXL | ~10–12 GB | 细节更好，速度慢 2–3 倍 |
| SDXL-Turbo / LCM | ~8 GB | 4–8 步出图，适合批量试错 |
| CPU only | 无要求 | 每帧几十秒，只适合一次性生成素材 |

模型许可：SD1.5 为 CreativeML OpenRAIL-M，SDXL 为 OpenRAIL++-M，**基础模型可商用**；
但社区微调模型经常附加「禁止商用 / 需署名 / 禁止生成特定内容」条款，使用前看模型卡。

### 关键节点

- **IP-Adapter**（或 Reference-only）：锁住宠物的毛色、花纹、配饰。
- **ControlNet OpenPose / Depth / Canny**：控制动作姿态，避免只换背景。
- **低 denoise img2img（0.35–0.5）**：不改结构，只改细微姿态，一致性最好。
- **固定 seed**：同一角色的所有帧共用 seed 基线，减少闪烁。
- **RIFE / FILM**（免费）：4–8 张关键帧补到 16–24 帧，比逐帧生成便宜得多。

### 一致性技巧（按收益排序）

1. 用**已经抠好的 base 图**做 img2img，而不是纯文生图。
2. 每帧只改**一个变量**（例如「左前爪抬起 2cm」），不要同时换视角和光照。
3. prompt 里固定角色描述前缀（品种、毛色、画风、描边），动作描述放最后。
4. 生成后做**统一对齐**（脚底 / 头部锚点）+ **色彩匹配** + **去重**，否则动起来会抖。
5. 动作幅度宁小勿大：照片宠物做大动作必然崩手脚，剧烈动作交给程序化形变。

### 建议帧数（8 fps）

| 动作 | 关键帧 | 说明 |
| --- | --- | --- |
| idle | 4–6 | 呼吸起伏，幅度 < 2% |
| walk | 6 | 上下 bob + 轻微前后倾 |
| run | 6–8 | bob 更大，允许水平前倾 |
| lie | 2–4 | 压扁 + 轻微倾斜 |
| hop | 4 | 蹲、起、顶点、落地 |

---

## B. 云免费额度（只适合验证）

| 服务 | 免费形态 | 注意 |
| --- | --- | --- |
| Google AI Studio / Gemini 图像 | 每日请求配额 | 用原图做参考图编辑，一致性最好；条款可能限制商用 |
| Hugging Face Inference API / Spaces | 月度额度 + ZeroGPU | 模型全，冷启动慢，排队 |
| Cloudflare Workers AI | 每日 neuron 配额 | SDXL / Flux-schnell，适合小批量 |
| Pollinations.ai | 免费、免 key | Flux 出图，排队、无商用保证 |
| Kaggle / Colab | 免费 T4 数小时 | 可跑 ComfyUI 批量出素材，会话会断 |
| ModelScope 魔搭 | 国内免费 GPU 额度 | 需实名，适合国内网络 |

通用坑：免费额度通常写明「仅测试 / 评估」；上传用户照片还涉及隐私与跨境传输。
**不要**把免费云 API 放进「用户点一下、几秒出结果」的主链路。

---

## C. 单图程序化变形（已实现）

不生成新图，直接对同一张透明 PNG 做仿射变换：

- 以**脚底中心**为轴心，保证贴地不漂移；
- 呼吸 = 纵向 squash + 横向反向补偿；
- 走路 / 跑步 = 上下 bob + 左右倾斜 + 轻微水平位移；
- 躺下 = 纵向压扁 + 小角度倾斜；
- 帧间做感知去重，避免出现内置宠物那种「两帧一模一样」的假动画。

优点：零成本、零闪烁、绝对一致、CPU 毫秒级。
缺点：做不出新视角、新肢体动作。所以它负责「保底」，AI 只补「程序化做不出来」的动作。

---

## 与 PetForge 的集成

```
照片
 └─ pipeline.generate()            抠图 + 贴纸 + 调色板 + 锚点（已有）
     └─ animate.generate_animation()     生成动作帧（新增）
         ├─ engine=procedural            仿射变形，默认，永远可用
         └─ engine=comfyui               低 denoise img2img，需要本机 ComfyUI
             └─ 逐帧抠图 + 对齐 + 去重
     └─ petpack.json: frames + animations + atlas
```

### 产物

```
pets/<id>/
├─ petpack.json
├─ base.png
├─ walk_0.png ... walk_5.png
├─ run_0.png  ... run_5.png
├─ lie_0.png  ... lie_1.png
└─ atlas.png            # 可选（--atlas / atlas=true），所有帧的网格图集
```

默认只生成 `walk` / `run` / `lie`：待机的呼吸起伏已经由 Flutter 端
`MotionEngine` 程序化完成，再生成 idle 帧属于重复劳动。
帧统一缩到 **512×512** 导出（桌面实际显示只有一两百像素），单帧约 200 KB。

`petpack.json` 新增：

```jsonc
{
  "animations": {
    "walk": { "fps": 8, "frames": ["walk_0.png", "walk_1.png", "..."] },
    "run":  { "fps": 10, "frames": ["run_0.png", "..."] },
    "lie":  { "fps": 3,  "frames": ["lie_0.png", "lie_1.png"] }
  },
  "atlas": {
    "file": "atlas.png",
    "cell": 512,
    "columns": 6,
    "frames": {
      "walk_0": [0, 0, 512, 512],
      "walk_1": [512, 0, 512, 512]
    }
  },
  "metrics": { "animate": "procedural" }
}
```

Flutter 端 `Pet.fromPack` 已支持 `animations`（`app/lib/models/pet.dart`），
`atlas` 暂未消费，留给后续「图集 + 预解码」优化。

### 接口

```bash
# 默认：只出单帧，行为和旧版一致
POST /api/generate            file=... style=sticker

# 程序化动画（App 内生成默认开启；HTTP 接口默认关闭以保持兼容）
POST /api/generate            file=... animate=true engine=procedural

# 本地 ComfyUI
POST /api/generate            file=... animate=true engine=comfyui

# 需要图集时再加 atlas=true（文件较大，默认关闭）
POST /api/generate            file=... animate=true atlas=true
```

CLI：

```bash
python -m petforge.cli photo.jpg -o out/ --animate
python -m petforge.cli photo.jpg -o out/ --animate --engine comfyui
```

### ComfyUI 配置

1. 安装 ComfyUI，放入一个 SD1.5/SDXL checkpoint。
2. 可选：安装 IP-Adapter / ControlNet 节点，在 ComfyUI 里搭好工作流。
3. `工作流 → 导出（API 格式）`，保存为
   `services/petforge/workflows/pet_frames.api.json`（也可以用自带的
   `workflows/img2img_frames.api.json`，或用 `--workflow` 指定别的路径）。
4. 把需要替换的字段写成占位符：

   | 占位符 | 注入值 |
   | --- | --- |
   | `{{image}}` | 上传后的 base 图文件名 |
   | `{{prompt}}` | 当前帧的动作提示词 |
   | `{{negative}}` | 负面提示词 |
   | `{{seed}}` | 帧序号推导的固定 seed |
   | `{{denoise}}` | 0.35–0.5 |
   | `{{checkpoint}}` | checkpoint 文件名，可留空自动取第一个 |

5. 启动 ComfyUI（默认 `127.0.0.1:8188`；用 `PETFORGE_COMFY` 或 `--comfy-host` 覆盖），
   再跑 `--engine comfyui`。

仓库自带一份**只用核心节点**的 img2img 模板
（`workflows/img2img_frames.api.json`），装上 checkpoint 即可跑；
它的角色一致性一般，正式使用建议换成带 IP-Adapter 的工作流。

---

## 清理已有 AI 帧

图生图经常产出「hop 帧里有两只狗」「run 帧其实是趴滑」这类素材。可以先用
`tools/clean_pet_frames.py` 做一遍清理：

```powershell
python tools\clean_pet_frames.py <源宠物目录> <输出宠物目录>
```

它会：

- 跳帧只保留位置最高的主体，去掉重复的小狗/小道具；
- 其他帧去掉面积极小的碎片；
- 统一缩放到 640 画布，按底边 + 中心对齐，避免走动时忽大忽小；
- 重建 `petpack.json`：walk 4 帧 @8fps、run 复用 walk @12fps、hop 4 帧 @10fps、
  lie 2 帧、drop 1 帧。

这是「修现有帧」；想要 Petdex 那种 6–8 帧的顺滑度，仍然需要图生图重新生成动作帧。

## 本机已搭好的 ComfyUI（2026-11-01）

这台机器已经有一套可用的 SD1.5 + IP-Adapter 流水线：

| 组件 | 路径 |
| --- | --- |
| ComfyUI 后端 | `D:\software\confyUI\ComfyUI\resources\ComfyUI` |
| Python 环境 | `D:\AiPet\services\comfyui\.venv`（torch 2.11.0+cu128） |
| Checkpoint | `models/checkpoints/DreamShaper_8_pruned.safetensors` |
| IP-Adapter | `models/ipadapter/ip-adapter_sd15.safetensors` |
| CLIP Vision | `models/clip_vision/CLIP-ViT-H-14-laion2B-s32B-b79K.safetensors` |
| 工作流 | `services/petforge/workflows/img2img_ipadapter.api.json` |

启动：

```powershell
cd D:\software\confyUI\ComfyUI\resources\ComfyUI
D:\AiPet\services\comfyui\.venv\Scripts\python.exe main.py --port 8188 --listen 127.0.0.1
```

验证：

```powershell
curl http://127.0.0.1:8188/system_stats
```

### 用现有姿势帧精修（推荐）

照片宠物已经有 walk / hop / lie 帧时，不要重新文生图；用这些帧做 img2img 底图，
IP-Adapter 锁外形，低 denoise 只修画风和细节：

```powershell
$env:PYTHONPATH='D:\AiPet\services\petforge'
D:\AiPet\services\petforge\.venv\Scripts\python.exe tools\refine_pet_frames.py `
  "C:\Users\<你>\AppData\Roaming\MomoPet\MomoPet\pets\p20261031-cartoon-dog" `
  "C:\Users\<你>\AppData\Roaming\MomoPet\MomoPet\pets\p20261101-youcai-ai"
```

脚本会保留原姿势、修掉重复主体/比例漂移，重新生成 640 画布的真帧动画包。

### 从零生成动作帧

```powershell
cd services\petforge
.\.venv\Scripts\python -m petforge.cli photo.jpg -o out\ `
  --animate --engine comfyui `
  --workflow workflows\img2img_ipadapter.api.json `
  --subject "a cute cartoon dog wearing an orange hoodie"
```

`--subject` 会拼进每一帧的 prompt；动作提示词和 denoise 在
`petforge/animate.py` 的 `ACTION_PROMPTS` / `ACTION_DENOISE` 里。

## 质量检查清单

生成完先看这几点，再决定是否采用：

- [ ] 每帧 alpha 边缘干净，没有白边 / 黑边
- [ ] 脚底位置一致，没有上下漂移
- [ ] 相邻帧亮度、色相没有跳变
- [ ] 没有两帧完全相同（用哈希去重）
- [ ] 手、脚、耳朵没有多出或少掉
- [ ] 首尾帧能循环（walk / run / idle）
- [ ] 512×512 下文件体积可接受（单帧 < 250 KB）

---

## 成本与风险

- **显存**：SD1.5 约 6 GB，SDXL 约 10–12 GB；CPU 可跑但慢。
- **电费 / 时间**：本地生成不是「零成本」，只是「零单价」。
- **免费额度**：随时可能缩水、限速、要求登录或实名。
- **许可**：基础模型可商用，社区模型 / LoRA 不一定；云服务免费层通常不允许商用。
- **隐私**：用户照片上传云端前必须明确告知；本地模式是差异化优势。
- **一致性**：AI 生成的多帧仍可能「同一只宠物但换了花纹」，必须有去重与人工抽检。

---

## 参考

- ComfyUI：<https://github.com/comfyanonymous/ComfyUI>
- IP-Adapter：<https://github.com/tencent-ailab/IP-Adapter>
- ControlNet：<https://github.com/lllyasviel/ControlNet>
- RIFE：<https://github.com/hzwer/Practical-RIFE>
- 现有实现：`services/petforge/petforge/animate.py`、`comfy.py`
- 格式说明：[petpack.md](petpack.md)
