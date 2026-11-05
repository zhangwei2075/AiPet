# 宠物包格式（petpack v1）

一个宠物就是一个文件夹：

```
pets/<petId>/
├─ petpack.json     元数据（本文件）
├─ base.png         照片生成宠物的主帧
├─ idle.png         内置宠物有 6 张：idle / happy / love / angry / sleepy / blink
├─ happy.png
├─ walk_0.png …    可选：逐帧动作（walk / run / lie / hop / drop / spin / eat …）
└─ idle_0.png …    可选：待机呼吸、说话、打盹等扩展动作帧
```

内置宠物放在 `app/assets/pets/<id>/`（打进 App，依次是 `doudou` 小黄豆 / `momo` 橘子团子 /
`mint` 薄荷麻薯 / `taro` 芋泥汤圆），用户生成的放在
`%APPDATA%/<应用支持目录>/pets/<id>/`（运行时扫描）。两者的 `petpack.json` 结构完全一致。

## 字段

```jsonc
{
  "schemaVersion": 1,
  "name": "小黄豆",

  // 性格：既用于本地小脑的台词，也会作为在线模型的 system prompt
  "personality": {
    "traits": ["元气", "贪吃", "黏人"],
    "tone": "短句、口语化、偶尔用颜文字，每次不超过 40 字",
    "greeting": "嗨，我是橘子团子！今天有带小零食吗？",
    "catchphrase": "陪你待着",
    "systemPrompt": "你是一只名叫「橘子团子」的桌面宠物……回答格式：[情绪]正文"
  },

  // 配色：第一项通常是最抢眼的那个，用于卡片 / 气泡
  "palette": ["#F7AA5F", "#FFE3C2", "#E6873D", "#FFB9A8", "#5A4034"],
  "accent": "#F7AA5F",

  // 交互锚点（归一化坐标，0~1，相对表情帧画布）
  "anchors": {
    "head": [0.5, 0.34],   // 头中心：点头部算「摸头」，好感度 +2
    "headRadius": 0.27,    // 头部半径：判定「摸头」的圆形范围
    "body": [0.5, 0.72]    // 身体中心：粒子（爱心 / 星星）的发射原点
  },

  // 渲染指标
  "metrics": {
    "heightRatio": 0.78,   // 主体高度占画布比例，用于贴地
    "cutout": "rembg",     // rembg | flat | grabcut | oval | badge | drawn
    "style": "sticker"     // sticker | soft | original | badge
  },

  // 表情帧：键是 PetMood 名字，值是文件名（相对本目录）
  "frames": {
    "idle": "idle.png",
    "happy": "happy.png",
    "love": "love.png",
    "angry": "angry.png",
    "sleepy": "sleepy.png",
    "blink": "blink.png"
  },

  // 逐帧动作：键必须和 PetMotion.name 对上，值是帧序列
  // 已支持：idle / walk / run / lie / hop / drop / spin / pat / talk / sleepy / angry / eat
  // <motion>_left 是另一朝向的独立序列（对齐 Petdex 的 run-left 行）
  // fps 缺省 8；帧文件同样是相对本目录的文件名
  "animations": {
    "walk": { "fps": 8, "frames": ["walk_0.png", "walk_1.png", "walk_2.png"] },
    "run": { "fps": 10, "frames": ["run_0.png", "run_1.png", "run_2.png"] },
    "lie": { "fps": 3, "frames": ["lie_0.png", "lie_1.png"] },
    "idle": { "fps": 6, "frames": ["idle_0.png", "idle_1.png"] },
    "eat": { "fps": 8, "frames": ["eat_0.png", "eat_1.png"] }
  },

  // 可选：网格图集（当前 Flutter 端未消费，留给批量预解码使用）
  "atlas": {
    "file": "atlas.png",
    "cell": 512,
    "columns": 6,
    "rows": 3,
    "frames": { "walk_0": [0, 0, 512, 512] }
  },

  "source": "photo"        // photo | builtin
}
```

### 解析规则（`Pet.fromPack`）

- `frames` 缺 `idle` 时，拿第一个可用帧当 idle；一个都没有就假定 `idle.png`。
- `frames` 缺某个情绪帧时回退到 idle。照片生成的宠物只有 `idle` 时，其余表情靠动画叠加；
  带 `animations` 的包（PetForge `animate=true` 生成）走真实逐帧动画。
