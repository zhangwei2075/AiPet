# tools

- `make_builtin_pets.py`：用 PIL 生成内置宠物（橘子团子 / 薄荷麻薯 / 芋泥汤圆）的 6 种表情帧、
  `petpack.json`，以及应用图标 `app_icon.png/ico`、托盘图标 `tray.ico`。

```powershell
python tools\make_builtin_pets.py
```

依赖 `pillow`、`numpy`，并且会 import `services/petforge/petforge/pipeline.py` 里的
`apply_sticker_style`（描边贴纸风格），所以需要先有 petforge 的 Python 依赖。

- `generate_pet_motion_frames.py`：按 [Petdex](../docs/petdex.md) 范式，
  用**分部件蒙皮**给单图宠物生成动作帧，不依赖模型 / ComfyUI。幂等，
  覆盖 `idle / walk / run / hop / drop / lie / talk / eat / sleepy / angry / spin`
  共 67 帧，并写入 `walk_left` / `run_left` 两条独立方向序列。
  身体拆成九个部件（头 / 双耳 / 嘴 / 躯干 / 左右前脚 / 后脚 / 尾巴），
  每个部件有自己的关节枢轴，可独立旋转 / 平移 / 缩放 / 压暗后按权重合成；
  `spin` 是绕垂直轴的方向帧（y 恒定、无 2D 旋转）。依赖 `pillow` + `numpy`。

```powershell
# 默认处理 exports/有财
services\petforge\.venv\Scripts\python.exe tools\generate_pet_motion_frames.py

# 指定目录（例如桌面端正在使用的宠物包）
services\petforge\.venv\Scripts\python.exe tools\generate_pet_motion_frames.py `
    --pet-dir "$env:APPDATA\MomoPet\MomoPet\pets\<petId>"
```

输出：`idle_0..5` / `walk_0..7` / `run_0..7` / `hop_0..4` / `drop_0..1` /
`lie_0..5` / `talk_0..3` / `eat_0..5` / `sleepy_0..5` / `angry_0..7` /
`spin_0..7`（512×512 RGBA，共 67 帧）与更新后的 `petpack.json`。
依赖 `pillow`，用 `services/petforge/.venv/Scripts/python.exe` 运行即可。
字段与动作名规则见 [宠物包格式](../docs/petpack.md)。

- `refine_pet_frames.py` / `clean_pet_frames.py`：ComfyUI 图生图精修与帧清理，
  路线见 [宠物动画素材生成](../docs/pet-generation.md)。
