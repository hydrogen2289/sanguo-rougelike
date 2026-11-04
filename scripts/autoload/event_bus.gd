extends Node
## EventBus —— 全局事件总线 autoload(M0)。
## M3+ 挂载点:三选一/商店/事件/结算/技能表现相关信号在此追加。

signal wave_state_changed(state: StringName, wave_idx: int)
signal wave_banner(text: String, secs: float)   # 居中横幅(波次开始/结束)
signal banner_styled(text: String, secs: float, color: Color, font_size: int)   # 带样式横幅(M6 卷轴展开演出)
signal screen_shake(strength: float, dur: float)                # 震屏(Boss 出场/震地,M5/M6)
signal enemy_died(unit: Node)
signal hero_died(hero_id: String)               # 武将阵亡 = 本局退场(01 §5)
signal lord_died                                # 主公阵亡 = 本局失败(M1 先发信号,结算属 M3)
signal gold_picked(value: int)
signal eastwind_started(duration: float)        # 借东风(M4 接入)
signal eastwind_ended
signal executed_kill                            # 关羽拖刀计斩杀 → 全屏「斩!」白闪(M6)
signal boss_phase_changed(phase: int)           # 华雄阶段切换(1 常规 / 2 狂暴,M5)
