---
name: godot-verify
description: Use when running, testing, or exporting the 桃源乱武 Godot 4.7.2 project — the headless test suite, the two smoke scenes, the procedural asset generators, or the Windows export. Also use before claiming any change works, since it fixes the exact commands, the pass baseline, and the traps that make headless runs lie. Triggers on "跑测试", "验证一下", "run_all", "冒烟", "导出", "为什么 headless 报 Identifier not found".
---

# 桃源乱武 · Godot 验证与导出

这个工程是 Godot 4.7.2 stable + GDScript，Windows PC 单机。所有验证命令都必须带 `--path` 指向工程根，且 `--headless` 只影响渲染，不影响逻辑。

## 引擎路径

```bash
GODOT="C:/Users/58249/tools/godot/Godot_v4.7.2-stable_win64_console.exe"
```

`C:/Users/58249/bin/godot.cmd` 是同一个 exe 的封装，交互式用；**自动化脚本里直接调 console 版**，因为 cmd 封装在 Git Bash 里会吞退出码。

## 三条必跑命令

```bash
# 1. 全量自测（13 套件 / 11 表）
"$GODOT" --headless --path "E:/Vibe Coding/zcode/三国肉鸽" --script res://tests/run_all.gd

# 2. 完整一局冒烟（主菜单→序章→W1~W7→W8 真杀华雄→结算→再来一局→暂停→回主菜单）
"$GODOT" --headless --path "E:/Vibe Coding/zcode/三国肉鸽" res://tests/smoke_boot.tscn

# 3. 主城冒烟（五入口→酒馆直购→武将府升级→校场编队→1-1 出征→★3 入库→1-2 解锁）
"$GODOT" --headless --path "E:/Vibe Coding/zcode/三国肉鸽" res://tests/smoke_city.tscn
```

注意命令 1 用 `--script`（其后不接场景），命令 2/3 直接给 `.tscn` 路径。两种形态**不可混用**。

## 通过基线

| 项 | 判定 |
|---|---|
| 汇总行 | `通过 1624 / 失败 0 / 跳过套件 0` |
| 表加载 | `[DataDB] 11 表加载 + schema 校验通过。` |
| 经济闭环 | `early 0.9061`（在 `[0.8,1.5]` 带内）；`full 0.0167`（已知未达标，不阻断） |
| 冒烟 | 退出码 0 |

**基线数字会随套件增加而变。** 加套件后先跑一次记录新基线，再拿它比对——不要拿旧数字判新失败。

## 退出噪声，不是失败

`--headless` 退出时必定刷这些，**不要记成缺陷**：

```
ERROR: N RID allocations of type '...' were leaked at exit.
ERROR: 8 resources still in use at exit
WARNING: Leaked instance dependency: Bug - did not call instance_notify_deleted when freeing.
ERROR: Pages in use exist at PagedAllocator: ...
```

判失败只看：汇总行的 `失败 M`、退出码、以及 `SCRIPT ERROR`（**这个是真缺陷**）。

## 三个必踩的坑

### 1. `--script` 模式 autoload 不自动实例化

`run_all.gd` 开头有一段 `AUTOLOADS` 常量手动把六个 autoload 挂到 `/root`，因为 ProjectSettings 的 autoload 在 `--script` 模式下不会实例化。后果：

- 新测试套件若直接用 `DataDB` / `SaveState` 等全局标识符，跑 `--script` 会报 **Identifier not found**。
- `run_all.gd` 自身不得直接引用 autoload 标识符（编译早于注册）。
- 新增 autoload 时**同步更新** `run_all.gd` 的 `AUTOLOADS` 数组，否则套件全挂。

### 2. 容器遍历遇到非目标类型

`wave_director.gd` 遍历 `Units/Heroes` 与 `Units/Enemies` 读 `.dead` / `.unit_id`。容器里混进任何非 `UnitBase` 节点（历史事故：台词浮字 `Label3D`）都会 SCRIPT ERROR。约定：

- 浮字挂 `battle/VFX`，不挂单位容器。
- 遍历时加 `if u is UnitBase` 守卫。
- 同理适用于任何新增的 VFX / UI 节点。

### 3. 跨套件状态污染

`run_all.gd` 有 `_purge_suite_residue()`，但套件自己改了全局状态（`SaveState` / `RunState`）也必须兜底复位，异步复位要 `await`。历史上 `test_save.gd` 少写一个 `await` 就污染了后续套件。

## 程序化素材生成

```bash
"$GODOT" --headless --path "<工程>" --script res://tools/gen_textures.gd
"$GODOT" --headless --path "<工程>" --script res://tools/gen_audio.gd
```

固定 seed、可复现。产物登记在 `assets/textures/manifest.json`（45 条）与 `assets/audio/*.wav`。**不要往 `assets/` 放下载来的素材**（GDD §0 约束 4）。

## Windows 导出

```bash
"$GODOT" --headless --path "<工程>" --export-release "Windows Desktop" "build/windows/SanGuoRogue.exe"
```

前置条件：
- 导出模板必须在 `%APPDATA%\Godot\export_templates\4.7.2.stable\`，缺了整个导出会失败。
- `export_presets.cfg` 已存在于工程根（预设名 `Windows Desktop`）。
- 导出**后必须实跑产物**，不能只在工程目录里跑。

## 实机启动（看画面、截图）

```bash
"$GODOT" --path "<工程>" --resolution 1920x1080
```

必须用后台常驻任务拉起——`Start-Process` 拉起的窗口会随命令结束被回收。4K 屏 + 150% DPI 环境下做窗口自动化时，先调 `SetProcessDPIAware()`，物理坐标 = 逻辑 × 1.5（见 `.workbuddy/memory/2026-11-04.md`）。

已知 GPU 问题：RX 5700 XT + Vulkan 长时间空闲会出现 `Vulkan device was lost`（退出码 132）。不可稳定复现，判为驱动层 TDR，非脚本缺陷。缓解：窗口降到 1920×1080、别长时间停在波间弹窗。

## 数据表清单（11 张）

`palette / heroes / enemies / waves / relics / upgrades / events / shop / economy / campaign / tower`

由 `scripts/autoload/data_db.gd` 的 `TABLE_NAMES` 加载，启动时 `_validate_all()` 校验。加新表要同时改：`TABLE_NAMES`、加载语句、`_validate_*()`、查询器、启动日志的表数字。
