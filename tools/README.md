# tools

- `make_builtin_pets.py`：用 PIL 生成内置宠物（橘子团子 / 薄荷麻薯 / 芋泥汤圆）的 6 种表情帧、
  `petpack.json`，以及应用图标 `app_icon.png/ico`、托盘图标 `tray.ico`。

```powershell
python tools\make_builtin_pets.py
```

依赖 `pillow`、`numpy`，并且会 import `services/petforge/petforge/pipeline.py` 里的
`apply_sticker_style`（描边贴纸风格），所以需要先有 petforge 的 Python 依赖。

- `generate_pet_motion_frames.py`：给只有一张 `base.png` 的宠物补程序化动作帧，
  不依赖模型 / ComfyUI。幂等，只覆盖 `idle` / `talk` / `eat` / `sleepy` / `spin` 五个
  `animations` key，已有动作与元数据不动。

```powershell
# 默认处理 exports/有财
services\petforge\.venv\Scripts\python.exe tools\generate_pet_motion_frames.py

# 指定目录（例如桌面端正在使用的宠物包）
services\petforge\.venv\Scripts\python.exe tools\generate_pet_motion_frames.py `
    --pet-dir "$env:APPDATA\MomoPet\MomoPet\pets\<petId>"
```

输出：`idle_0..3.png`、`talk_0..1.png`、`eat_0..3.png`、`sleepy_0..1.png`、
`spin_0..7.png`（512×512 RGBA）与更新后的 `petpack.json`。
依赖 `pillow`，用 `services/petforge/.venv/Scripts/python.exe` 运行即可。
字段与动作名规则见 [宠物包格式](../docs/petpack.md)。

- `refine_pet_frames.py` / `clean_pet_frames.py`：ComfyUI 图生图精修与帧清理，
  路线见 [宠物动画素材生成](../docs/pet-generation.md)。
