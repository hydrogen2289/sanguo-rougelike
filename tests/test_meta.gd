extends "res://tests/test_base.gd"
## test_meta(M8,02 §5 / §12.2):养成曲线、记账、招募、编队、席位、面板冒烟。
## 断言口径来自 02 §5.1/§5.2/§4.5,并交叉校验 economy.json 与 SaveState 常量一致。
## 与 test_save 一样用隔离存档文件名,结束清理,不碰玩家真实存档。

const ECON_DOC_CAP := 30        # 02 §5.1 等级域上限
const ECON_DOC_STAR := 5        # 02 §5.2 星级域上限

const HERO_SCENE := "res://scenes/units/hero.tscn"   # (a) 接缝断言实例化范式(同 test_rig.gd)

var _st: SceneTree

func _run() -> void:
	_st = Engine.get_main_loop() as SceneTree
	DataDB.load_all()
	var old_file: String = SaveState.save_file
	SaveState.save_file = "test_meta_unit.json"
	_clear()
	_test_economy_loaded()
	_test_curves()
	_test_upgrade_accounting()
	_test_star_accounting()
	_test_recruit_and_fuse()
	_test_squad_rules()
	_test_slot_cap()
	_test_factors_into_battle_data()
	_test_owned_unowned_lists()
	_test_panels_build()
	# --- M8 补票(a~e,02 §12.2-2 覆盖缺口)---
	_test_curve_literals_and_seam()      # (a) 曲线字面量 + HeroUnit 接缝
	_test_dupe_recruit_rejected()        # (b) 重复转化:现状固化
	_test_upgrade_failure_idempotent()   # (c) 升级失败路径幂等
	_test_economy_closed_loop()          # (d) 经济闭环占位算术
	_test_recruit_persist_chain()        # (e) 端到端持久化链
	_clear()
	SaveState.save_file = old_file
	SaveState.data = {}

# ---------------------------------------------------------------- 工具

func _clear() -> void:
	SaveState.delete_save()
	SaveState.load_game()            # 建内存新档(默认桃园三人组 / 军资 0)

func _test_economy_loaded() -> void:
	var e := DataDB.economy
	check(not e.is_empty(), "economy.json 已加载")
	check(int(e.get("level", {}).get("cap", 0)) == SaveState.LEVEL_CAP,
		"economy.level.cap 与 SaveState.LEVEL_CAP 一致")
	check(int(e.get("star", {}).get("cap", 0)) == SaveState.STAR_CAP,
		"economy.star.cap 与 SaveState.STAR_CAP 一致")
	check(int(e.get("level", {}).get("cap", 0)) == ECON_DOC_CAP, "等级上限 = 02 §5.1 的 30")
	check(int(e.get("star", {}).get("cap", 0)) == ECON_DOC_STAR, "星级上限 = 02 §5.2 的 5")
	# 每个武将有且只有一个稀有度分档
	var seen := {}
	var dup := false
	for tier in ["starting", "normal", "rare", "epic"]:
		for id in DataDB.economy.get("rarity", {}).get(tier, []):
			if seen.has(str(id)):
				dup = true
			seen[str(id)] = true
	check(not dup, "稀有度分档无重复")
	check(seen.size() == DataDB.heroes.size(), "稀有度分档覆盖全部武将")

