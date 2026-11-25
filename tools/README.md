# tools

- `make_builtin_pets.py`：用 PIL 生成内置宠物（橘子团子 / 薄荷麻薯 / 芋泥汤圆）的 6 种表情帧与
  `petpack.json`。**不再生成应用图标**（图标已改为「有财」，见下一条），避免重跑时覆盖。

- `make_youcai_icons.py`：从 `exports/有财/base.png` 幂等生成托盘 / 任务栏 / EXE 的
  全部图标：`app/assets/icons/app_icon.png`（托盘 + logo）、`app_icon.ico`、`tray.ico`
  以及 `app/windows/runner/resources/app_icon.ico`（`IDI_APP_ICON`，任务栏）。
  8 帧多尺寸 ICO；≤32px 用头部特写与纯奶油底，小图标也看得清脸。
  `--preview` 只把候选样式写到 `.tmp/icon-preview/`，不覆盖正式图标。

```powershell
services\petforge\.venv\Scripts\python.exe tools\make_youcai_icons.py
```

```powershell
python tools\make_builtin_pets.py
```

依赖 `pillow`、`numpy`，并且会 import `services/petforge/petforge/pipeline.py` 里的
`apply_sticker_style`（描边贴纸风格），所以需要先有 petforge 的 Python 依赖。

- `generate_pet_motion_frames.py`：按 [Petdex](../docs/petdex.md) 范式，
  用**分部件蒙皮**给单图宠物生成动作帧，不依赖模型 / ComfyUI。幂等，
  覆盖 `idle / walk / run / hop / drop / lie / talk / eat / sleepy / angry / spin`
  共 67 帧 + 16 张方向镜像帧（`walk_left` / `run_left` 是**真正的水平镜像文件**，
  不是把帧序列倒过来播 —— 倒序会让脚往回迈，读起来像倒带）。
  身体拆成九个部件（头 / 双耳 / 嘴 / 躯干 / 左右前脚 / 后脚 / 尾巴），
  每个部件有自己的关节枢轴，可独立旋转 / 平移 / 缩放 / 压暗后按权重合成；
  `spin` 是绕垂直轴的方向帧（y 恒定、无 2D 旋转）。依赖 `pillow` + `numpy`。

  **三套部件标定**：`FRONT` 对应正面坐姿底图，`SIDE` 对应四足站立的侧前 3/4 底图，
  `PROFILE` 对应纯侧面 90° 底图（`_ai/side_profile_raw_cut.png`，后腿不被下摆遮挡）。
  走路 / 奔跑优先走 `PROFILE`，没有该底图时退回 `SIDE`，再没有退回 `FRONT` ——
  正面坐姿的四条腿叠在一起，怎么摆都读不出交替，这正是「只有一只脚在动」的根因。
  侧面步态是**腿绕肩 / 胯前后摆动**（对角两两成对），和正面的「竖直抬脚 + 内收」
  是两套机制，不能互换。腿 / 尾用椭圆内饱和的 rigid 权重，摆幅上限约 0.14 rad——
  椭圆遮罩固定而内容随腿旋转，摆幅大了白描边会扫出弧形细丝（详见 docs/petpack.md）。

  **转圈走坐姿四视角**：自动找 `_ai/side_sit_raw_cut.png` 与 `_ai/back_sit_raw_cut.png`。
  八帧 = 4 个真实视角（正面 / 坐姿侧前 / 坐姿背面 / 侧前镜像）+ 4 个柱面压窄过渡帧，
  180° 看到的是真背面。**不能用淡化**：两张视角各半 alpha 会重影成双头双尾。
  缺任一张就退回单图蒙皮（180° 仍是正脸），加 `--no-spin-views` 可强制退回。

```powershell
# 默认处理 exports/有财，自动找 _ai/ 下的侧面与坐姿视角底图
services\petforge\.venv\Scripts\python.exe tools\generate_pet_motion_frames.py

# 指定方向与目录（例如桌面端正在使用的宠物包）
services\petforge\.venv\Scripts\python.exe tools\generate_pet_motion_frames.py `
    --pet-dir "$env:APPDATA\MomoPet\MomoPet\pets\<petId>" --side-view <侧面底图>
```

输出：`idle_0..5` / `walk_0..7` / `run_0..7` / `hop_0..4` / `drop_0..1` /
`lie_0..5` / `talk_0..3` / `eat_0..5` / `sleepy_0..5` / `angry_0..7` /
`spin_0..7`（512×512 RGBA，共 67 帧 + 16 张镜像帧 = 83 帧）与更新后的 `petpack.json`。
字段与动作名规则见 [宠物包格式](../docs/petpack.md)。

- `normalize_ai_frames.py`：把 AI 生成的视角图整理成项目可用的透明帧。
  `background: transparent` **时灵时不灵**，同一套参数会返回三种东西，分别处理：

  | 实际返回 | 处理方式 |
  | --- | --- |
  | 真透明通道 | 直接沿用原 alpha（模型给的边缘最干净，重新抠只会更差） |
  | 纯白底 | 四角连通域泛洪 |
  | **画进图片里的假棋盘格** | 按「中性灰」判定后泛洪（亮格是纯白、暗格约 220，和白描边同为中性色，颜色阈值分不开） |

  白底和棋盘格都不能「全局白转透明」——白描边与背景同为白色且互相连通，
  那样会把白色毛发一起吃掉。去背后还会丢掉面积 < 最大前景 1% 的孤立碎块
  （棋盘格角落常留一两个像素的残点，肉眼看不见，却会把 bbox 拉到画布边缘、让对齐缩放整体算错）。
  `--align-to` 按参考帧的主体高度占比重新缩放并水平居中、底边对齐，保证切换动作时宠物不变大小。
  幂等，输出 `<名>_cut.png`。依赖 `pillow` + `numpy` + `scipy`。

```powershell
services\petforge\.venv\Scripts\python.exe tools\normalize_ai_frames.py `
    exports\有财\_ai\*.png --align-to exports\有财\base.png
```

- `refine_pet_frames.py` / `clean_pet_frames.py`：ComfyUI 图生图精修与帧清理，
  路线见 [宠物动画素材生成](../docs/pet-generation.md)。
