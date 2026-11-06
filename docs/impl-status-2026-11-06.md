# ★新增 节点落地盘点（2026-11-06）· v2 刷新

盘点范围：`docs/02-技术方案.md` §2 目录树中标「★新增」的 18 个节点，外加各章节正文中标「★新增」但未进目录树的实现项（§4.2 / §6.2 / §8.2 / §8.3 / §8.4 / §10 / §12.2）。
判定口径：以 `ls` 与 `grep` 实测为准，不采信文档措辞。状态三态：**已实装** / **部分** / **未落地**。

> **刷新说明（2026-11-06 21:40，本版为 v2）**
> 本文件首版盘点于当日 **02:17**，当时 M9/M10/M11 尚未落盘。此后 03:12~21:03 之间三条主线全部完成，本版按实测重判。
> **v1 的历史结论（18 节点 已实装 6 / 部分 3 / 未落地 9）已不成立，勿再引用**；如需追溯，见 `git log` 与 `docs/qa/baseline-2026-11-06.md`（该文件是 86d9012 基线，属历史快照，**不回改**）。
> 本版基线：`run_all.gd` 实测 **通过 1624 / 失败 0 / 跳过套件 0**（2026-11-06 21:45，**13 套件 / 11 表**），两个冒烟（`smoke_boot` / `smoke_city`）退出码 0。
> 复跑命令见文末 §五。

---

## 一、目录树 18 个 ★新增 节点（v2 实测）