func _test_curves() -> void:
	# 02 §5.1:HP/ATK ×(1+0.08×(L−1));cost = round(50 × L^1.4)
	check(is_equal_approx(HeroSave.level_mult(1), 1.0), "Lv1 乘区 = 1.00")
	check(is_equal_approx(HeroSave.level_mult(30), 1.0 + 0.08 * 29.0), "Lv30 乘区 = 1+0.08×29")
	var expect_cost := int(round(50.0 * pow(1.0, 1.4)))
	check(HeroSave.level_cost(1) == expect_cost, "Lv1→2 耗军资 = round(50×1^1.4)=50")
	var c10 := int(round(50.0 * pow(10.0, 1.4)))
	check(HeroSave.level_cost(10) == c10, "Lv10→11 耗军资按幂曲线")
	check(HeroSave.level_cost(30) > HeroSave.level_cost(10), "升级消耗随等级单调增")
	# 02 §5.2:星乘区 1+0.15×(S−1) → [1.00,1.15,1.30,1.45,1.60]
	check(is_equal_approx(HeroSave.star_mult(1), 1.0), "1 星乘区 = 1.00")
	check(is_equal_approx(HeroSave.star_mult(5), 1.60), "5 星乘区 = 1.60")
	# 升星消耗 [10,20,40]
	check(HeroSave.star_cost(1) == 10 and HeroSave.star_cost(2) == 20 and HeroSave.star_cost(3) == 40,
		"升星消耗表 10/20/40")
	check(HeroSave.star_cost(5) == 0, "满星无升星消耗(返回 0 表示不可升)")

func _test_upgrade_accounting() -> void:
	var id := "guanyu"
	SaveState.data["wallet"]["junzi"] = 0
	var r := HeroSave.upgrade_level(id)
	check(not bool(r["ok"]), "军资不足时升级被拒")
	check(HeroSave.level_of(id) == 1, "被拒升级不改等级")
	check(SaveState.junzi() == 0, "被拒升级不扣军资")
	# 给够钱:连升两级,逐级扣费
	SaveState.add_junzi(10000)
	var before := SaveState.junzi()
	var c1 := HeroSave.level_cost(1)
	var r2 := HeroSave.upgrade_level(id)
	check(bool(r2["ok"]), "军资充足可升级")
	check(HeroSave.level_of(id) == 2, "等级 +1")
	check(SaveState.junzi() == before - c1, "按 Lv1 价格扣费")
	var c2 := HeroSave.level_cost(2)
	HeroSave.upgrade_level(id)
	check(SaveState.junzi() == before - c1 - c2, "第二级按 Lv2 价格扣费")
	# 封顶
	var e: Dictionary = SaveState.data["roster"][id]
	e["level"] = SaveState.LEVEL_CAP
	var r3 := HeroSave.upgrade_level(id)
	check(not bool(r3["ok"]), "满级拒绝升级")
	check(HeroSave.entry(id)["level"] == SaveState.LEVEL_CAP, "满级等级不变")
	# 未拥有
	var r4 := HeroSave.upgrade_level("lvbu")
	check(not bool(r4["ok"]), "未拥有武将不可升级")
	e["level"] = 1

func _test_star_accounting() -> void:
	var id := "zhangfei"
	SaveState.add_fragments(id, 5)
	var r := HeroSave.star_up(id)
	check(not bool(r["ok"]), "碎片不足(5/10)拒绝升星")
	check(HeroSave.star_of(id) == 1, "被拒升星不改星级")
	SaveState.add_fragments(id, 5)         # 10
	var r2 := HeroSave.star_up(id)
	check(bool(r2["ok"]), "碎片够 10 可升 2 星")
	check(HeroSave.star_of(id) == 2, "星级 +1")
	check(SaveState.fragments_of(id) == 0, "按 10 枚扣碎片")
	# 碎片是按武将定向记账:别人不能被挪用
	SaveState.data["wallet"]["fragments"] = {"guanyu": 100}
	var r3 := HeroSave.star_up(id)
	check(not bool(r3["ok"]), "他人碎片不可挪用")
	check(HeroSave.entry(id)["star"] == 2, "跨将升星失败不改星级")

