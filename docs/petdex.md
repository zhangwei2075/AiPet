# Petdex 宠物导入

[Petdex](https://petdex.dev/) 是一个「给 coding agent 用的动态宠物」画廊 + CLI + 桌面 App，
不是可以嵌进别的应用的 SDK。它和我们的关系是：**可以导入它安装到本机的宠物素材**，
但不能把它的画廊素材直接打包进 MomoPet 分发。

## 能不能直接用？

| 方式 | 可行性 | 说明 |
| --- | --- | --- |
| 把 Petdex 桌面 App 当桌宠 | ✅ | 独立程序，和 MomoPet 二选一或同时开 |
| 嵌入 Petdex 的渲染器 | ❌ | 没有公开 SDK；桌面 App 只暴露 `127.0.0.1:7777` 状态接口 |
| 导入它的宠物到 MomoPet | ✅ | 读取本机 `~/.codex/pets/<slug>/` 的 `pet.json` + 图集 |
| 把画廊素材打包进 App | ⚠️ | 代码 MIT，但宠物是用户投稿的同人图；Petdex 不主张底层 IP 权利，分发前必须逐个确认授权 |

## 素材格式

```text
~/.codex/pets/<slug>/
├─ pet.json
└─ spritesheet.webp   # 也支持 .png
```

`pet.json` 最少包含：

```json
{
  "id": "boba",
  "displayName": "Boba",
  "description": "A tiny otter sipping bubble tea...",
  "spriteVersionNumber": 2,
  "spritesheetPath": "spritesheet.webp"
}
```

图集是 **8 列**网格：

- v1：9 行，单帧 192×208，整图 1536×1872
- v2：11 行，单帧 192×208，整图 1536×2288

状态行（v1/v2 前 9 行一致）：

| 行 | 状态 | 帧数 |
| --- | --- | --- |
| 0 | idle | 6 |
| 1 | running-right | 8 |
| 2 | running-left | 8 |
| 3 | waving | 4 |
| 4 | jumping | 5 |
| 5 | failed | 8 |
| 6 | waiting | 6 |
| 7 | running | 6 |
| 8 | review | 6 |

### 方向是独立行，不是镜像或旋转

`running-right`（行 1）与 `running-left`（行 2）是**分别绘制**的两组 8 帧：
身体朝向、尾巴位置、手里的杯子都有区别，并不是把同一行水平翻转。
部分投稿宠物（如 JokeBear-CodexPet）还提供更细的 16-direction look 序列。

也就是说 Petdex 里转身 / 朝向变化靠**切换方向帧**，没有「把整张图绕中心旋转」
或「运行时镜像」的做法；帧内只有眨眼、尾巴、四肢交替这些局部变化，
身体基座和脚底始终稳定。对照本机 `~/.codex/pets/boba/spritesheet.webp` 可以直观看到这点。

## MomoPet 的映射

`app/lib/services/petdex_importer.dart` 会把图集切成独立 PNG（208×208，底部对齐、
水平翻转以匹配我们的朝向约定），再写一份普通 `petpack`：

| MomoPet | Petdex 行 |
| --- | --- |
| `animations.idle` | 0 idle（6 帧） |
| `animations.walk` / `run` | 1 running-right（8 帧，run 提高 fps） |
| `animations.walk_left` / `run_left` | 2 running-left（8 帧，独立方向序列） |
| `frames.love` / `animations.talk` | 3 waving（4 帧） |
| `animations.hop` / `frames.happy` | 4 jumping（5 帧） |
| `frames.angry` / `animations.angry` | 5 failed（8 帧） |
| `animations.lie` / `frames.sleepy` | 6 waiting（6 帧） |
| `frames.blink` | idle 第 2 帧 |

`PetStage._animationFor` 在 `facing < 0` 时优先取 `<motion>_left` 序列；
`facing` 只用于水平镜像，**不再承担旋转**。转身动作（`spin`）按一次性动作进度
把帧号当作朝向索引，绕垂直轴走完一圈。

## 使用

1. 先在本机安装一个 Petdex 宠物：

   ```bash
   npx petdex install boba
   ```

2. 打开 MomoPet →「我的宠物」→「导入 Petdex」。
3. 选择列表里的宠物，导入后会保存成普通自定义宠物，可切换、改名、删除。

只读取本机已安装的宠物；不会联网下载，也不会把素材写进安装包。

## 为什么它的动画更好

Petdex 的每一帧是**单独绘制的 192×208 像素画**，每个状态 4–8 帧，并带逐帧时长。
早期 MomoPet 的照片宠物是对**整张**抠图做仿射变形（压扁 / 倾斜 / 上下浮动），
实测 4 张 walk 帧的差异区域都是 `x=59~512, y=22~512`——整只狗一起动，
所以走路只剩一只脚在动、动作幅度一大就「果冻化」，转圈还错误地用了绕图像中心的 2D 旋转。

现在按 Petdex 范式改了两层：

1. **渲染层**：转身不再用 `rotation: 2πp`，改为绕垂直轴的方向帧序列；
   左右朝向各是一条独立序列，不是运行时镜像。
2. **素材层**：`tools/generate_pet_motion_frames.py` 用**位移场**代替整图仿射——
   头 / 躯干 / 四只脚 / 尾巴 / 嘴各自有独立权重，只动该动的部位，脚底加锚定衰减。

导入 Petdex 图集后仍是真帧动画，观感最接近桌面 App。但要强调：
一张正面照片**不包含侧面 / 背面的信息**，位移场和柱面重映射只是几何近似，
做不到 Petdex 那种独立绘制的 8 方向。真要达到同等质量，需要为有财单独出一套
8×9 / 8×11 图集（手工绘制、Hatch Pet，或 [pet-generation.md](pet-generation.md)
里的 ComfyUI 图生图补帧）；本机 ComfyUI 的 `models/checkpoints` 目前为空。
