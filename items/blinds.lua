-- items/blinds.lua — Boss Blind 线（对应设计案 §九）
-- 罗伯斯庇尔的"嫌疑"发放/结算在 hooks 的 set_blind 与 calculate_joker 门里；
-- 路易十四/周厉王在 hooks 的 set_cost / can_sell_card；隋炀帝用 SMODS.Blind 的 press_play
-- 占位图：不写 atlas，pos 指原版 Blind 图集帧

return {
	items = {
		-- 革命者·罗伯斯庇尔：恐怖统治（设计案 §五.4）
		SMODS.Blind({
			key = "robespierre",
			pos = { x = 0, y = 0 },
			dollars = 5,
			mult = 2,
			boss = { min = 1, max = 10 },
			boss_colour = HEX("7c1f1f"),
		}),

		-- 奢靡·路易十四"朕即国家"：商店价格翻倍（设计案 §九）
		SMODS.Blind({
			key = "louis14",
			pos = { x = 1, y = 0 },
			dollars = 5,
			mult = 2,
			boss = { min = 1, max = 10 },
			boss_colour = HEX("b8860b"),
		}),

		-- 过度扩张·隋炀帝"大运河"：每回合第一手牌必须打出至少 4 张（设计案 §九）
		-- 首手 = 本回合尚未打出过手牌（hist_hand_played 由 hooks 维护）
		SMODS.Blind({
			key = "suiyangdi",
			pos = { x = 2, y = 0 },
			dollars = 5,
			mult = 2,
			boss = { min = 1, max = 10 },
			boss_colour = HEX("4a6141"),
			press_play = function(self)
				if (G.GAME.hist_hand_played or 0) == 0
					and G.hand and #G.hand.highlighted < 4
				then
					attention_text({
						text = localize("hist_sui_block"),
						scale = 0.8,
						hold = 1.2,
						major = G.play,
						align = "cm",
					})
					return false
				end
			end,
		}),

		-- 暴政·周厉王"弭谤"：本回合不能出售任何卡牌（设计案 §九）
		SMODS.Blind({
			key = "zhouliwang",
			pos = { x = 3, y = 0 },
			dollars = 5,
			mult = 2,
			boss = { min = 1, max = 10 },
			boss_colour = HEX("5d4037"),
		}),

		-- 黑死病（1347 · 2026-09-11 新增批次）：进场即从牌组永久带走 2 张牌
		-- 落点 = 永久损耗牌组，与其余四个 Boss（嫌疑/价格/出牌数/禁售）完全不同轴；
		-- 不 debuff、不改数值，代价是"人真的少了"。牌组留 8 张底，不会把人抽干
		-- 实现：hooks 的 Blind:set_blind 分支调 HIST.plague_kill(2)（start_dissolve 同手牌销毁路径）
		SMODS.Blind({
			key = "plague",
			pos = { x = 4, y = 0 },
			dollars = 5,
			mult = 2,
			boss = { min = 2, max = 10 },
			boss_colour = HEX("3d3d2f"),
		}),

		-- 结绳记事·印加（2026-09-11 第二批次）：本盲注内不能使用任何消耗牌
		-- 新轴：五个既有 Boss 分别打"结算/价格/出牌数/出售/牌组"，本 Boss 打"资源入口"
		-- 实现：hooks 的 Card:can_use_consumeable（card.lua:1840 是唯一的可用性入口）直接返回 false，
		-- 使用按钮置灰；不销毁、不 debuff，只是"这片土地上没有文字"
		SMODS.Blind({
			key = "inca",
			pos = { x = 5, y = 0 },
			dollars = 5,
			mult = 2,
			boss = { min = 2, max = 10 },
			boss_colour = HEX("8c6239"),
		}),
	},
}