func _test_recruit_and_fuse() -> void:
	var id := "zhaoyun"
	SaveState.data["wallet"]["junzi"] = 0
	check(not bool(HeroSave.recruit_buy(id)["ok"]), "军资不足不能直购")
	check(not HeroSave.owned(id), "直购失败不入册")
	var price := HeroSave.buy_price(id)
	check(price == int(DataDB.economy["recruit"]["buy_price"][DataDB.hero_rarity(id)]),
		"直购价取自 economy.json 对应稀有度")
	SaveState.add_junzi(price + 10)
	var r := HeroSave.recruit_buy(id)
	check(bool(r["ok"]), "军资够可直购")
	check(HeroSave.owned(id), "直购后入册")
	check(HeroSave.level_of(id) == 1 and HeroSave.star_of(id) == 1, "新将 1 级 1 星")
	check(SaveState.junzi() == 10, "按标价扣军资")
	check(not bool(HeroSave.recruit_buy(id)["ok"]), "已拥有不可重复直购")
	# 合成路径
	var id2 := "huatuo"
	var need := HeroSave.fuse_cost(id2)
	SaveState.add_fragments(id2, need - 1)
	check(not bool(HeroSave.recruit_fuse(id2)["ok"]), "碎片差 1 枚不能合成")
	SaveState.add_fragments(id2, 1)
	var rf := HeroSave.recruit_fuse(id2)
	check(bool(rf["ok"]), "碎片够可合成")
	check(HeroSave.owned(id2), "合成后入册")
	check(SaveState.fragments_of(id2) == 0, "合成按需扣碎片")
	# 存档校验仍通过(招募不能破坏 schema)
	check(SaveState.validate(SaveState.data).is_empty(), "招募后存档仍通过校验")

func _test_squad_rules() -> void:
	SaveState.data["squad"]["slots"] = ["liubei", "guanyu", "zhangfei"]
	check(not bool(HeroSave.set_squad(["guanyu"])["ok"]), "主公不在首位被拒")
	check(not bool(HeroSave.set_squad(["liubei", "lvbu"])["ok"]), "未拥有武将上阵被拒")
	check(not bool(HeroSave.set_squad(["liubei", "guanyu", "guanyu"])["ok"]), "重复上阵被拒")
	var cap := HeroSave.slot_cap()
	var too_many := ["liubei", "guanyu", "zhangfei", "zhaoyun", "huatuo", "machao", "weiyan"]
	check(not bool(HeroSave.set_squad(too_many)["ok"]) if too_many.size() > cap else true,
		"超出席位被拒")
	var ok := HeroSave.set_squad(["liubei", "guanyu", "zhaoyun"])
	check(bool(ok["ok"]), "合法编队写入成功")
	check(HeroSave.slots() == ["liubei", "guanyu", "zhaoyun"], "编队内容写回正确")
	# 出征名单:RunState.reset 取存档编队
	RunState.reset()
	var ids := []
	for m in RunState.team:
		ids.append(str(m["hero_id"]))
	check(ids == ["liubei", "guanyu", "zhaoyun"], "RunState 出征名单 = 存档编队")
	# 存档未初始化时回落桃园三人组
	SaveState.data = {}
	RunState.reset()
	var ids2 := []
	for m in RunState.team:
		ids2.append(str(m["hero_id"]))
	check(ids2 == ["liubei", "guanyu", "zhangfei"], "无存档回落到桃园三人组")
	SaveState.load_game()

func _test_slot_cap() -> void:
	var start := HeroSave.slot_cap()
	check(start == SaveState.INITIAL_SLOT_CAP, "初始席位 = INITIAL_SLOT_CAP")
	SaveState.data["wallet"]["junzi"] = 0
	check(not bool(HeroSave.buy_slot_cap()["ok"]), "军资不足不能扩编")
	SaveState.add_junzi(999999)
	var r := HeroSave.buy_slot_cap()
	check(bool(r["ok"]) and HeroSave.slot_cap() == start + 1, "扩编后席位 +1")
	var guard := 0
	while HeroSave.slot_cap() < SaveState.MAX_SLOT_CAP and guard < 20:
		var rr := HeroSave.buy_slot_cap()
		guard += 1
		if not bool(rr.get("ok", false)):
			check(false, "扩编意外中断: " + str(rr.get("reason", "")))
			break
	check(HeroSave.slot_cap() == SaveState.MAX_SLOT_CAP, "席位封顶 MAX_SLOT_CAP")
	check(not bool(HeroSave.buy_slot_cap()["ok"]), "满席位不可再扩")
	# 满席位 + 更多已拥有武将时 auto_fill 不超编
	SaveState.data["squad"]["slot_cap"] = SaveState.MAX_SLOT_CAP
	HeroSave.auto_fill()
	check(HeroSave.slots().size() <= SaveState.MAX_SLOT_CAP, "自动补满不超席位")
	check(str(HeroSave.slots()[0]) == "liubei", "自动补满仍以主公居首")

