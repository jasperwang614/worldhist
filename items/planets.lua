-- items/planets.lua — 星图线（Planet 槽，设计案 §十 10.1）
-- 隐喻：牌型等级 = 人类的认知层级；每次天文大发现 = 给对应"牌型"升一级
-- 机制与原版星球牌完全一致（level_up_hand），零数值；图集用 hist_relics（格位 17-25）
--
-- ⚠ 必须写 config = { hand_type = ... }，不要自己写 use：
--   ① Card:can_use_consumeable 靠 self.ability.consumeable.hand_type 判定可用，
--      没有它 → 卡永远置灰点不了（这就是"开到用不了"的原因）；
--   ② Card:use_consumeable 见到 hand_type 会自动 level_up_hand，
--      自己再写一遍 use 会变成升两级，叠上察举制就是四级；
--   ③ 天文台券（v_observatory）也读这个字段，缺了它券对小丑不生效。

return {
	items = {
		-- 紫微垣（北极星）→ 高牌：众星拱之，帝星孤悬
		SMODS.Consumable({
			key = "ziwei",
			set = "Planet",
			cost = 3,
			config = { hand_type = "High Card" },
			atlas = "hist_relics",
			pos = { x = 7, y = 1 },
		}),

		-- 双子星 → 对子：天上的双胞胎，天生成对
		SMODS.Consumable({
			key = "shuangzi",
			set = "Planet",
			cost = 3,
			config = { hand_type = "Pair" },
			atlas = "hist_relics",
			pos = { x = 8, y = 1 },
		}),

		-- 四象 → 四条：二十八宿分四象，四象即四条
		SMODS.Consumable({
			key = "sixiang",
			set = "Planet",
			cost = 3,
			config = { hand_type = "Four of a Kind" },
			atlas = "hist_relics",
			pos = { x = 9, y = 1 },
		}),

		-- 五星连珠 → 顺子：五星聚东井，行星连成一线
		SMODS.Consumable({
			key = "wuxing",
			set = "Planet",
			cost = 3,
			config = { hand_type = "Straight" },
			atlas = "hist_relics",
			pos = { x = 0, y = 2 },
		}),

		-- 银河 → 同花：万点同源，同一片天
		SMODS.Consumable({
			key = "yinhe",
			set = "Planet",
			cost = 3,
			config = { hand_type = "Flush" },
			atlas = "hist_relics",
			pos = { x = 1, y = 2 },
		}),

		-- 黄道 → 同花顺：同一条路径连成一环
		SMODS.Consumable({
			key = "huangdao",
			set = "Planet",
			cost = 3,
			config = { hand_type = "Straight Flush" },
			atlas = "hist_relics",
			pos = { x = 2, y = 2 },
		}),

		-- 联星 → 两对：两对双星，天上从来成双（v2 补位件）
		SMODS.Consumable({
			key = "lianxing",
			set = "Planet",
			cost = 3,
			config = { hand_type = "Two Pair" },
			atlas = "hist_relics",
			pos = { x = 3, y = 2 },
		}),

		-- 三合星 → 三条：三颗星绑在一起烧（v2 补位件）
		SMODS.Consumable({
			key = "sanhexing",
			set = "Planet",
			cost = 3,
			config = { hand_type = "Three of a Kind" },
			atlas = "hist_relics",
			pos = { x = 4, y = 2 },
		}),

		-- 三垣 → 葫芦：紫微、太微、天市三垣拱着两重天（v2 补位件，风味待定稿）
		SMODS.Consumable({
			key = "sanyuan",
			set = "Planet",
			cost = 3,
			config = { hand_type = "Full House" },
			atlas = "hist_relics",
			pos = { x = 5, y = 2 },
		}),
	},
}
