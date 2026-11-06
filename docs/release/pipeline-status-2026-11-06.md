# 打包 / 发版链路状态

日期：2026-11-06（北京时间）
核对人：门房
依据：直接在工程根 `E:\Vibe Coding\zcode\三国肉鸽` 与本机 Godot 安装处查看，逐项标注命令/路径证据。

## 一句话结论

**链路没有打通，一步都还没跑过。** 当前状态是「有工程、有引擎、有一份能跑的 debug 版本」，缺导出预设、缺导出模板、缺签名证书、缺商店后台账号。距离能出一个给外部人装的 exe，还差 4 个阻断项。

## 逐项状态

| 环节 | 状态 | 证据 |
|---|---|---|
| 工程可启动 | ✅ 通 | 2026-11-04 实机跑过：主菜单→序章，Vulkan Forward+，59~60fps（`.workbuddy/memory/2026-11-04.md`） |
| Godot 引擎 | ✅ 通 | `C:\Users\58249\tools\godot\Godot_v4.7.2-stable_win64.exe` 存在；`godot.cmd` 已加入 PATH |
| 导出预设 `export_presets.cfg` | ❌ 缺 | 工程根无此文件（`ls` 报 No such file）。Godot 里没配置过任何导出目标 |
| 导出模板（export templates） | ❌ 缺 | `%APPDATA%\Godot\export_templates\` **是空目录**，无 `4.7.2.stable/` 子目录，模板未安装 |
| 版本号 / 产品信息 | ⚠️ 未定 | `project.godot` 只有 `config/name="桃源乱武"`，无 `config/version`、无公司/版权字段 |
| 图标 | ⚠️ 粗糙 | `icon.png` 仅 3071 字节（占位图级别），商店与 exe 图标都需要正式版 |
| 代码签名证书 | ❌ 缺 | 本机无任何代码签名工具/证书痕迹。Windows SmartScreen 会对未签名 exe 报「未知发布者」 |
| 分发工具 butler（itch.io） | ❌ 缺 | `which butler` 无结果 |
| Steam 上传工具 steamcmd | ❌ 缺 | `which steamcmd` 无结果 |
| 商店后台账号 | ❌ 无 | 无 Steamworks 后台、无 itch.io 项目页。**这两件只能人来做，机器人不代办对外账号** |
| 版本库状态 | ⚠️ 脏 | `git status` 有 7 个已改文件 + 多个未跟踪文件（`data/economy.json`、`scenes/city/`、`scripts/autoload/save_state.gd` 等），当前 HEAD = `86d9012`，工作区**不是**一个可打包的干净状态 |

## 阻断项（按必须先解决的顺序）

1. **导出模板没装** —— 没它 `godot --export-release` 直接失败。修法：Godot 编辑器 → 编辑器 → 管理导出模板 → 下载 4.7.2，或手动把模板包解到 `%APPDATA%\Godot\export_templates\4.7.2.stable\`。约 1~2 GB 下载，**需核实**当前网络能否直连官方源。
2. **没有 export_presets.cfg** —— 需要新增一个 Windows Desktop 预设，填产品名、版本号、图标、是否内嵌 PCK。**这一项要不要我写进工程根？** 它不属于 `scripts/ scenes/ data/ tests/ project.godot` 任何一处，但确实是新增工程文件，我按规则先问；@木匠 或人点头我再落。
3. **版本号与产品信息未定** —— 需要人拍板首发版本号（建议 `0.1.0` 起，垂直切片口径）。
4. **商店账号** —— Steam 需先交 Steam Direct 费用（金额与币种**需核实**，不凭记忆写数字）；itch.io 免费建页但审核/展示规则**需核实**。账号注册、付款、税务表格都必须人本人完成。

## 不阻断、但要排期

- 代码签名：不签也能发，代价是用户首次运行会被 SmartScreen 拦一次、需要点「仍要运行」。要不要买证书是个成本决策，建议首发 itch.io 免费试玩不签，走 Steam 时再签。
- 安装包形式：Godot 导出的是一整个文件夹或单 exe，没有安装向导。要做安装器得另配 Inno Setup 之类，首发可以先发 zip。

## 下一次推进需要人拍板的三件事

1. 首发渠道选 itch.io（免费、当天能上）还是 Steam（有门槛费、过审周期**需核实**）？我的建议见 `platform.md`。
2. 首发版本号定多少？
3. 允许我在工程根新增 `export_presets.cfg` 吗？（只加这一个配置文件，不碰其他任何工程文件）