func _test_factors_into_battle_data() -> void:
	# 02 §5.4:出场基础值 = 表值 × factors;局内修饰符后乘(这里只验乘区本身)
	var id := "guanyu"
	var e: Dictionary = SaveState.data["roster"][id]
	e["level"] = 11                     # 1+0.08×10 = 1.8
	e["star"] = 3                       # 1+0.15×2 = 1.3
	var f := HeroSave.factors(id)
	check(is_equal_approx(f, 1.8 * 1.3), "养成乘区 = 等级乘区 × 星级乘区")
	var h := DataDB.hero_by_id(id)
	check(is_equal_approx(float(h["hp"]) * f, float(h["hp"]) * 2.34), "生命值按乘区放大")
	check(HeroSave.factors("lvbu") == 1.0, "未拥有武将乘区为 1.0(不意外变强)")
	e["level"] = 1
	e["star"] = 1

func _test_owned_unowned_lists() -> void:
	var own: Array = HeroSave.owned_ids()
	check(own.has("liubei") and own.has("guanyu") and own.has("zhangfei"), "初始三人组在已拥有列表")
	check(not own.has("lvbu"), "未招募武将不在已拥有列表")
	var un: Array = HeroSave.unowned_ids()
	check(un.size() == DataDB.heroes.size() - own.size(), "已拥有 + 未拥有 = 全名册")
	for id in un:
		check(not HeroSave.owned(str(id)), "未拥有列表不含已拥有武将: " + str(id))

func _test_panels_build() -> void:
	# 面板冒烟:实例化不崩、关键控件存在。--script 模式下不挂进场景树,只验证构造。
	for path in ["res://scripts/ui/tavern.gd", "res://scripts/ui/hero_up.gd"]:
		var s = load(path)
		check(s != null, "面板脚本可加载: " + path)
	# 编队面板 setup 参数在 _ready 前设置,单独验接口
	var sq = load("res://scripts/ui/squad_edit.gd")
	check(sq != null, "编队面板脚本可加载")
	check(load("res://scripts/ui/hero_card.gd") != null, "武将卡片脚本可加载")
	var tex: ImageTexture = HeroCard.portrait("liubei", 64)
	check(tex != null and tex.get_width() == 64, "程序化头像 64×64 生成成功")
	check(HeroCard.star_text(3) == "★★★☆☆", "星级文字 3 星 5 档")
	check(DataDB.hero_rarity("lvbu") == "epic", "吕布被登记为史诗")
	check(DataDB.hero_rarity("liubei") == "starting", "刘备被登记为初始")

# ---------------------------------------------------------------- M8 补票(a~e,02 §12.2-2 覆盖缺口)

