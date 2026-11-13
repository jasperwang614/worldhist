-- items/planets.lua — 星图线（Planet 槽，设计案 §十 10.1）
-- 隐喻：牌型等级 = 人类的认知层级；每次天文大发现 = 给对应"牌型"升一级
-- 机制与原版星球牌完全一致（level_up_hand），零数值；占位图：不写 atlas，pos 指原版 Planet 图集帧

return {
	items = {
		-- 紫微垣（北极星）→ 高牌：众星拱之，帝星孤悬
		SMODS.Consumable({
			key = "ziwei",
			set = "Planet",
			cost = 3,
			pos = { x = 0, y = 0 },
			use = function(self, card, area, copier)
				level_up_hand(card, "High Card")
			end,
		}),

		-- 双子星 → 对子：天上的双胞胎，天生成对
		SMODS.Consumable({
			key = "shuangzi",
			set = "Planet",
			cost = 3,
			pos = { x = 1, y = 0 },
			use = function(self, card, area, copier)
				level_up_hand(card, "Pair")
			end,
		}),

		-- 四象 → 四条：二十八宿分四象，四象即四条
		SMODS.Consumable({
			key = "sixiang",
			set = "Planet",
			cost = 3,
			pos = { x = 2, y = 0 },
			use = function(self, card, area, copier)
				level_up_hand(card, "Four of a Kind")
			end,
		}),

		-- 五星连珠 → 顺子：五星聚东井，行星连成一线
		SMODS.Consumable({
			key = "wuxing",
			set = "Planet",
			cost = 3,
			pos = { x = 3, y = 0 },
			use = function(self, card, area, copier)
				level_up_hand(card, "Straight")
			end,
		}),

		-- 银河 → 同花：万点同源，同一片天
		SMODS.Consumable({
			key = "yinhe",
			set = "Planet",
			cost = 3,
			pos = { x = 4, y = 0 },
			use = function(self, card, area, copier)
				level_up_hand(card, "Flush")
			end,
		}),

		-- 黄道 → 同花顺：同一条路径连成一环
		SMODS.Consumable({
			key = "huangdao",
			set = "Planet",
			cost = 3,
			pos = { x = 5, y = 0 },
			use = function(self, card, area, copier)
				level_up_hand(card, "Straight Flush")
			end,
		}),

		-- 联星 → 两对：两对双星，天上从来成双（v2 补位件）
		SMODS.Consumable({
			key = "lianxing",
			set = "Planet",
			cost = 3,
			pos = { x = 6, y = 0 },
			use = function(self, card, area, copier)
				level_up_hand(card, "Two Pair")
			end,
		}),

		-- 三合星 → 三条：三颗星绑在一起烧（v2 补位件）
		SMODS.Consumable({
			key = "sanhexing",
			set = "Planet",
			cost = 3,
			pos = { x = 7, y = 0 },
			use = function(self, card, area, copier)
				level_up_hand(card, "Three of a Kind")
			end,
		}),

		-- 三垣 → 葫芦：紫微、太微、天市三垣拱着两重天（v2 补位件，风味待定稿）
		SMODS.Consumable({
			key = "sanyuan",
			set = "Planet",
			cost = 3,
			pos = { x = 8, y = 0 },
			use = function(self, card, area, copier)
				level_up_hand(card, "Full House")
			end,
		}),
	},
}