| # | 节点路径 | 状态 | 证据（v2 实测） | 依赖谁 |
|---|---|---|---|---|
| 1 | `data/campaign.json` | **已实装** | 14118 B，`chapters[0]=ch1「桃园篇」` 含 8 关（1-1 初起涿郡 … 1-8 虎牢·华雄，`boss_stage=true`），每关带 `waves[]`（1-3 波）/`first_clear`/`repeat_clear`/`rec_power`/`unlock_after`。`data_db.gd:56` 加载、`:541 _validate_campaign()` 校验、`:134 stage_by_id` / `:144 chapter_list` 查询。`test_campaign.gd`（323 行 / 92 断言）覆盖。 | 秤砣出关卡表数值；已接 DataDB |
| 2 | `data/tower.json` | **已实装** | 667 B：`floors_ref{from:1,to:8,source:"waves.json"}`、`gen_from:9`、`boss_every:8`、`gen{base_hp/base_atk/count/batch_n/enemy_pool/elite_from_floor/ranged_ratio}`、`boss_pool:["huaxiong"]`。`data_db.gd:57` 加载、`:647 _validate_tower()`、`:157 tower_floor(n,seed)` / `:169 tower_is_boss_floor` 查询。 | 秤砣出塔层参数；已接 DataDB |
| 3 | `data/economy.json` | **已实装** | 1050 B，含 level/star/star_up_cost/recruit/rarity/item_price/settle；`data_db.gd:55` 加载、`:466 _validate_economy()` 校验锚点齐全。 | 秤砣（数值表）；已完成 |
| 4 | `scenes/city/main_city.tscn` | **已实装** | 55 行，节点齐备：`MainCity` / `CityBg` / `TopBar` / `HubButtons` / `SubPanelHost`，与 §6.2 四节点一一对应。`test_save.gd` 实例化断言「主城五入口可见」。 | 本工程（M7）；已完成 |
| 5 | `scenes/ui/stage_select.tscn` | **部分** | `.tscn` 不存在；脚本 `scripts/ui/stage_select.gd` **已实装**（174 行，含 `signal stage_chosen` / `_rebuild()` / `_build_chapter()` / `_on_claim_box()` / `_stage_row()`），由 `main_city.gd:105 _open_stage_select()` 代码 `new()` 后挂进 `SubPanelHost`，不走场景文件。 | 本工程（M9）；脚本层已达 |
| 6 | `scenes/ui/squad_edit.tscn` | **部分** | `.tscn` 不存在；`scripts/ui/squad_edit.gd` 已实装（186 行，`setup(confirm)` / `signal confirmed(slots)`），`main_city.gd:123` 挂载，战役/塔两入口共用。 | 本工程（M8）；脚本层已达 |
| 7 | `scenes/ui/tavern.tscn` | **部分** | `.tscn` 不存在；`scripts/ui/tavern.gd` 已实装（153 行，程序化建 PanelContainer 货架），`main_city.gd:86 _open_panel()` 加载。 | 本工程（M8）；脚本层已达 |
| 8 | `scenes/ui/hero_up.tscn` | **部分** | `.tscn` 不存在；`scripts/ui/hero_up.gd` 已实装（174 行），`main_city.gd:88 _open_panel()` 加载。 | 本工程（M8）；脚本层已达 |
| 9 | `scenes/ui/reward_result.tscn` | **已实装（形态差异）** | 未新建独立场景，按 §6.2/§11 原意**改造** `scenes/ui/result.tscn` + `scripts/ui/result.gd`（184 行）：`open(is_victory, stats, settle)` 渲染 `settle.items` 奖励清单（「本局收获」区块，`:64/:107`），前端不重算。`test_reward.gd:324 _test_result_page()` 覆盖。 | 本工程（M11）；已完成 |
| 10 | `scripts/autoload/save_state.gd` | **已实装** | 397 行；`project.godot:21` 注册为第 2 个 autoload。原子写 tmp→rename、`.bak` 单级回滚、`migrate()`、`normalize()`、`validate()` 全部到位（`:102/:149/:196/:218/:276`）；写入口 `add_junzi`/`try_spend_junzi`/`add_fragments`/`mark_prologue_seen`。`test_save.gd`（77 断言）覆盖往返/坏档/迁移/幂等/校验/删档。 | 本工程（M7）；已完成 |
| 11 | `scripts/meta/hero_save.gd` | **已实装** | 224 行，`class_name HeroSave`。等级/星级曲线、升级升星、直购/合成招募、编队校验、席位扩容全部实现（`star_cost:44`）。已接进战斗层（`unit_base.gd` 读 `HeroSave.factors`）。`test_meta.gd`（121 断言）覆盖。 | 本工程（M8）；已完成 |
| 12 | `scripts/meta/campaign_save.gd` | **已实装** | **247 行**（v1 时判「未落地」）。API：`ensure_progress:24` / `is_unlocked:96` / `chapter_stars:107` / `calc_stars:115` / `settle_stage:154`（首通/重复/解锁写入）/ `claim_box:215`（3/6/9 星宝箱，幂等）。`test_campaign.gd` 覆盖评星/宝箱/解锁/失败零奖励。 | 本工程（M9）；已完成 |
| 13 | `scripts/meta/tower_save.gd` | **已实装** | **74 行**（v1 时判「未落地」）。`highest_floor:17` / `next_floor:27` / `floor_cap:30` / `is_boss_floor:35` / `record_floor:42`（只增不减）/ `record_kills:61`。`test_tower_gen.gd:259 _test_tower_save()` + `test_tower_climb` 端到端覆盖。 | 本工程（M10）；已完成 |
| 14 | `scripts/meta/reward_settle.gd` | **已实装** | **173 行**，`class_name RewardSettle`。`settle(mode, outcome):31` / `settle_campaign:42` / `settle_tower:79`；阵亡 `death_mult`、撤退 `retreat_mult` 互斥折算；返回 `items` 清单供结算页。全仓唯一入库管道（`wave_director.gd:432 _settle()` 接它）。`test_reward.gd`（59 断言，含真战斗场景端到端）覆盖。 | 本工程（M11）；已完成 |
| 15 | `scripts/meta/tower_wave_gen.gd` | **已实装** | **271 行**，`class_name TowerWaveGen`。`generate(floor, gen_seed):31` / `_build_normal:51` / `_build_boss:120` / `_distribute:195` / `_validate_and_return:251`；同 seed 可复现、难度单调、Boss 层排程。`test_tower_gen.gd`（32 断言，含 100 层契约校验）覆盖。 | 本工程（M10）；已完成 |
| 16 | `tests/test_save.gd` | **已实装** | 77 断言，11 个测试组；`run_all.gd:30` 注册。**v1 记录的跨套件污染 bug 已修**（`test_save.gd:28` 已补 `await`；`test_campaign.gd:227 _find_hub_button` 已改子树查找；`run_all.gd` 已有 `_purge_suite_residue()`）。 | 巡检可复用 |
| 17 | `tests/test_meta.gd` | **已实装** | 121 断言。**经济闭环带宽断言已落地**（`test_meta.gd:386`，见 §二）；full 轴如实打印不硬卡。 | 巡检可复用 |
| 18 | `tests/test_tower_gen.gd` | **已实装** | 32 断言：表/确定性/100 层契约/单调/Boss 层/ref 层/拒绝路径/塔层推进。`run_all.gd:32` 注册。 | 巡检可复用 |

**统计（v2）：18 个节点中 已实装 15 / 部分 3 / 未落地 0。**
（v1 为 已实装 6 / 部分 3 / 未落地 9。）

