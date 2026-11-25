# 简讯订阅（Watch）

> 解决的是「让智能体自己做财联社插件，定期通知我股票 / 光模块 / 光通信 / AI 消息」
> 这类需求。在此之前这类请求必定失败 —— 不是提示词的问题，而是代码里既没有
> 「插件」机制，也没有周期任务，模型只能在项目里翻目录，翻到轮次耗尽。

## 1. 为什么不是「让模型自己写插件」

| 做法 | 结果 |
| --- | --- |
| 模型写脚本 + 让 Windows 计划任务调度 | 没有去重、没有关键词过滤、出错没人管；`schtasks` 还在沙箱黑名单里 |
| 模型改项目源码加功能 | 需要重新编译，桌宠正在跑，改完也不会热生效 |
| **数据驱动的订阅（本方案）** | 源 + 关键词 + 间隔三个字段，模型一次工具调用即生效，调度与去重都在进程内 |

结论：把「可变部分」收敛成配置，把「不变部分」（抓取、去重、调度、通知）做成内置能力。
模型负责理解主人要什么，不负责造轮子。

## 2. 数据结构

```dart
Watch {
  id, name,
  source: WatchSourceKind.cailianshe,   // 源
  keywords: List<String>,               // 空 = 全量推送
  intervalMinutes: int,                 // 最小 5
  enabled: bool,
  createdAt, lastRunAt, lastError,
  seenIds: List<String>,                // 已推送条目，滚动 300 条
  pushCount: int,
}
```

持久化：`shared_preferences` key `agent.watches.v1`，JSON 数组。

## 3. 财联社接口

```
GET https://www.cls.cn/v1/roll/get_roll_list
  ?app=CailianpressWeb&category=&last_time=&os=web&refresh_type=1&rn=30&sv=8.4.6
  &sign=<签名>
```

签名算法：`md5(sha1(urlencode(按 key 排序的 query)))`

实测对照（同一个 query）：

| 算法 | 结果 |
| --- | --- |
| `sha1(query)` | `errno 10012 签名错误` |
| `md5(query)` | `errno 10012` |
| `sha1(md5(query))` | `errno 10012` |
| **`md5(sha1(query))`** | `errno 0`，返回 `data.roll_data` |

字段映射：`id`、`ctime`（秒）、`title`、`brief`、`subjects[].subject_name`、`shareurl`。
部分条目没有 `title`，从 `brief` 的 `【…】` 里补；再没有就取首行截断。

> 页面本身是纯 SPA（`__NEXT_DATA__` 里只有 `initialState.chooseNav`），拿不到 SSR 数据，
> 只能走接口，所以必须把签名算对。

## 4. 网络：直连优先，代理回落

`WatchFetcher` 先用 `HttpClient()..findProxy = (_) => 'DIRECT'` 建 `IOClient`，
失败再回落到系统代理。

原因：Windows 上 Dart 的 `HttpClient` 会读环境变量代理，这台机器的代理已经 502，
不显式 DIRECT 的话每次抓取都失败，看起来像「功能没做完」。
反过来，公司网必须走代理的环境，回落分支也能覆盖。

## 5. 调度与去重

```
每分钟 tick → 遍历启用的订阅 → 到期（now - lastRunAt >= interval）
  → 抓取 → 新条目 = 不在 seenIds 里的
  → 首次：取最新 12 条里的命中项（刚开通就刷一屏历史太吵，只看 1 条又常不命中）
  → 之后：全部新条目
  → 命中关键词 → 气泡通知 + 写入记忆（tag: watch）
  → seenIds 落盘（滚动 300）
```

- 抓取失败只写 `lastError`，下一次照常重试，不弹气泡（网络抖动不该骚扰主人）。
- 每条跑完立刻落盘，中途崩溃不会重复推送。
- `pump()` 有 `_busy` 互斥，不会并发打接口。

关键词匹配规则：中文直接 `contains`；纯 ASCII 且长度 ≤ 8 的（`AI`、`GPU`、`CPO`）按词边界，
避免 `AI` 命中 `paid`。

## 6. 工具（模型可直接调用）

| 工具 | 作用 |
| --- | --- |
| `watch_create` | 开通订阅；`name` + `keywords[]` + `intervalMinutes`。开通即抓一次 |
| `watch_list` | 列出订阅、间隔、上次运行、上次错误 |
| `watch_run` | 立刻抓一次（不看间隔），验证通不通 |
| `watch_delete` | 按名称或 id 删除 |

`watch_create` 的返回里带「试抓成功，本次拿到 N 条、命中 M 条」，模型据此判断是否真的通了，
而不是空口说「已开通」。

## 7. 界面

设置 →「简讯」分组（`ui/watch_section.dart`）：

- 每行：名称 + 源标签 + 「关键词 · 每 N 分钟 · 上次 X」+ 立刻抓 / 开关 / 删除
- 空态给一句可以直接照着说的话：「订阅财联社，关注光模块、光通信和 AI」
- 「新建订阅」对话框：名称、关键词（逗号/空格分隔）、间隔

## 8. 已知边界

- 只接了财联社电报一个源；加源 = 加一个 `WatchSourceKind` + 一个解析器。
- 通知走气泡 + 记忆，没有系统级通知（托盘通知需要额外插件）。
- 关键词是字面匹配，不做同义词扩展（「光模块」不会命中「光器件」）。
- 依赖进程存活：桌宠退出后不再抓取（与自主循环一致，没有独立后台服务）。
