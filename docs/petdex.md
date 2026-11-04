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

## MomoPet 的映射

`app/lib/services/petdex_importer.dart` 会把图集切成独立 PNG（208×208，底部对齐、
水平翻转以匹配我们的朝向约定），再写一份普通 `petpack`：

| MomoPet | Petdex 行 |
| --- | --- |
| `animations.idle` | 0 idle |
| `animations.walk` / `run` | 1 running-right（run 提高 fps） |
| `frames.love` | 3 waving 首帧 |
| `animations.hop` / `frames.happy` | 4 jumping |
| `frames.angry` | 5 failed 首帧 |
| `animations.lie` / `frames.sleepy` | 6 waiting |
| `frames.blink` | idle 第 2 帧 |

## 使用

1. 先在本机安装一个 Petdex 宠物：

   ```bash
   npx petdex install boba
   ```

2. 打开 MomoPet →「我的宠物」→「导入 Petdex」。
3. 选择列表里的宠物，导入后会保存成普通自定义宠物，可切换、改名、删除。

只读取本机已安装的宠物；不会联网下载，也不会把素材写进安装包。

## 为什么它的动画更好

Petdex 的每一帧是**单独绘制的 192×208 像素画**，每个状态 4–8 帧，并带逐帧时长；
MomoPet 的照片宠物默认只是对一张抠图做仿射变形（压扁 / 倾斜 / 上下浮动），
所以动作幅度一大就会「果冻化」。导入 Petdex 图集后，走 / 跑 / 跳 / 待机都是真帧动画，
观感会接近 Petdex 桌面 App。

照片宠物想达到同样效果，仍然需要走 [pet-generation.md](pet-generation.md) 里的
ComfyUI / 图生图路线生成多姿态帧。
