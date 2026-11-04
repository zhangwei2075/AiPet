# 自动更新

Windows 端支持可配置的版本检查接口：检查 → 下载 → 校验 → 启动安装（MSIX/EXE），
非安装包链接则打开下载页。

## 配置

管理面板 →「设置」→「更新」：

- **版本检查地址**：一个返回 JSON 的 HTTP(S) 地址；留空关闭更新。
- **启动时检查更新**：默认开启，仅在填写了地址时生效。
- **检查更新**：手动检查，结果显示在下方。
- **下载并安装**：有 `.msix` / `.msixbundle` / `.appx` / `.exe` 时下载并启动；
  其他链接显示「打开下载页」。

当前版本通过 `package_info_plus` 读取（与 `pubspec.yaml` 的 `version` 一致）。

## 清单格式

推荐按平台分组：

```json
{
  "version": "0.2.0",
  "notes": "新增多显示器游走、修复动画时钟",
  "windows": {
    "url": "https://example.com/MomoPet-0.2.0.msix",
    "sha256": "0123456789abcdef...",
    "size": 23390208
  }
}
```

也支持扁平写法：

```json
{
  "version": "0.2.0",
  "url": "https://example.com/MomoPet-0.2.0.msix",
  "notes": "可选",
  "sha256": "可选",
  "size": 123
}
```

字段：

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `version` | 是 | 新版本号，支持 `v` 前缀 / `+build` |
| `url` / `downloadUrl` | 是 | 安装包或下载页 |
| `notes` / `releaseNotes` | 否 | 更新说明，显示在设置页 |
| `sha256` | 否 | 安装包校验；不匹配会删除文件并报错 |
| `size` | 否 | 字节数，用于提前发现下载不完整 |

## 版本比较

- `0.2.0 > 0.1.9`、`0.1.0+2 > 0.1.0+1`
- `v0.2.0` 等价于 `0.2.0`
- `0.2.0-beta < 0.2.0`
- 无法解析的版本号不触发更新

## 安全建议

- 清单和安装包都走 **HTTPS**。
- 清单里带 `sha256`，客户端下载后会校验；不匹配直接删除。
- 正式分发时 MSIX 应使用正式代码签名证书；测试证书只适合内测。
- 客户端只接受 `http/https` 链接，避免 `file://` 等本地路径。

## 代码

- `app/lib/services/update_service.dart`：清单解析、版本比较、下载、校验、启动安装。
- `app/lib/state/app_controller.dart`：`checkForUpdates` / `downloadAndInstallUpdate`。
- `app/lib/ui/panel_view.dart`：设置页「更新」卡片。
- `app/test/update_service_test.dart`：10 个单元测试（版本、清单、HTTP 错误、下载、校验）。