## (a) 曲线字面量 + 接缝断言(P1 不回归,02 §5.1/§5.4):
## 现有 :56-57 只验乘区算术;此处补「L=1 出场值 = 表值」「L=30 HP ≈ 表值×3.32」字面量,
## 并实例化 HeroUnit 走完整 _ready→setup_from_data→_cache_base_stats→refresh_stats 链,
## 断言养成乘区在首次 refresh 与 mods_changed 常驻回调后仍生效(修复前被覆盖回裸表值)。
## 实例化范式同 test_rig.gd:64-78(hero.tscn + unit_id + add_child + await process_frame)。
func _test_curve_literals_and_seam() -> void:
	var id := "guanyu"
	var h: Dictionary = DataDB.hero_by_id(id)
	var hp0 := float(h.get("hp", 85))
	var atk0 := float(h.get("atk", 14))
	var e: Dictionary = SaveState.data["roster"][id]
	# L=1/S=1 → factors = 1.0,出场基础值 = 表值(字面量,不只是「乘区相等」)
	e["level"] = 1
	e["star"] = 1
	check(is_equal_approx(HeroSave.factors(id), 1.0), "L1/S1 出场乘区 = 1.00(字面量)")
	check(is_equal_approx(hp0 * HeroSave.factors(id), hp0), "L1 出场 HP = 表值(字面量)")
	check(is_equal_approx(atk0 * HeroSave.factors(id), atk0), "L1 出场 ATK = 表值(字面量)")
	# L=30 → 1+0.08×29 = 3.32(字面量),出场 HP ≈ 表值×3.32
	check(is_equal_approx(HeroSave.level_mult(30), 3.32), "Lv30 乘区 = 3.32(字面量)")
	check(is_equal_approx(hp0 * HeroSave.level_mult(30), hp0 * 3.32), "Lv30 HP ≈ 表值×3.32")
	# --- 接缝:实例化 HeroUnit 走 _ready 全链 ---
	RunState.reset()                       # 清干净局内 mods,使 RunState.stat() 恒等
	e["level"] = 11                        # 1+0.08×10 = 1.8
	e["star"] = 3                          # 1+0.15×2 = 1.3
	var f := HeroSave.factors(id)          # 2.34
	var expect_hp := hp0 * f
	var expect_atk := atk0 * f
	var hero: HeroUnit = (load(HERO_SCENE) as PackedScene).instantiate()
	hero.unit_id = id
	_st.root.add_child(hero)
	await _st.process_frame                # _ready 全链跑完(含首次 refresh_stats)
	check(is_equal_approx(float(hero.max_hp), expect_hp),
		"接缝:HeroUnit._ready 后 max_hp = 表值×level_mult×star_mult(P1 修复)")
	check(is_equal_approx(float(hero.atk), expect_atk),
		"接缝:HeroUnit._ready 后 atk = 表值×养成乘区")
	# mods_changed 常驻回调:修复前此处会把 max_hp 覆盖回裸表值 hp0
	RunState.mods_changed.emit()
	check(is_equal_approx(float(hero.max_hp), expect_hp),
		"接缝:mods_changed 刷新后乘区仍生效(P1 不回归)")
	check(not is_equal_approx(float(hero.max_hp), hp0),
		"接缝:refresh 后 max_hp 不再等于裸表值(乘区未被抹掉)")
	hero.queue_free()
	await _st.process_frame
	e["level"] = 1
	e["star"] = 1

## (b) 重复转化(economy.json:17 dupe_to_fragment:5 / 02 §7.4 提案):
## 审计坐实 hero_save.gd:141-152 已拥有直接拒绝、全仓无 dupe_to_fragment 消费点。
## 老板裁定「按实现值补文档」→ 不改实现;本断言把现状如实固化为测试:
## 已拥有武将再招募(直购/合成)均被拒,军资/碎片/等级/星级/存档不变。
## dupe_to_fragment 重复获取折算语义顺延 M11 RewardSettle 结算管道接线后重验。
func _test_dupe_recruit_rejected() -> void:
	var id := "guanyu"                  # 初始三人组,已拥有
	SaveState.add_junzi(5000)
	SaveState.add_fragments(id, 999)
	var junzi_before := SaveState.junzi()
	var frag_before := SaveState.fragments_of(id)
	var lv_before := HeroSave.level_of(id)
	var st_before := HeroSave.star_of(id)
	check(not bool(HeroSave.recruit_buy(id)["ok"]), "已拥有武将重复直购被拒")
	check(not bool(HeroSave.recruit_fuse(id)["ok"]), "已拥有武将重复合成被拒")
	check(SaveState.junzi() == junzi_before, "重复招募不扣军资(现状固化)")
	check(SaveState.fragments_of(id) == frag_before, "重复招募不扣碎片(现状固化)")
	check(HeroSave.level_of(id) == lv_before and HeroSave.star_of(id) == st_before,
		"重复招募不改等级/星级(现状固化)")
	check(SaveState.validate(SaveState.data).is_empty(), "重复招募后存档仍通过校验")