> 备注：3 个「部分」全部是同一类形态差异——**脚本层已实装、未拆独立 `.tscn`**，UI 由 `main_city.gd` 在 `SubPanelHost` 内 `new()` 程序化挂载。这是 §6.2「单场景内切换、不换场景」的原意，不是缺失；但**与目录树里写的 `.tscn` 路径不一致**，目录树已同步改写（见 02 §2）。

---

## 二、正文里标 ★新增、但未进目录树的实现项（v2 实测）

| 项 | 章节 | 状态 | 证据（v2 实测） | 依赖谁 |
|---|---|---|---|---|
| DataDB 扩表（11 表） | §4.2 | **已实装** | `data_db.gd:39 TABLE_NAMES` 列 11 表；`:55-57` 加载 economy/campaign/tower；`:203 _validate_all()` 已含 `_validate_economy/:466`、`_validate_campaign/:541`、`_validate_tower/:647`；启动日志实测打印「**11 表加载 + schema 校验通过**」。`test_data.gd` 41 断言。 | 已完成 |
| DataDB 查询器 `stage_by_id/chapter_list/tower_floor` | §4.2 | **已实装** | `data_db.gd:134 stage_by_id` / `:144 chapter_list` / `:157 tower_floor(n, seed)` / `:169 tower_is_boss_floor`。 | 已完成 |
| DataDB 查询器 `economy()` | §4.2 | **部分** | **`func economy()` 不存在**（`grep` 零命中）。economy 仍是裸 `var economy: Dictionary`（`data_db.gd:17`），各模块直接读 `DataDB.economy.settle`。功能可用，但**与 §4.2 写的查询器契约不一致**，为唯一的 API 形态欠账。 | 本工程（低优，非阻断） |
| `scripts/ui/stage_select.gd` | §6.2 | **已实装** | 174 行；主城战役入口 `main_city.gd:81 _open_stage_select()` → 选关 → `_on_stage_chosen` → 编队确认 → `SceneRouter.goto_stage(sid)`。**硬编码 `"1-1"` 已降级为三级兜底**（`main_city.gd:130-135`：`_pending_stage` → `first_unlocked_stage()` → 才回落 `"1-1"`），正常路径由选关页指定。 | 已完成 |
| RunState 模式上下文 `mode` / `context` | §8.1 | **已实装** | `run_state.gd` 两字段 + reset 归位 + `dump()` 带出；`test_save.gd` 有断言。 | 已完成 |
| SceneRouter 三层路由 `goto_city/goto_stage/goto_tower` | §7 | **已实装** | `scene_router.gd:61 goto_stage` **已读关卡表**：坏 id `stage_by_id().is_empty()` 直接 `printerr` + 返回 false 不切场景；合法 id 经 `prepare_campaign` 注入 `{stage_id, wave_total}`（`:75`，`wave_total` 由表带出）。`test_campaign.gd:311` 覆盖坏 id 拒绝 + 上下文不变。 | 已完成 |
| 主菜单改造「进入主城」 | §7 | **已实装** | `main_menu.gd:116 SceneRouter.goto_city()`；坏档横幅 `_on_city_enter_failed`；塔入口保留为调试快捷键。 | 已完成 |
| wave_director 波次双源 `_load_wave(idx)` | §8.2 | **已实装** | `wave_director.gd:58 _load_wave(idx)`：campaign → `_campaign_waves()` 读关卡表；tower → `DataDB.tower_floor(idx, tower_seed())`（同 run_seed 可复现）；旧路径保留 `DataDB.wave(idx)`。另有 `_wave_total()` / `_is_boss_wave()` 按模式分支。`test_campaign.gd:300` 断言「1-3 W1 主题=重锤压阵，非塔剧本」。 | 已完成 |
| `TowerWaveGen.generate()` 契约 | §8.3 | **已实装** | 见 §一 #15。`test_tower_gen.gd` 100 层全量契约校验 + `test_tower_climb.gd` 真场景连爬 12 层（含第 8 层 Boss、9+ 层切生成器）。 | 已完成 |
| `RewardSettle.settle()` 统一管道 | §8.4 | **已实装** | 见 §一 #14。`wave_director.gd:432 _settle()` 为战斗层唯一出口，旧直连入库块已删。`test_reward.gd` 断言「入库额 == 清单额」「局内军资不入库（存档 roster/purse JSON 全等）」。 | 已完成 |
| §10 增量贴图 `city_panorama / icons/cur / icons/build/* / ui/star` | §10 | **未落地** | 四个代表性路径逐个 `ls` 均不存在：`assets/textures/city_panorama.png` MISS、`icons/cur/` MISS、`icons/build/` MISS、`ui/star.png` MISS；`icons/` 只有 `coin.png` + `relics/` + `skills/`；`manifest.json`（45 条）无任何 `build/` 条目。主城现用 `city_bg.gd` 的 `_draw()` 程序化绘制顶替、入口图标由 `proc_icon.gd` 运行时生成。 | 本工程 + 验收（`test_textures` 需同步扩 manifest 断言） |
| §12.2-4 三层路由 / 结算折算扩展 | §12.2 | **已实装（落在别的套件）** | 断言不在 `test_flow.gd`（该文件对 `goto_stage/goto_tower/campaign` 仍零命中），但覆盖已存在：三层路由与选关链路在 `test_campaign.gd:285-315`（真路由进 battle + stage_id 注入 + 坏 id 拒绝）；撤退 1.0 / 阵亡 0.5 折算与「局内军资不入库」在 `test_reward.gd:147-177`（真战斗场景端到端）。**分布与 §12.2 写的归属不符，已同步改写 §12.2。** | 已完成 |
| §12.2-2 经济闭环带宽断言 | §12.2 | **部分（已落地但只覆盖可玩窗口轴）** | `test_meta.gd:386` 断言 `early_ratio ∈ [0.8,1.5]` **通过**（实测 0.9061）。但 **full 轴（三人组 L1→30）实测比值 0.0167，未达带宽且没有断言**，仅 `print` 提示：「campaign.json 仅 1 章，产出侧封顶」。即：**闭环在「首章 + 招 1 稀有将 + 三人组 L1→5」窗口成立；在长线（L30 / 满星）不成立**。这是内容深度 vs 养成深度的数量级差，**属数值/内容排产，不是实现缺陷**（详见 `docs/balance-audit-2026-11-06.md`）。 | 秤砣（补章节或调 `economy.level.cost_base/cost_exp`）；口径待拍板 |

