# tools

- `make_builtin_pets.py`：用 PIL 生成内置宠物（橘子团子 / 薄荷麻薯 / 芋泥汤圆）的 6 种表情帧、
  `petpack.json`，以及应用图标 `app_icon.png/ico`、托盘图标 `tray.ico`。

```powershell
python tools\make_builtin_pets.py
```

依赖 `pillow`、`numpy`，并且会 import `services/petforge/petforge/pipeline.py` 里的
`apply_sticker_style`（描边贴纸风格），所以需要先有 petforge 的 Python 依赖。