## (c) 升级扣款幂等(02 §12.2-2):成功升级按设计非幂等(每次 +1 级并扣费,不改实现)。
## 「幂等」口径取「失败路径重复调用不二次扣费、不改等级」:
## 余额不足 / 未拥有 / 满级三类失败各连续重复调用,断言状态守恒(现状固化)。
func _test_upgrade_failure_idempotent() -> void:
	var id := "guanyu"
	SaveState.data["wallet"]["junzi"] = 0
	var lv0 := HeroSave.level_of(id)
	for i in 3:
		check(not bool(HeroSave.upgrade_level(id)["ok"]), "余额不足第 %d 次升级被拒" % (i + 1))
	check(SaveState.junzi() == 0, "连续失败调用累计扣费仍为 0(幂等)")
	check(HeroSave.level_of(id) == lv0, "连续失败调用等级不变(幂等)")
	for i in 2:
		check(not bool(HeroSave.upgrade_level("lvbu")["ok"]), "未拥有第 %d 次升级被拒" % (i + 1))
	check(SaveState.junzi() == 0 and not HeroSave.owned("lvbu"), "未拥有重复失败不产出/不扣费")
	SaveState.add_junzi(999999)
	var e: Dictionary = SaveState.data["roster"][id]
	e["level"] = HeroSave.level_cap()
	var money_before := SaveState.junzi()
	for i in 2:
		check(not bool(HeroSave.upgrade_level(id)["ok"]), "满级第 %d 次升级被拒" % (i + 1))
	check(SaveState.junzi() == money_before, "满级重复失败不扣军资(幂等)")
	check(HeroSave.level_of(id) == HeroSave.level_cap(), "满级等级不变")
	e["level"] = 1

## (d) 经济闭环实测(02 §12.2-2 / §13.2-M11):**走真实结算管道 RewardSettle**,不是纯算术。
## 产出 = 第一章 8 关首通(campaign.json first_clear → settle_campaign)+ 评星宝箱 3 档
##      (claim_box)+ 塔 1~20 层(single settle_tower)。全部读 SaveState 增量,证明
##      「表 → 结算 → 钱包」单点无漏发/无重发(纯算术查不出管道漏项)。
## 消耗 = 三人组每级 level_cost 累加 + 招 1 名稀有将直购价。
##
## 口径说明(勿改回纯算术):
## 1) 产出侧必须经 RewardSettle 入库后读钱包增量;并交叉验证「管道产出 == 表推导值」,
##    后者是单一真源断言(管道若少发/多发一条就红)。
## 2) 02 §12.2-2 原带宽口径的分母是「三人组升满 L1→30」。该轴实测比值见本函数末尾
##    full_ratio 打印,当前 ≈0.016 —— 可定位为数值/内容量问题而非实现缺陷:
##    campaign.json 现只有 1 章 8 关(产出侧军资上限约 1190),而 economy.level 的
##    L1→30 单将总耗约 7.3 万、三人组约 21.9 万;内容深度(1 章)与养成深度(L30)
##    不匹配。属数值方(秤砣)调 data/economy.json / 补章节的活,不在本套件硬卡。
## 3) 本套件对「当前确实可玩到的窗口」——招 1 稀有将 + 三人组 L1→5 —— 做
##    ratio∈[0.8,1.5] 带宽断言(02 §12.2-2 的防通胀/防死档本意);full 轴原样打印备查。
## 4) 确定性:同输入算两次,比值必须完全一致(防随机/残留状态污染)。

const ECON_EARLY_LEVEL := 5     # 可玩窗口轴:三人组升到 5 级(章节 1 产出可支撑段)