---

## 三、结论（v2）

- 第二棒五个里程碑：**M7 / M8 / M9 / M10 / M11 在代码层全部落盘**，三条主线（关卡表→选关→闯关波次）、（塔表→随机波次→塔层推进）、（结算管道→奖励页）**均已成链并有端到端测试**。
- 全量自测 **1624 / 0 / 0（13 套件）**，两个冒烟退出码 0。v1 记录的 `test_campaign` 跨套件污染失败**已修复**。
- 剩余欠账只有三类，**都不阻断主流程**：
  1. **三个子面板未拆 `.tscn`**（脚本层已实装，程序化挂载）——形态欠账，非功能缺失。
  2. **`DataDB.economy()` 查询器未实现**（裸 var 可读）——API 契约欠账，低优。
  3. **§10 增量贴图未落地**（主城底图/货币图标/入口图标/评星图仍为程序化占位）——美术增量，非阻断。
- **唯一实质性的未达标项是长线经济**：full 轴 0.0167 距 [0.8,1.5] 差两个数量级。它需要的是**内容量或曲线口径拍板**，不是写代码。

## 四、M9/M10/M11 三件大事的收口状态

| 里程碑 | v1 判定 | v2 实测 | 关键证据 |
|---|---|---|---|
| M9 组队闯关 | 未开工 | **代码完成** | `data/campaign.json`(8 关) + `campaign_save.gd`(247 行) + `stage_select.gd`(174 行) + `wave_director._load_wave` 双源 + `test_campaign.gd`(92 断言) |
| M10 试炼塔转型 | 未开工 | **代码完成** | `data/tower.json` + `tower_wave_gen.gd`(271 行) + `tower_save.gd`(74 行) + `test_tower_gen.gd`(32) + `test_tower_climb.gd`(16，真连爬 12 层) |
| M11 闭环与平衡 | 未开工 | **管道完成，平衡未达标** | `reward_settle.gd`(173 行) + `result.gd` 奖励清单 + `test_reward.gd`(59)；带宽 early 0.9061 过 / full 0.0167 未过 |

---

## 五、复跑命令（v2 基线）

```text
"C:/Users/58249/bin/godot.cmd" --headless --path "E:\Vibe Coding\zcode\三国肉鸽" --script res://tests/run_all.gd
"C:/Users/58249/bin/godot.cmd" --headless --path "E:\Vibe Coding\zcode\三国肉鸽" res://tests/smoke_boot.tscn
"C:/Users/58249/bin/godot.cmd" --headless --path "E:\Vibe Coding\zcode\三国肉鸽" res://tests/smoke_city.tscn
```

预期：`通过 1624 / 失败 0 / 跳过套件 0`，`[DataDB] 11 表加载 + schema 校验通过`，闭环两行 `full 0.0167` / `early 0.9061`。
退出时 RID/ObjectDB 泄漏为 `--headless` 退出清理噪声，不记失败。
