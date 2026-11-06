# 《桃源乱武》· 项目工作规则

三国题材「局外养成 × 组队推图 × 肉鸽爬塔」三层数值循环游戏。Godot 4.7.2 stable + GDScript，Windows PC 单机。

- 设计依据：[docs/01-设计文档.md](docs/01-设计文档.md)（GDD）
- 技术契约：[docs/02-技术方案.md](docs/02-技术方案.md)
- 两者冲突时由人裁决，不擅自改任一边迁就另一边。

## 角色分工

六个子代理，定义在 `.claude/agents/`。详见 [角色名册](.claude/README.md)。

| 代理 | 花名 | 归它管 |
|---|---|---|
| `godot-engineer` | 木匠 | `scripts/` `scenes/` 实现与修 bug |
| `balance-designer` | 秤砣 | `data/*.json` 数值、关卡与塔层参数 |
| `qa-verifier` | 验收员 | 只读验收，不落盘 |
| `art-director` | 丹青 | 光照、程序化贴图、低模、`palette.json` |
| `release-manager` | 门房 | 导出、打包、合规、商店材料 |
| `design-writer` | 撰文 | `docs/` 文档与对外文案 |

**分派原则**：写的人和验的人不同源。木匠写完，验收员验。

## 测试门禁（硬性）

改动 `scripts/` `scenes/` `data/` `tests/` 后**必跑**三条命令，全绿才算完成：

```bash
GODOT="C:/Users/58249/tools/godot/Godot_v4.7.2-stable_win64_console.exe"
"$GODOT" --headless --path "E:/Vibe Coding/zcode/三国肉鸽" --script res://tests/run_all.gd
"$GODOT" --headless --path "E:/Vibe Coding/zcode/三国肉鸽" res://tests/smoke_boot.tscn
"$GODOT" --headless --path "E:/Vibe Coding/zcode/三国肉鸽" res://tests/smoke_city.tscn
```

- 基线：`通过 1624 / 失败 0 / 跳过套件 0`，`[DataDB] 11 表加载 + schema 校验通过`
- 退出时的 RID / ObjectDB / PagedAllocator 泄漏**是噪声，不记失败**
- `SCRIPT ERROR` **是真缺陷**
- 详细命令与三个已知坑见 `.claude/skills/godot-verify/SKILL.md`

**没有实测输出，不许说「通过」「已修复」。**

## 硬约束（来自 GDD §0，不可协商）

1. 战斗核心一套代码，闯关与塔共用（WASD 走位 + 自动普攻 + 数字键技能）。
2. 肉鸽塔奖励必须经 `scripts/meta/reward_settle.gd` 入跨局存档，闭环成立。
3. **平台仅 Windows PC 单机。** 小游戏平台属「另议」，任何文档与对外表述不得写成既定路线。
4. **禁止下载外部素材或 addon。** 贴图音频全程序化生成（固定 seed 可复现），走 `tools/gen_textures.gd` / `tools/gen_audio.gd`。
5. 伪 3D：真 3D 场景 + 程序化低模小人 + 斜俯视相机。
6. 现有 8 波肉鸽内容不废弃，整体属于试炼塔层。
7. 未拍板的细节（抽卡规则、席位细节等）在文档里标「提案待拍板」，不得写成已定。

## 领域边界

- **数值只归秤砣。** `data/*.json` 的任何数字改动都必须走 `balance-designer`，木匠改了要返工。
- **文档只归撰文。** 代码与文档不一致时报冲突，不擅自改文档。
- **发版只归门房。** `export_presets.cfg`、版本号、打包脚本。
- **验收员不写文件。** 它只产出报告。

## 落盘纪律

1. 产物只写入用户或任务卡明确指定的目录。
2. 临时/中间产物放 `_scratch/`；长期保留放 `_bak_archive/`。
3. **永远禁止写**：盘符根目录（`E:\`、`C:\`）、用户主目录根（`C:\Users\58249\`）、桌面根、系统目录。
4. 写盘后主动报告实际路径。

## 已知欠账（别当新发现）

| 项 | 状态 |
|---|---|
| 长线经济不闭环（full 轴 0.0167，差两个数量级） | 内容深度不足，属拍板项 |
| 三个子面板未拆 `.tscn`（脚本层已实装） | 形态欠账 |
| `DataDB.economy()` 查询器不存在 | API 契约欠账 |
| §10 增量贴图未落地 | 美术欠账 |
| 战斗画面中心过曝 | 美术风格决策，未修 |
| 开场视频来源不明 | **发版阻断项**，见 `docs/release/assets-license.md` |
| `build/windows/` 为空，从未成功导出 | 发版阻断项 |

## 外部事实

渠道费率、审核周期、提交费、法律条款一律标 **需核实**，不凭记忆写数字。这是本工程文档的既定口径。