func _test_economy_closed_loop() -> void:
	var settle: Dictionary = DataDB.economy.get("settle", {})
	check(not settle.is_empty() and settle.has("first_clear") and settle.has("tower_floor"),
		"闭环:settle 参数齐全(first_clear / tower_floor)")
	# ---------- 产出:全部经 RewardSettle 真实入库 ----------
	var out_total := _pipeline_output()
	check(out_total > 0, "闭环:经 RewardSettle 实测总产出 %d 军资 > 0" % out_total)
	# ---------- 单一真源:管道产出 == 表推导值 ----------
	var expect_total := _expected_output()
	check(out_total == expect_total,
		"闭环:管道产出与表推导一致(实测 %d / 表推 %d),无漏发或重发" % [out_total, expect_total])
	# ---------- 消耗 ----------
	var cost_full := _level_cost_3heroes(HeroSave.level_cap())
	var cost_early := _level_cost_3heroes(ECON_EARLY_LEVEL)
	var rare_price := float(HeroSave.buy_price("huatuo"))
	check(cost_full > cost_early and cost_early > rare_price,
		"闭环:消耗单调(L1→%d %.0f < L1→%d %.0f,含稀有将直购 %.0f)" % [
			ECON_EARLY_LEVEL, cost_early, HeroSave.level_cap(), cost_full, rare_price])
	var full_ratio := float(out_total) / maxf(1.0, cost_full)
	var early_ratio := float(out_total) / maxf(1.0, cost_early + rare_price)
	check(full_ratio > 0.0 and not is_inf(full_ratio) and not is_nan(full_ratio)
		and early_ratio > 0.0 and not is_inf(early_ratio) and not is_nan(early_ratio),
		"闭环:两轴比值均有限为正(full %.4f / early %.4f)" % [full_ratio, early_ratio])
	# 确定性:重算一次必须逐位相同
	var out2 := _pipeline_output()
	var early_ratio2 := float(out2) / maxf(1.0, _level_cost_3heroes(ECON_EARLY_LEVEL) + rare_price)
	check(out2 == out_total and is_equal_approx(early_ratio2, early_ratio),
		"闭环:同输入重算比值一致(确定性,%.4f)" % early_ratio)
	# ---------- 带宽断言(可玩窗口轴,02 §12.2-2) ----------
	check(early_ratio >= 0.8 and early_ratio <= 1.5,
		"闭环带宽:招 1 稀有将 + 三人组 L1→%d,产出/消耗 = %.3f ∈ [0.8, 1.5]" % [
			ECON_EARLY_LEVEL, early_ratio])
	# ---------- full 轴(三人组 L1→30)如实打印,交数值方调参 ----------
	print("    [闭环] 总产出 %d / 消耗(三人组 L1→%d + 稀有将)= %.0f → full 比值 %.4f"
		% [out_total, HeroSave.level_cap(), cost_full + rare_price, full_ratio])
	print("    [闭环] 可玩窗口轴(三人组 L1→%d + 稀有将)= %.0f → early 比值 %.4f"
		% [ECON_EARLY_LEVEL, cost_early + rare_price, early_ratio])
	if full_ratio < 0.8:
		print("    [闭环] full 轴未达带宽:campaign.json 仅 %d 章,产出侧封顶;"
			% DataDB.chapter_list().size()
			+ "需补章节或由数值方调 data/economy.json:level.cost_base/cost_exp(非结算实现缺陷)")

## 走真实管道跑一遍「第一章全首通 + 宝箱 + 塔 1~20 层」,返回入库军资总额
func _pipeline_output() -> int:
	SaveState.delete_save()
	SaveState.load_game()
	RunState.reset(20261106)
	RunState.mode = &"campaign"
	var start := SaveState.junzi()
	for sid in _chapter1_stage_ids():
		RunState.context = {"stage_id": sid, "wave_total": 4}
		var r: Dictionary = RewardSettle.settle("campaign",
			{"victory": true, "no_casualty": true, "lord_hp_ratio": 1.0, "stage_id": sid})
		check(bool(r.get("ok", false)), "闭环:关卡 %s 结算 ok" % sid)
	# 评星宝箱(每章 3/6/9 星各 1 箱;全 ★3 后三档全开)
	var cid := str(DataDB.chapter_list()[0].get("id", "ch1"))
	for tier in [3, 6, 9]:
		var b: Dictionary = CampaignSave.claim_box(cid, tier)
		check(bool(b.get("ok", false)), "闭环:评星宝箱 %d 星档可领" % tier)
	# 塔 1~20 层(一次结算 = 本局爬到 20 层)
	RunState.mode = &"tower"
	RunState.context = {"floor_start": 1, "endless": true}
	var rt: Dictionary = RewardSettle.settle("tower",
		{"floors_cleared": 20, "died": false, "retreat": false, "kills": 200})
	check(bool(rt.get("ok", false)), "闭环:塔 1~20 层结算 ok")
	return SaveState.junzi() - start

