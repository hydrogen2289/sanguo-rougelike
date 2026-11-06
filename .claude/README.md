# 角色名册 ·《桃源乱武》

六个子代理，覆盖「实现 → 数值 → 验收 → 美术 → 发版 → 文档」闭环。花名沿用 `docs/` 里已有的 `@木匠` / `@秤砣` / `@门房`，保证文档里的 @ 指向不失效。

## 名册

| 代理 ID | 花名 | 职责 | 明确不做 | 色 |
|---|---|---|---|---|
| `godot-engineer` | 木匠 | GDScript / `.tscn` / autoload / 战斗与 UI 实现、修 bug、补测试 | 不改 `data/`、不碰发版配置 | 蓝 |
| `balance-designer` | 秤砣 | `data/*.json` 数值、关卡与塔层参数、经济曲线审计 | 不写 `.gd`、不碰美术与发版 | 绿 |
| `qa-verifier` | 验收员 | 只读验收：跑全量 + 双冒烟、文档逐条对账、发版门禁 | **不写任何文件**，只报 | 黄 |
| `art-director` | 丹青 | 光照/tonemap、程序化贴图、低模表现、`palette.json`、商店截图 | 不下载素材、不改数值逻辑 | 品红 |
| `release-manager` | 门房 | 导出预设、打包、版本元信息、许可与合规、itch.io 材料 | **不注册账号、不付款**（人做） | 红 |
| `design-writer` | 撰文 | GDD/技术方案同步、README、商店文案 | 不改代码与数据 | 青 |

**为什么没有 orchestration 代理**：子代理不能派子代理，编排留在主 Agent。

## Skill 分配

| 代理 | Skill | 用途 |
|---|---|---|
| 全部 | `.claude/skills/godot-verify`（项目内） | 命令、基线、三个坑 |
| 木匠 | `superpowers:test-driven-development` | 先写断言再实现 |
| 木匠 | `superpowers:systematic-debugging` | 查因不猜 |
| 木匠 | `superpowers:using-git-worktrees` | 大改动隔离 |
| 全部改完 | `superpowers:verification-before-completion` | 没有实测输出不许说通过 |
| 验收员 | `code-review` / `run` | 代码审查与实跑 |
| 丹青 | `open-design:color-expert` | 色彩科学、对比度 |
| 丹青 | `open-design:shader-dev` | 着色器技巧（GLSL → Godot Shading Language 需转写） |
| 丹青 | `open-design:design-review` | 视觉审计 |
| 门房 | `security-review` | 发版前扫描 |
| 门房 | `open-design:copywriting` | 商店文案 |
| 撰文 | `open-design:writing-guidelines` | 文字打磨 |
| 撰文 | `superpowers:brainstorming` | 新文档构思 |
| 秤砣 | — | 市场无对口 skill，靠 `test_balance_sim` + 公式 |

## 明确不装

| 插件/Skill | 原因 |
|---|---|
| `unity` | 官方 Unity 插件，本工程是 Godot |
| `unreal-engine-skills-for-claude-code` | 同上 |
| `fal-generate` / `imagegen` / `fal-3d` 等生成类 | 与 GDD §0 约束 4「不下载外部素材、全部程序化生成」直接冲突 |

官方市场共 462 个插件，**没有 Godot 专项插件**——工程能力只能靠自建代理 + 项目内 skill，这也是 `godot-verify` 存在的原因。

## 调用示例

```
用 godot-engineer 把 stage_select / squad_edit / tavern / hero_up 四个子面板拆成独立 .tscn
用 balance-designer 审一下塔 20 层以后的难度曲线
用 qa-verifier 验收当前这版能不能发
用 art-director 修战斗画面中心过曝
用 release-manager 出一版 0.1.0 的 Windows 分发包
用 design-writer 把 impl-status 更新到今天
```

## 硬规则（所有代理共用）

1. **越界即返工**：木匠不改数值、秤砣不写代码、验收员不落盘、门房不注册账号。
2. **证据优先**：任何「已实装 / 已修复 / 已通过」必须带 `ls` / `grep` / 测试原文行。
3. **落盘纪律**：临时产物进 `_scratch/`，长期归档进 `_bak_archive/`；绝不写盘符根、用户主目录根、桌面根。
4. **外部事实标「需核实」**：费率、周期、法律条款不凭记忆写。
