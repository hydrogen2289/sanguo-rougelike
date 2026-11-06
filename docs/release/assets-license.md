# 素材授权核对

日期：2026-11-06
核对人：门房
核对方式：逐目录 `ls` + 读生成脚本 + 查 git 跟踪状态。不采信文档措辞。

## 结论

**大部分素材确实是程序化生成，无第三方风险。但有一处「理论上无风险」的说法不成立——开场视频不在这套程序化管线里，来源不明，我把它标红。**

---

## 🔴 红标：开场视频 `assets/opening/taoyuan_intro.*`

| 文件 | 大小 | 是否入库 | 问题 |
|---|---|---|---|
| `assets/opening/taoyuan_intro.mp4` | 37,406,986 B（约 35.7 MB） | ✅ 已入库 | 来源不明 |
| `assets/opening/taoyuan_intro.ogv` | 10,577,154 B（约 10 MB） | ✅ 已入库 | 由 mp4 转码而来 |

**为什么标红：**

1. `tools/` 下只有 `gen_audio.gd` 和 `gen_textures.gd` 两个生成器，**没有任何视频生成脚本**。这两个文件不是程序化产物。
2. 全仓 `grep 即梦|dreamina|可灵|runway|sora|vidu|生视频|图生视频` 在 `docs/` 与 `.workbuddy/` **零命中**——没有任何地方记录过这两段视频是怎么来的。
3. mp4 内嵌元数据显示编码器为 `Lavc60.31.102 libx264` / `Lavf60.16.100`，即经 ffmpeg 转码。这只能说明转码工具，说明不了原始画面版权。
4. 关联的文件 `vibe_images/` 下 5 张关键帧 PNG（`taoyuan_keyframe_01_scroll_*` 等）和 `vibe_videos/` 下 6 段 mp4（`taoyuan_clip_01_scroll_*` 等），文件名带时间戳与 8 位 hash，**命名模式符合 AI 生成工具的输出规范，但工具与账号我无法从工程内确认**。
5. `vibe_images/` 已入库到 git（`git ls-files` 可见）。`vibe_videos/` 被 `.gitignore` 排除，但**文件在本机磁盘上存在**，打包时若按目录拷贝会带进去。

**这不必然是问题**——如果这些是用户自己用 AI 工具生成、且该工具的服务条款允许商用，那就没问题。但**工程里没有任何一份记录能证明这一点**，而它已经在 git 里、会被打进发行包。

**必须做的事（需要人回答）：**

- 这两段视频是用什么工具生成的？哪个账号？
- 该工具的商用授权条款允许把它嵌进商业发行的游戏吗？（多数 AI 视频工具的免费档**不允许商用**，付费档才允许，且条款各不相同——**需核实具体条款**）
- 如果无法确认，处置方案有两个：
  - **A**：从发行包里移除 `assets/opening/`，游戏会走 `prologue.gd` 的卷轴对话卡回退（`scripts/ui/prologue.gd:6-7` 已实现该回退，缺视频不影响启动）。代价是开场表现力下降。
  - **B**：重新用可确认授权的工具生成一段。

**在来源确认之前，这两段视频不得进入任何对外发行包。** 这是阻断项。

---

## ⚠️ 黄标：字体

`scripts/ui/ui_theme.gd:5`

```
const FONT_STACK := ["Microsoft YaHei", "SimHei", "Noto Sans CJK SC"]
```

走 Godot `SystemFont`，即**运行时读取玩家系统里的字体，不打包字体文件**。

- **不打包 = 不构成再分发**，这一点是安全的。
- **但风险是**：`Microsoft YaHei` 与 `SimHei` 是 Windows 自带的微软/中易专有字体。如果玩家在 Steam Deck（Linux）或任何没有这些字体的机器上运行，`SystemFont` 会回退到 `Noto Sans CJK SC`——而多数 Linux 发行版**也不预装** Noto CJK 完整字重。结果是**中文全部变方块**。
- 这不是授权问题，是**发行可用性问题**，但同样会卡住上线。

**建议**：首发前打包一款开源中文字体（SIL OFL 授权的思源黑体 / Noto Sans SC 之类），作为 fallback 内嵌。**代价**：包体增加约 5~15 MB（取决于字重与是否子集化），需要改 `project.godot` 的 theme——**这属于工程侧，交 @木匠**。

注意：这需要**改工程代码/配置**，不在我的权限内。我只列问题。

---

## ✅ 已核实无风险的素材

### 贴图（45 个文件）

- 全部由 `tools/gen_textures.gd` 生成，`assets/textures/manifest.json` 记录每个文件的 `seed`、`w`、`h`，共 45 条。
- 每个条目都有确定性的随机种子，可复现。
- 无任何外部下载素材。

### 音频（16 个文件）

- `ls assets/audio/*.wav` = 16 个文件。
- `grep -cE '_gen\("[a-z_]+\.wav"' tools/gen_audio.gd` = **16**，与磁盘文件数**完全对上**。
- 由 `tools/gen_audio.gd` 合成（噪声脉冲、扫频、琶音等），全部程序化。

### 着色器（3 个）

`eastwind_tint.gdshader`、`ground_fade.gdshader`、`hit_flash.gdshader`——项目自写，无外部来源。

### 图标

`icon.png` 3,071 字节。是自产（或程序生成的小图），**但规格太低，不足以作为商店/发行图标**，见 `store-page.md`。

---

## 待登记（一旦引入外部素材，在此表逐条补）

| 日期 | 文件路径 | 来源（URL / 工具 / 作者） | 许可类型 | 是否允许商用 | 是否需署名 | 登记人 |
|---|---|---|---|---|---|---|
| — | — | — | — | — | — | — |

当前为空。**规则：任何人往工程里加外部素材，必须先在表里登记一行，否则不进发行包。**

---

## 复查清单（每次打包前跑一遍）

1. `find . -path ./.godot -prune -o -path ./.git -prune -o -type f \( -name "*.png" -o -name "*.mp4" -o -name "*.ogv" -o -name "*.wav" -o -name "*.ogg" -o -name "*.ttf" -o -name "*.otf" \) -print` —— 输出里凡不在 `assets/textures/` 与 `assets/audio/` 下的，逐个交代来源。
2. 检查 `vibe_videos/` 与 `vibe_images/` 是否被误打进包（`.gitignore` 排除了它们，但打包脚本如果按目录拷贝就绕过了 git）。
3. 回查本文件的待登记表。
