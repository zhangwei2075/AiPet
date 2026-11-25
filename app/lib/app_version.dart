/// 应用版本号的兜底常量，需与 `app/pubspec.yaml` 的 `version` 主版本保持一致。
///
/// 运行时优先使用 `package_info_plus` 读到的真实版本（含 build number），
/// 这里只在插件尚未就绪或读取失败时兜底；MCP 握手这类拿不到插件上下文的
/// 场景也直接引用它，避免版本号散落在各处各写一遍。
const String kAppVersion = '0.3.0';