- `blink` 帧只影响眨眼表现，没有就压扁一下代替（`Pet.supportsBlink`）。
- `animations` 里帧列表为空的项会被忽略；`fps` 缺省 8。动作名要和
  `PetMotion.name` 对上（`walk` / `run` / `lie` / `hop` / `spin` / `eat`…），否则不会被播放。
- **帧文件必须真实存在**：`PetStage` 预解码时用 `onError` 忽略加载失败，
  声明了却不存在的帧会表现为「动作期间宠物消失」。增删帧时记得同步 `petpack.json`。
- 只有 `idle` 表情帧、又带 `idle` 呼吸动画时，`PetStage` 在 happy / love / angry 等情绪下
  会跳过呼吸帧，改用 `ExpressionOverlay` 表现表情，避免呼吸帧盖住情绪。
- `eat` 由主动讨食行为触发（见 [架构说明](architecture.md#状态与行为)），
  没有该序列时回退到 `motion.dart` 的程序化点头姿态。
- `atlas` 是可选优化，缺省时按 `animations` 里的独立帧加载。
- `palette` 为空时补一个暖橙色；`accent` 缺失时取 `palette.first`。
- 任何字段缺失都有默认值，`{ "frames": {...} }` 这样的最小包也能跑起来。

## 自制宠物

### 方式一：用 PetForge 生成（推荐）

```bash
python -m petforge.cli photo.jpg -o out/ --name 小橘 --style sticker
```

得到 `out/小橘/petpack.json` + `base.png`，整目录丢进用户宠物目录即可。

### 方式二：手写

最低要求：一个 512×512 左右的透明 PNG + 一份 `petpack.json`。`frames` 只写 `idle` 也能用。

想有完整的 6 种表情，可以参考 `tools/make_builtin_pets.py`：
它用 PIL 超采样绘制猫 / 兔，再调用 `petforge.pipeline.apply_sticker_style` 统一成描边贴纸风格，
同时生成 `petpack.json` 与托盘 / 应用图标。

```powershell
python tools\make_builtin_pets.py
```

### 方式三：App 内生成

管理面板 →「生成」→ 选照片 → 收养。产物会写进应用支持目录下的 `pets/p<时间戳>/`，
在「宠物库」里可以随时切换或删除。

### 方式四：给已有的单图宠物补动作帧

`tools/generate_pet_motion_frames.py` 用 Pillow + numpy 对 `frames.idle` 做**分部件蒙皮**，
幂等生成 idle / walk / run / hop / drop / lie / talk / eat / sleepy / angry / spin
共 67 帧并写回 `petpack.json`（只覆盖自己管理的 11 个 key，附带 `walk_left` / `run_left`
两条方向序列，不动性格 / 配色 / 其它字段），加上 16 张方向镜像帧一共 83 张图。
只依赖 Pillow 与 numpy，不需要模型或 ComfyUI。

![有财动作帧](images/youcai-motion-frames.jpg)

```powershell
# 项目里的导出素材
services\petforge\.venv\Scripts\python.exe tools\generate_pet_motion_frames.py

# 直接对桌面端正在使用的宠物目录生成（改完重启 App 生效）
services\petforge\.venv\Scripts\python.exe tools\generate_pet_motion_frames.py `
    --pet-dir "$env:APPDATA\MomoPet\MomoPet\pets\<petId>"
```

Windows 上应用支持目录来自 `windows/runner/Runner.rc` 的 CompanyName / ProductName，
当前是 `%APPDATA%\MomoPet\MomoPet\pets`。脚本每次运行会覆盖同名帧，但不会删除任何文件；
批量改动前建议先备份 `petpack.json`。

### 动画范式（对齐 [Petdex](petdex.md)）

早期版本对**整张图**做仿射变换，实测 4 张 walk 帧的差异区域都是
`x=59~512, y=22~512`（整只狗一起动），所以走路看不出四肢交替、动作一大就果冻化，
转圈还错误地用了绕图像中心的 2D 旋转（`rotation: 2πp`）。现在的规则：

- **分部件蒙皮**：身体划成 head / ear_left / ear_right / mouth / body / front_left /
  front_right / hind_left / tail 九个部件，每个部件有自己的**关节枢轴**（肩、胯、颈、耳根、尾根）
  与**超高斯权重**。每个部件可独立做「绕枢轴旋转 + 平移 + 缩放 + 压暗」，
  再按权重做 alpha 加权合成；没被任何部件覆盖的像素保留原图。
  于是耳朵会滞后甩动、尾巴会摇、嘴能张合、四肢能各自动。
- **步态方向**：绕肩枢轴大角度旋转会让脚**向两侧甩**（读起来像劈叉），
  所以走路的主运动是**竖直抬脚 + 略向身体内收 + 脚掌轻微拉伸**，旋转只留很小的胫骨倾角；
  躯干做起伏 + 2 倍频左右重心转移，把两个半周期区分开（避免 `walk_0` / `walk_4` 长得一样）。
- **绕垂直轴转身**：`spin` 序列的帧号代表**朝向**，
  `PetStage` 按一次性动作进度取帧而不是按 fps 循环。视角齐了走四视角硬切（见下文），
  只在缺视角时退回单图蒙皮（头保持宽度不被压扁、躯干按 `|cos|` 收窄、远近侧肢体错位并压暗）。
  两种情况都保证帧内 **y 恒定、无 2D rotation、无整体倾斜**。
  `MotionEngine.spin` 只留水平面内的微动。
- **方向独立序列**：`<motion>_left` / 普通序列对应 Petdex 的 running-left / running-right，
  渲染层按 `facing` 选择，不再靠运行时镜像假装转身。两套序列是**独立的镜像帧文件**，
  不是把帧序倒过来播 —— 倒序会让脚往回迈，读起来像倒带。
- **侧面步态**：正面坐姿的四条腿在画面上叠在一起，无论怎么摆都读不出交替，
  这是「只有一只脚在动」的根因。所以 `walk` / `run` 改用 AI 生成的**纯侧面 90° 底图**
  （`_ai/side_profile_raw_cut.png`，四腿沿 x 前后排开、后腿不被下摆遮挡），
  配套第三套部件标定 `PROFILE_PARTS`；没有它时退回 3/4 视角的 `SIDE_PARTS`。
  侧面能看见腿的倾角，主运动必须是**绕肩 / 胯前后摆动**（对角两两成对：近前 + 远后同相），
  正面那套「竖直抬脚 + 内收」搬到侧面只会读成原地踏步。
  四个必须做的补偿：
  ① 绕枢轴转 θ 会让脚掌沿圆弧**下移** `-sinθ·dx + (cosθ-1)·dy`，
  底图的脚本来就贴着画布底边，不反向抵消就会被裁成断腿，抵消后支撑相的脚底锁在地面、只剩前后位移；
  ② 超高斯权重的长尾很长，椭圆外 1.5 倍半径处还有 0.17 的权重，
  腿一摆就把卫衣下摆的像素按几十个百分点搬过去、叠成半透明拖影，
  所以权重要做 smoothstep 软截断，让部件只影响自己椭圆附近；
  ③ 腿和尾巴用**椭圆内饱和的 rigid 权重**（中心 78% 半径内恒为 1、边界快速归零）——
  软高斯在边界留半权重，原位描边和旋转后描边会双重曝光；
  ④ **摆幅上限约 0.14 rad**（run 0.19）：椭圆遮罩固定、内容随腿旋转，
  摆幅一大腿的白描边就扫进 vacated 区域拖出弧形细丝，0.27 rad 实测明显，
  0.14 时脚掌位移约 10px、细丝藏进腿自身轮廓，摆动读感靠抬脚高度补。
- **帧数**：idle 6 / walk 8 / run 8 / hop 5 / lie 6 / talk 4 / eat 6 / sleepy 6 /
  angry 8 / spin 8，加上 `walk_left` / `run_left` 各 8 张镜像帧，共 83 帧，
  与 Petdex 的状态行帧数一致。

![有财侧面走路与奔跑帧](images/youcai-side-gait.jpg)

动态预览（静态拼图看不出步态连贯性）：[走路](images/youcai-walk.gif) /
[奔跑](images/youcai-run.gif) / [转圈](images/youcai-spin.gif)。

**转圈：从柱面近似到四视角硬切**（2026-11，两轮实测）

第一轮想做「正面 → 侧前 → 背面 → 另一侧」四视角**交叉淡化**，失败，两个原因：

1. 50% 的混合帧是**两个头的叠加**，看起来像残影而不是转身；
2. 更根本的是**姿态不一致**——正面底图是坐姿，而当时手上的侧前 / 背面是**四足站姿**，
   转到一半姿态会跳，这是结构差异，调参补不了。

第二轮补齐了**和 `base.png` 同姿态的坐姿侧前 + 坐姿背面**（出图提示词里把
`rump resting on the ground, hind legs folded at the sides, front legs straight down`
写死，姿态才没跑偏），转圈改成**硬切 + 柱面压窄过渡**：

| 帧 | 角度 | 取帧 | 轮廓宽 |
| --- | --- | --- | --- |
| 0 | 0° | 正面 `base.png` | 337 |
| 1 | 45° | 坐姿侧前 | 368 |
| 2 | 90° | 坐姿侧前压到 0.62 | 228 |
| 3 | 135° | 坐姿背面压到 0.92 | 247 |
| 4 | 180° | 坐姿背面（原宽） | 294 |
| 5 | 225° | 坐姿背面压到 0.92 | 247 |
| 6 | 270° | 侧前镜像压到 0.62 | 229 |
| 7 | 315° | 侧前镜像 | 368 |

过渡帧**不用淡化**：两张不同视角各占一半 alpha，12fps 下读起来是双头双尾的残影；
压窄是个单调变化，反而读得出「正在侧过去」。宽度按 90°/270° 最窄、180° 回到背面原宽，
跳变被最窄处掩盖，八帧的高度都是 475px（贴地不跳）。

代价：手头只有一个背面视角，135°/225° 两帧是对同一张背面的等比例压窄，逐帧比对完全一样。
转一圈只要 667ms，观感上是「背面一闪而过」，可以接受；要彻底解决需要 8 方向的独立图集。

![两种转圈方案对比](images/youcai-spin-compare.jpg)

三个视角的对齐与抠图见 [有财三视角](images/youcai-sit-views.jpg)。
坐姿侧面用于转圈、四足站姿侧面用于走路，**两者不可互换**——混用会在转身中途从坐姿跳成站姿。

**AI 生成素材的边界**（2026-11 两轮实测，避免重复踩）：

*第一轮：本地 ComfyUI + SD1.5*

| 尝试 | 结果 |
| --- | --- |
| img2img（IP-Adapter）denoise 0.45 / 0.65 / 0.72 / 0.80 / 0.85 | 画质变好，但**全部仍是正面**——初始潜空间被底图锁死，`side` 提示词无效 |
| txt2img + IP-Adapter（空 latent，weight 0.9） | 能换姿态，但**换不出可靠视角**，且身份漂移（卫衣、耳朵、花纹都变） |
| txt2img 求「四足站立」底图 × 6 个种子 | 全部输出**两条后腿直立**的拟人站姿——SD1.5 + 坐姿参考会往拟人化跑 |

*第二轮：内置出图模型（多图参考 + `input_fidelity`，单张 5~10 credits）*

| 需求 | 结果 |
| --- | --- |
| 坐姿侧前 3/4 | ✅ 臀部着地、后腿折叠、前爪撑地，姿态与 `base.png` 一致；卫衣 / 胸背带 / 垂耳全部保留 |
| 坐姿背面 | ✅ 完全无脸、后脑与耳背正确、连帽搭在后背、胸背带交叉、尾巴从下摆正中伸出 |
| 四足站姿侧面 | ✅ 但只是 3/4 前侧而非纯 profile，四腿分开可见（用于 `walk` / `run`） |
| 8 帧连续步态 | ❌ 模型无帧间约束（无 seed 通道、帧 i 不依赖帧 i-1），逐帧生成必然闪烁 |

两条结论：

1. **能生成「关键视角底图」，不能生成「每一帧」。** 正确分工是 AI 只出 2~4 个视角的底图
   （正面 / 侧前 / 背面 / 侧后），中间帧继续交给本文上面的分部件蒙皮算，
   这样既有真实视角、帧间又零漂移。
   侧前 + 背面的坐姿三视角样张见 `docs/images/youcai-sit-views.jpg`，
   走路的站姿样张见 `docs/images/youcai-ai-views.jpg`，原始产物在 `exports/有财/_ai/`。
2. **`background: transparent` 参数时灵时不灵**，同一套参数会返回三种东西：真透明通道、
   纯白底、**画进图片里的假棋盘格**。前两种能按白底处理，第三种必须按「中性灰」判定
   （亮格是纯白、暗格约 220，都和白描边同为中性色，颜色阈值分不开）。
   三种情况统一由 [`tools/normalize_ai_frames.py`](../tools/README.md) 处理。
3. **姿态必须写死在提示词里。** 只说「same dog, side view」会得到四足站立；
   要坐姿就得把 `rump resting on the ground, hind legs folded, front legs straight down`
   这类关节状态逐条列出，否则转身中途会从坐姿跳成站姿。

要真正达到 Petdex 的 8 方向观感，还是得有一整套 8×9 / 8×11 图集（单独绘制，或训练角色 LoRA
后批量生成），再用 `PetdexImporter` 导入；当前的分部件蒙皮是它的低保真替代。