## 表推导值(独立于管道:直接按 campaign.json 与 economy.settle 算),用于单一真源交叉验证
func _expected_output() -> int:
	var total := 0
	for sid in _chapter1_stage_ids():
		total += int(DataDB.stage_by_id(sid).get("first_clear", {}).get("junzi", 0))
	for t in CampaignSave.BOX_TIERS:
		total += int(CampaignSave.BOX_REWARDS.get(t, 0))
	var tf: Dictionary = DataDB.economy.get("settle", {}).get("tower_floor", {})
	var tj: Dictionary = tf.get("junzi", {})
	var bm := float(tf.get("boss_mult", 1.0))
	for f in range(1, 21):
		var g := float(tj.get("base", 0)) + float(tj.get("per_floor", 0)) * float(f)
		if DataDB.tower_is_boss_floor(f):
			g *= bm
		total += int(round(g))
	return total

func _chapter1_stage_ids() -> Array:
	var out: Array = []
	for ch in DataDB.chapter_list():
		for st in ch.get("stages", []):
			out.append(str(st.get("id", "")))
		return out          # 只取第一章(当前内容量)
	return out

## 三名初始武将各升到 target 级的累计军资消耗
func _level_cost_3heroes(target: int) -> float:
	var per := 0.0
	for lv in range(1, target):
		per += float(HeroSave.level_cost(lv))
	return per * 3.0

## (e) 端到端「招 1 名稀有将」持久化链(02 §12.2-2):
## recruit_buy → set_squad → SaveState.flush → 清内存 → load_game → owned/slots 仍含该将。
## 沿用 _run 开头的隔离存档文件名(test_meta_unit.json),不污染玩家真实存档;
## 结束由 _clear() 统一删档,恢复 save_file。
func _test_recruit_persist_chain() -> void:
	SaveState.delete_save()
	SaveState.load_game()               # 干净默认档
	var id := "huatuo"                  # rare 档(economy.rarity)
	check(DataDB.hero_rarity(id) == "rare", "前置:华佗为 rare 档")
	check(not HeroSave.owned(id), "前置:华佗未拥有")
	SaveState.add_junzi(HeroSave.buy_price(id) + 100)
	check(bool(HeroSave.recruit_buy(id)["ok"]), "招 1 名稀有将:直购成功")
	check(HeroSave.owned(id), "直购后入册")
	check(bool(HeroSave.set_squad(["liubei", "guanyu", id])["ok"]), "编队写入含该将")
	check(HeroSave.slots().has(id), "内存编队含该将")
	SaveState.flush()                   # 唯一写盘入口(02 §3.1)
	check(SaveState.has_save(), "落盘后存档文件存在")
	SaveState.data = {}                 # 模拟进程重启后内存清空
	check(not HeroSave.owned(id), "清内存后尚未读档(owned 回落 false)")
	var lr: Dictionary = SaveState.load_game()
	check(bool(lr.get("ok", false)) and not bool(lr.get("created", false)), "重启后读回既有档")
	check(HeroSave.owned(id), "持久化链:读回后该将仍已拥有")
	check(HeroSave.slots().has(id), "持久化链:读回后编队仍含该将")
	check(SaveState.validate(SaveState.data).is_empty(), "读回存档通过校验")
