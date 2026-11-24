-- items/figures.lua — 风云小丑线（对应设计案 §七）
-- 革命者小丑在 HIST.revolutionary_keys 登记（石人一只眼的重触发对象）
-- 占位图：不写 atlas，pos 指原版 Joker 图集帧

return {
	items = {
		-- 李斯：+50 筹码；嬴政/秦始皇在场 → +80 且 X1.5——跟对人（设计案 §七.1）
		-- 文字例外说明：李斯写"场上有嬴政或秦始皇"是辅佐其人，不是皇帝判定（§2.1）
		SMODS.Joker({
			key = "lisi",
			config = { extra = { chips = 50, chips_up = 80, xmult = 1.5 } },
			rarity = 2,
			cost = 6,
			atlas = "hist_jokers",
			pos = { x = 4, y = 1 },
			blueprint_compat = true,
			eternal_compat = true,
			perishable_compat = true,
			order = 3,
			loc_vars = function(self, info_queue, center)
				local has_qin = HIST.emperor_key_present("j_hist_yingzheng")
					or HIST.emperor_key_present("j_hist_qinshihuang")
				if has_qin then
					return { key = "j_hist_lisi_up", vars = {} }
				end
				return { key = "j_hist_lisi", vars = {} }
			end,
			calculate = function(self, card, context)
				if context.joker_main and not context.blueprint then
					local e = card.ability.extra
					if HIST.emperor_key_present("j_hist_yingzheng")
						or HIST.emperor_key_present("j_hist_qinshihuang")
					then
						return { chips = e.chips_up, xmult = e.xmult, card = card }
					end
					return { chips = e.chips, card = card }
				end
			end,
		}),

		-- 蒙恬：手牌上限 +1；场上有皇帝 Joker → +2——长城是多一张牌的容错（设计案 §七.2）
		SMODS.Joker({
			key = "mengtian",
			config = { extra = { h_size = 1, h_size_emperor = 2 } },
			rarity = 2,
			cost = 6,
			atlas = "hist_jokers",
			pos = { x = 5, y = 1 },
			blueprint_compat = false,
			eternal_compat = true,
			perishable_compat = true,
			order = 4,
			add_to_deck = function(self, card)
				-- 结算时决定加多少并记在卡上，remove 对称回收（debuff 瞬窗也对称）
				local n = HIST.emperor_present()
					and card.ability.extra.h_size_emperor
					or card.ability.extra.h_size
				G.hand:change_size(n)
				card.ability.hist_h_size_applied = n
			end,
			remove_from_deck = function(self, card)
				local n = card.ability.hist_h_size_applied or card.ability.extra.h_size
				G.hand:change_size(-n)
				card.ability.hist_h_size_applied = nil
			end,
		}),

		-- 太常：每第 3 回合结束生成 1 张随机登基器物——太常寺管的就是加冕礼（设计案 §七.9）
		SMODS.Joker({
			key = "taichang",
			config = { extra = { every = 3, count = 0 } },
			rarity = 2,
			cost = 5,
			atlas = "hist_jokers",
			pos = { x = 6, y = 1 },
			blueprint_compat = false,
			eternal_compat = true,
			perishable_compat = true,
			order = 5,
			calculate = function(self, card, context)
				if context.end_of_round and not context.blueprint and not context.retrigger_joker then
					local e = card.ability.extra
					e.count = (e.count or 0) + 1
					if e.count >= e.every then
						e.count = 0
						local pool = {}
						for k in pairs(HIST.crown_items) do
							pool[#pool + 1] = k
						end
						local give = pseudorandom_element(pool, pseudoseed("hist_taichang"))
						G.E_MANAGER:add_event(Event({
							trigger = "after",
							delay = 0.3,
							func = function()
								local new_card = SMODS.create_card({ key = give, area = G.consumeables })
								if new_card then
									new_card:add_to_deck()
									G.consumeables:emplace(new_card)
									new_card:juice_up(0.3, 0.5)
								end
								return true
							end,
						}))
						return {
							message = localize("hist_taichang_gift"),
							colour = G.C.GOLD,
							card = card,
						}
					end
				end
			end,
		}),

		-- 陈胜（革命者）：高牌 X3——王侯将相宁有种乎（设计案 §七.8）
		-- 与石人一只眼同场：高牌双触发 X9
		SMODS.Joker({
			key = "chensheng",
			config = { extra = { xmult = 3 } },
			rarity = 2,
			cost = 5,
			atlas = "hist_jokers",
			pos = { x = 7, y = 1 },
			blueprint_compat = true,
			eternal_compat = true,
			perishable_compat = true,
			order = 1,
			loc_vars = function(self, info_queue, center)
				return { vars = { center.ability.extra.xmult } }
			end,
			calculate = function(self, card, context)
				if context.joker_main and context.scoring_name == "High Card" then
					return { xmult = card.ability.extra.xmult, card = card }
				end
			end,
		}),

		-- 斯巴达克斯（革命者）：点数最小的计分牌 X3——奴隶翻身（设计案 §七.6）
		-- 同点并列的最小牌都触发
		SMODS.Joker({
			key = "spartacus",
			config = { extra = { xmult = 3 } },
			rarity = 2,
			cost = 5,
			atlas = "hist_jokers",
			pos = { x = 8, y = 1 },
			blueprint_compat = true,
			eternal_compat = true,
			perishable_compat = true,
			order = 2,
			loc_vars = function(self, info_queue, center)
				return { vars = { center.ability.extra.xmult } }
			end,
			calculate = function(self, card, context)
				if context.individual and context.cardarea == G.play then
					local min_id = 15
					for _, c in ipairs(context.scoring_hand or {}) do
						local id = c:get_id()
						if id < min_id then
							min_id = id
						end
					end
					if context.other_card:get_id() == min_id then
						return { xmult = card.ability.extra.xmult, card = context.other_card }
					end
				end
			end,
		}),

		-- 布鲁图：Et tu, Brute——每局第 15 张计分牌刺杀凯撒，自己永久 X6（设计案 §七.7）
		-- 特殊例外设计；计数为整局累计（设计案原文"每回合"实测过难触发，记入进度表待调）
		SMODS.Joker({
			key = "brutus",
			config = { extra = { chips = 10, kill_at = 15, mult = 6, count = 0, done = false } },
			rarity = 3,
			cost = 8,
			atlas = "hist_jokers",
			pos = { x = 9, y = 1 },
			blueprint_compat = false,
			eternal_compat = true,
			perishable_compat = true,
			order = 6,
			loc_vars = function(self, info_queue, center)
				local e = center.ability.extra
				return { vars = { e.chips, e.kill_at, e.mult, e.count } }
			end,
			calculate = function(self, card, context)
				local e = card.ability.extra
				if context.individual and context.cardarea == G.play
					and not context.blueprint and not e.done
				then
					e.count = (e.count or 0) + 1
					if e.count >= e.kill_at then
						for _, c in ipairs(G.jokers.cards) do
							if c.config.center.key == "j_hist_caesar" then
								c:start_dissolve()
								e.done = true
								return {
									message = localize("hist_brutus"),
									colour = G.C.RED,
									card = card,
								}
							end
						end
					end
				end
				if context.joker_main then
					if e.done then
						return { xmult = e.mult, card = card }
					end
					return { chips = e.chips, card = card }
				end
			end,
		}),

		-- 荆轲：每手牌最后一张计分牌 X2；它是 A 再翻倍——图穷匕见（设计案 §七.3）
		SMODS.Joker({
			key = "jingke",
			config = { extra = { xmult = 2 } },
			rarity = 2,
			cost = 5,
			atlas = "hist_jokers",
			pos = { x = 0, y = 2 },
			blueprint_compat = true,
			eternal_compat = true,
			perishable_compat = true,
			order = 7,
			loc_vars = function(self, info_queue, center)
				return { vars = { center.ability.extra.xmult } }
			end,
			calculate = function(self, card, context)
				if context.individual and context.cardarea == G.play then
					local hand = context.scoring_hand or {}
					if #hand > 0 and context.other_card == hand[#hand] then
						local x = card.ability.extra.xmult
						if context.other_card:get_id() == 14 then
							x = x * 2
						end
						return { xmult = x, card = context.other_card }
					end
				end
			end,
		}),

		-- 克伦威尔：护国公武装就绪——持有断头台时本手牌 X2（设计案 §七.4）
		SMODS.Joker({
			key = "cromwell",
			config = { extra = { xmult = 2 } },
			rarity = 3,
			cost = 8,
			atlas = "hist_jokers",
			pos = { x = 1, y = 2 },
			blueprint_compat = true,
			eternal_compat = true,
			perishable_compat = true,
			order = 8,
			loc_vars = function(self, info_queue, center)
				return { vars = { center.ability.extra.xmult } }
			end,
			calculate = function(self, card, context)
				if context.joker_main and G.consumeables then
					for _, c in ipairs(G.consumeables.cards) do
						if c.config.center.key == "c_hist_guillotine" then
							return { xmult = card.ability.extra.xmult, card = card }
						end
					end
				end
			end,
		}),

		-- 黎塞留：红衣主教操盘群王——每张 Rare 及以上小丑 +10 倍率（设计案 §七.5）
		SMODS.Joker({
			key = "richelieu",
			config = { extra = { mult_per = 10 } },
			rarity = 2,
			cost = 6,
			atlas = "hist_jokers",
			pos = { x = 2, y = 2 },
			blueprint_compat = true,
			eternal_compat = true,
			perishable_compat = true,
			order = 9,
			loc_vars = function(self, info_queue, center)
				return { vars = { center.ability.extra.mult_per } }
			end,
			calculate = function(self, card, context)
				if context.joker_main and G.jokers then
					local rares = 0
					for _, c in ipairs(G.jokers.cards) do
						local r = c.config.center.rarity
						if r == 3 or r == 4 then
							rares = rares + 1
						end
					end
					if rares > 0 then
						return { mult = card.ability.extra.mult_per * rares, card = card }
					end
				end
			end,
		}),

		-- ===== 小众历史人物线（设计案 §十五） =====

		-- 徐福：东渡求药一去不回——每回合结束 15% 概率生成 1 张随机消耗牌
		SMODS.Joker({
			key = "xufu",
			config = { extra = {} },
			rarity = 2,
			cost = 5,
			atlas = "hist_jokers",
			pos = { x = 3, y = 2 },
			blueprint_compat = false,
			eternal_compat = true,
			perishable_compat = true,
			order = 10,
			calculate = function(self, card, context)
				if context.end_of_round and not context.blueprint and not context.retrigger_joker then
					if pseudorandom("hist_xufu") < 0.15 then
						G.E_MANAGER:add_event(Event({
							trigger = "after",
							delay = 0.3,
							func = function()
								local c = SMODS.create_card({ set = "Tarot", area = G.consumeables })
								if c then
									c:add_to_deck()
									G.consumeables:emplace(c)
									c:juice_up(0.3, 0.5)
								end
								return true
							end,
						}))
						return { message = localize("hist_xufu_sail"), colour = G.C.BLUE }
					end
				end
			end,
		}),

		-- 王莽：托古改制——连续两手打出同种牌型 → X2
		SMODS.Joker({
			key = "wangmang",
			config = { extra = { xmult = 2 } },
			rarity = 2,
			cost = 6,
			atlas = "hist_jokers",
			pos = { x = 4, y = 2 },
			blueprint_compat = true,
			eternal_compat = true,
			perishable_compat = true,
			order = 11,
			loc_vars = function(self, info_queue, center)
				return { vars = { center.ability.extra.xmult } }
			end,
			calculate = function(self, card, context)
				if context.joker_main and not context.blueprint then
					local repeat_hand = HIST.last_hand ~= nil and HIST.last_hand == context.scoring_name
					HIST.last_hand = context.scoring_name
					if repeat_hand then
						return { xmult = card.ability.extra.xmult, card = card }
					end
				end
			end,
		}),

		-- 司马迁：每有一张小丑被销毁，永久 +12 倍率——史家绝唱是拿命写的
		-- 观察回调 HIST.on_destroyed 由 hooks 的 start_dissolve 包装触发
		-- ★ 2026-09-11 修：原本从未注册 HIST.on_destroyed，成长永远不发生（死卡）
		SMODS.Joker({
			key = "simaqian",
			config = { extra = { mult_gain = 12, mult = 0 } },
			rarity = 3,
			cost = 8,
			atlas = "hist_jokers",
			pos = { x = 5, y = 2 },
			blueprint_compat = true,
			eternal_compat = true,
			perishable_compat = true,
			order = 12,
			loc_vars = function(self, info_queue, center)
				local e = center.ability.extra
				return { vars = { e.mult_gain, e.mult } }
			end,
			add_to_deck = function(self, card)
				-- 多张司马迁各自记账；回调只给场上还活着、且不是被销毁那张的加成长
				HIST.simaqian = HIST.simaqian or {}
				HIST.simaqian[card] = true
				HIST.on_destroyed = function(destroyed)
					for c in pairs(HIST.simaqian or {}) do
						if c ~= destroyed and c.ability and c.ability.extra then
							c.ability.extra.mult = (c.ability.extra.mult or 0)
								+ (c.ability.extra.mult_gain or 0)
							card_eval_status_text(c, "extra", nil, nil, nil, {
								message = localize("hist_simaqian_write"),
								colour = G.C.MULT,
							})
						end
					end
				end
			end,
			remove_from_deck = function(self, card)
				if HIST.simaqian then
					HIST.simaqian[card] = nil
				end
			end,
			calculate = function(self, card, context)
				if context.joker_main and card.ability.extra.mult > 0 then
					return { mult = card.ability.extra.mult, card = card }
				end
			end,
		}),

		-- 白起：回合结束时弃牌堆每满 10 张，本局永久 +4 倍率——坑杀，四十万的重量
		SMODS.Joker({
			key = "baiqi",
			config = { extra = { mult_gain = 4, mult = 0 } },
			rarity = 3,
			cost = 8,
			atlas = "hist_jokers",
			pos = { x = 6, y = 2 },
			blueprint_compat = true,
			eternal_compat = true,
			perishable_compat = true,
			order = 13,
			loc_vars = function(self, info_queue, center)
				local e = center.ability.extra
				return { vars = { e.mult_gain, e.mult } }
			end,
			calculate = function(self, card, context)
				if context.end_of_round and not context.blueprint and not context.retrigger_joker then
					local tens = math.floor(#(G.discard and G.discard.cards or {}) / 10)
					if tens > 0 then
						card.ability.extra.mult = card.ability.extra.mult
							+ card.ability.extra.mult_gain * tens
						return { message = localize("hist_baiqi"), colour = G.C.MULT, card = card }
					end
				end
				if context.joker_main and card.ability.extra.mult > 0 then
					return { mult = card.ability.extra.mult, card = card }
				end
			end,
		}),

		-- 伊姆霍特普：每使用 3 张消耗牌，永久 +15 筹码——金字塔一层层筑高
		SMODS.Joker({
			key = "imhotep",
			config = { extra = { every = 3, chips_gain = 15, chips = 0, count = 0 } },
			rarity = 2,
			cost = 6,
			atlas = "hist_jokers",
			pos = { x = 7, y = 2 },
			blueprint_compat = true,
			eternal_compat = true,
			perishable_compat = true,
			order = 14,
			loc_vars = function(self, info_queue, center)
				local e = center.ability.extra
				return { vars = { e.every, e.chips_gain, e.chips } }
			end,
			calculate = function(self, card, context)
				if context.using_consumeable and not context.blueprint then
					local e = card.ability.extra
					e.count = (e.count or 0) + 1
					if e.count >= e.every then
						e.count = 0
						e.chips = e.chips + e.chips_gain
						return { message = localize("hist_imhotep_layer"), colour = G.C.CHIPS, card = card }
					end
				end
				if context.joker_main and card.ability.extra.chips > 0 then
					return { chips = card.ability.extra.chips, card = card }
				end
			end,
		}),

		-- 曼萨·穆萨：每回合结束结算状态——金钱 ≥$40 下一回合 X2，否则 +20 筹码
		SMODS.Joker({
			key = "musa",
			config = { extra = { rich = false, xmult = 2, chips = 20, dollars = 40 } },
			rarity = 2,
			cost = 6,
			atlas = "hist_jokers",
			pos = { x = 8, y = 2 },
			blueprint_compat = true,
			eternal_compat = true,
			perishable_compat = true,
			order = 15,
			calculate = function(self, card, context)
				if context.end_of_round and not context.blueprint then
					card.ability.extra.rich = HIST.num(G.GAME.dollars) >= card.ability.extra.dollars
				end
				if context.joker_main then
					local e = card.ability.extra
					if e.rich then
						return { xmult = e.xmult, card = card }
					end
					return { chips = e.chips, card = card }
				end
			end,
		}),

		-- 汉尼拔：打出恰好 5 张牌且首尾同点 → X3——坎尼合围
		SMODS.Joker({
			key = "hannibal",
			config = { extra = { xmult = 3 } },
			rarity = 2,
			cost = 6,
			atlas = "hist_jokers",
			pos = { x = 9, y = 2 },
			blueprint_compat = true,
			eternal_compat = true,
			perishable_compat = true,
			order = 16,
			loc_vars = function(self, info_queue, center)
				return { vars = { center.ability.extra.xmult } }
			end,
			calculate = function(self, card, context)
				if context.joker_main and context.full_hand and #context.full_hand == 5 then
					local first = context.full_hand[1]:get_id()
					local last = context.full_hand[5]:get_id()
					if first == last then
						return { xmult = card.ability.extra.xmult, card = card }
					end
				end
			end,
		}),

		-- 张骞：打出顺子 +30 筹码——凿空，把东西连成一线
		SMODS.Joker({
			key = "zhangqian",
			config = { extra = { chips = 30 } },
			rarity = 2,
			cost = 5,
			atlas = "hist_jokers",
			pos = { x = 0, y = 3 },
			blueprint_compat = true,
			eternal_compat = true,
			perishable_compat = true,
			order = 17,
			loc_vars = function(self, info_queue, center)
				return { vars = { center.ability.extra.chips } }
			end,
			calculate = function(self, card, context)
				if context.joker_main and context.scoring_name == "Straight" then
					return { chips = card.ability.extra.chips, card = card }
				end
			end,
		}),

		-- 马可·波罗：每局第一次出牌后触发一次——随机 1 张手牌随机变成另一张（他说的牌，未必是真的）
		SMODS.Joker({
			key = "marco",
			config = { extra = {} },
			rarity = 2,
			cost = 5,
			atlas = "hist_jokers",
			pos = { x = 1, y = 3 },
			blueprint_compat = false,
			eternal_compat = true,
			perishable_compat = true,
			order = 18,
			calculate = function(self, card, context)
				if context.joker_main and not context.blueprint
					and (G.GAME.hist_hand_played or 0) == 1
					and not card.ability.extra.used
					and G.hand and #G.hand.cards > 0
				then
					card.ability.extra.used = true
					local picked = pseudorandom_element(G.hand.cards, pseudoseed("hist_marco"))
					local base_keys = {}
					for base_key, _ in pairs(G.P_CARDS) do
						base_keys[#base_keys + 1] = base_key
					end
					picked:set_base(G.P_CARDS[pseudorandom_element(base_keys, pseudoseed("hist_marco2"))])
					picked:juice_up(0.3, 0.5)
					return { message = localize("hist_marco_tale"), colour = G.C.BLUE }
				end
			end,
		}),

		-- 图坦卡蒙：每盲注首手抽齐时 25% 概率销毁一张随机其他小丑，自身永久 +30 筹码
		-- 陪葬的越多，越重；销毁池排除吞并壳（庇护），免死金牌由拦截钩子接管
		SMODS.Joker({
			key = "tut",
			config = { extra = { chance = 0.25, chips_gain = 30, chips = 0 } },
			rarity = 3,
			cost = 8,
			atlas = "hist_jokers",
			pos = { x = 2, y = 3 },
			blueprint_compat = false,
			eternal_compat = true,
			perishable_compat = true,
			order = 19,
			loc_vars = function(self, info_queue, center)
				local e = center.ability.extra
				return { vars = { e.chips_gain, e.chips } }
			end,
			calculate = function(self, card, context)
				if context.first_hand_drawn and not context.blueprint
					and pseudorandom("hist_tut") < card.ability.extra.chance
				then
					local pool = {}
					for _, c in ipairs(G.jokers.cards) do
						if c ~= card and not (c.ability and c.ability.hist_absorbed)
							and not HIST.is_emperor(c)
						then
							pool[#pool + 1] = c
						end
					end
					if #pool > 0 then
						local victim = pseudorandom_element(pool, pseudoseed("hist_tut2"))
						victim:start_dissolve()
						card.ability.extra.chips = card.ability.extra.chips + card.ability.extra.chips_gain
						return { message = localize("hist_tut_curse"), colour = G.C.RED, card = card }
					end
				end
				if context.joker_main and card.ability.extra.chips > 0 then
					return { chips = card.ability.extra.chips, card = card }
				end
			end,
		}),

		-- 阿育王：ante ≤2 +50 筹码（征伐期）；ante ≥3 反转 X2（放下屠刀）
		SMODS.Joker({
			key = "ashoka",
			config = { extra = { chips = 50, xmult = 2 } },
			rarity = 3,
			cost = 8,
			atlas = "hist_jokers",
			pos = { x = 3, y = 3 },
			blueprint_compat = true,
			eternal_compat = true,
			perishable_compat = true,
			order = 20,
			loc_vars = function(self, info_queue, center)
				return { vars = { center.ability.extra.chips, center.ability.extra.xmult } }
			end,
			calculate = function(self, card, context)
				local late = G.GAME.round_resets and G.GAME.round_resets.ante >= 3
				if context.joker_main then
					if late then
						return { xmult = card.ability.extra.xmult, card = card }
					end
					return { chips = card.ability.extra.chips, card = card }
				end
			end,
		}),

		-- 干将莫邪：每盲注首手抽齐时，随机 1 张手牌永久获得随机增强（金/钢/玻璃）——以身铸剑
		SMODS.Joker({
			key = "ganjiang",
			config = { extra = {} },
			rarity = 2,
			cost = 5,
			atlas = "hist_jokers",
			pos = { x = 4, y = 3 },
			blueprint_compat = false,
			eternal_compat = true,
			perishable_compat = true,
			order = 21,
			calculate = function(self, card, context)
				if context.first_hand_drawn and not context.blueprint
					and G.hand and #G.hand.cards > 0
				then
					local picked = pseudorandom_element(G.hand.cards, pseudoseed("hist_forge"))
					local roll = pseudorandom("hist_forge2")
					local key = roll < 0.34 and "m_gold" or (roll < 0.67 and "m_steel" or "m_glass")
					picked:set_ability(G.P_CENTERS[key], true, nil)
					picked:juice_up(0.3, 0.5)
				end
			end,
		}),

		-- ===== 宗教史人物线（设计案 §十五，机制全部来自史实） =====

		-- 玄奘：每 ante 开始生成 1 张随机星球牌（真经；发放逻辑在 hooks 的 set_blind）
		SMODS.Joker({
			key = "xuanzang",
			config = { extra = {} },
			rarity = 3,
			cost = 8,
			atlas = "hist_jokers",
			pos = { x = 5, y = 3 },
			blueprint_compat = false,
			eternal_compat = true,
			perishable_compat = true,
			order = 22,
		}),

		-- 鉴真：每局第 6 次使用消耗牌后，生成 1 张该牌的复制——六渡东瀛，终成正果
		SMODS.Joker({
			key = "jianzhen",
			config = { extra = { every = 6, count = 0 } },
			rarity = 2,
			cost = 6,
			atlas = "hist_jokers",
			pos = { x = 6, y = 3 },
			blueprint_compat = false,
			eternal_compat = true,
			perishable_compat = true,
			order = 23,
			loc_vars = function(self, info_queue, center)
				return { vars = { center.ability.extra.every } }
			end,
			calculate = function(self, card, context)
				if context.using_consumeable and context.consumeable
					and not context.blueprint
				then
					local e = card.ability.extra
					e.count = (e.count or 0) + 1
					if e.count >= e.every then
						e.count = 0
						local key = context.consumeable.config.center.key
						G.E_MANAGER:add_event(Event({
							trigger = "after",
							delay = 0.3,
							func = function()
								local c = SMODS.create_card({ key = key, area = G.consumeables })
								if c then
									c:add_to_deck()
									G.consumeables:emplace(c)
									c:juice_up(0.3, 0.5)
								end
								return true
							end,
						}))
						return { message = localize("hist_jianzhen"), colour = G.C.GOLD, card = card }
					end
				end
			end,
		}),

		-- 圣尼古拉：每回合结束时若金钱 <$5，+$3——枕下金币，悄悄接济
		SMODS.Joker({
			key = "nicholas",
			config = { extra = { dollars = 3, poor = 5 } },
			rarity = 2,
			cost = 5,
			atlas = "hist_jokers",
			pos = { x = 7, y = 3 },
			blueprint_compat = false,
			eternal_compat = true,
			perishable_compat = true,
			order = 24,
			calculate = function(self, card, context)
				if context.end_of_round and not context.blueprint and not context.retrigger_joker then
					if HIST.num(G.GAME.dollars) < card.ability.extra.poor then
						return {
							dollars = card.ability.extra.dollars,
							message = localize("hist_nicholas"),
							colour = G.C.MONEY,
							card = card,
						}
					end
				end
			end,
		}),

		-- 伊本·白图泰：本局首次打出的每种牌型，永久 +25 筹码——走过的路都算数
		SMODS.Joker({
			key = "battuta",
			config = { extra = { chips_gain = 25, chips = 0, seen = {} } },
			rarity = 2,
			cost = 6,
			atlas = "hist_jokers",
			pos = { x = 8, y = 3 },
			blueprint_compat = true,
			eternal_compat = true,
			perishable_compat = true,
			order = 25,
			loc_vars = function(self, info_queue, center)
				return { vars = { center.ability.extra.chips_gain, center.ability.extra.chips } }
			end,
			calculate = function(self, card, context)
				local e = card.ability.extra
				if context.joker_main and context.scoring_name
					and not e.seen[context.scoring_name]
				then
					e.seen[context.scoring_name] = true
					e.chips = e.chips + e.chips_gain
				end
				if context.joker_main and e.chips > 0 then
					return { chips = e.chips, card = card }
				end
			end,
		}),

		-- 萨拉丁：击败 Boss 后，下个商店价格 -1——不屠城，仁慈的战利品
		-- 标记在 hooks 的 end_of_round？不：直接在本卡 end_of_round 判定，set_cost 消费
		SMODS.Joker({
			key = "saladin",
			config = { extra = {} },
			rarity = 2,
			cost = 6,
			atlas = "hist_jokers",
			pos = { x = 9, y = 3 },
			blueprint_compat = false,
			eternal_compat = true,
			perishable_compat = true,
			order = 26,
			calculate = function(self, card, context)
				if context.end_of_round and not context.blueprint then
					local b = G.GAME.blind
					if b and b.boss and b.defeated then
						HIST.saladin_discount = true
					end
				end
			end,
		}),

		-- 第欧根尼：每盲注首手抽齐时随机弃 1 张手牌，+$3——别挡我阳光
		SMODS.Joker({
			key = "diogenes",
			config = { extra = { dollars = 3 } },
			rarity = 2,
			cost = 5,
			atlas = "hist_jokers",
			pos = { x = 0, y = 4 },
			blueprint_compat = false,
			eternal_compat = true,
			perishable_compat = true,
			order = 27,
			loc_vars = function(self, info_queue, center)
				return { vars = { center.ability.extra.dollars } }
			end,
			calculate = function(self, card, context)
				if context.first_hand_drawn and not context.blueprint
					and G.hand and #G.hand.cards > 0
				then
					local victim = pseudorandom_element(G.hand.cards, pseudoseed("hist_cynic"))
					victim:start_dissolve()
					ease_dollars(card.ability.extra.dollars)
					return { message = localize("hist_cynic_sun"), colour = G.C.MONEY, card = card }
				end
			end,
		}),

		-- 伊壁鸠鲁：每回合结束时，每个{C:attention}空着的小丑槽位{} +$2——该乐就乐
		-- ★ 2026-09-11 换效果：原"每剩 1 次弃牌 +$1"与屯田（每剩 1 次出牌 +$1）是镜子一对，
		--   同触发同奖励；改为"空槽位"这一全 mod 未用过的维度，并与吞并释放槽位天然协同
		--   （秦始皇吞得越多，花园越大），和"结余资源换钱"彻底分开
		SMODS.Joker({
			key = "epicurus",
			config = { extra = { dollars = 2 } },
			rarity = 2,
			cost = 5,
			atlas = "hist_jokers",
			pos = { x = 1, y = 4 },
			blueprint_compat = false,
			eternal_compat = true,
			perishable_compat = true,
			order = 28,
			loc_vars = function(self, info_queue, center)
				return { vars = { center.ability.extra.dollars, HIST.empty_joker_slots() } }
			end,
			calculate = function(self, card, context)
				if context.end_of_round and not context.blueprint and not context.retrigger_joker then
					local empty = HIST.empty_joker_slots()
					if empty > 0 then
						return {
							dollars = card.ability.extra.dollars * empty,
							message = localize("hist_epicurus"),
							colour = G.C.MONEY,
							card = card,
						}
					end
				end
			end,
		}),

		-- ===== 2026-09-11 新增批次：全部落在 mod 内未开垦的机制空间 =====

		-- 苏秦：合纵——左右相邻的每个小丑各为他提供 +40 筹码（位置机制，全 mod 首例）
		-- 六国是一条绳上的；他站在哪儿，哪儿就是联盟的中缝
		SMODS.Joker({
			key = "suqin",
			config = { extra = { chips = 40 } },
			rarity = 2,
			cost = 6,
			atlas = "hist_jokers",
			pos = { x = 2, y = 4 },
			blueprint_compat = true,
			eternal_compat = true,
			perishable_compat = true,
			order = 29,
			loc_vars = function(self, info_queue, center)
				local n = HIST.neighbour_count(center)
				return { vars = { center.ability.extra.chips, center.ability.extra.chips * n, n } }
			end,
			calculate = function(self, card, context)
				if context.joker_main then
					local n = HIST.neighbour_count(card)
					if n > 0 then
						return { chips = card.ability.extra.chips * n, card = card }
					end
				end
			end,
		}),

		-- 屈原：每弃掉 1 张牌，本局永久 +4 筹码——放逐的人跟着被弃的牌一起沉
		-- 弃牌触发是 mod 内首次作为正向资源使用（context.discard 经 state_events.lua:417 广播）
		SMODS.Joker({
			key = "quyuan",
			config = { extra = { chips_gain = 4, chips = 0 } },
			rarity = 2,
			cost = 6,
			atlas = "hist_jokers",
			pos = { x = 3, y = 4 },
			blueprint_compat = false,
			eternal_compat = true,
			perishable_compat = true,
			order = 30,
			loc_vars = function(self, info_queue, center)
				local e = center.ability.extra
				return { vars = { e.chips_gain, e.chips } }
			end,
			calculate = function(self, card, context)
				local e = card.ability.extra
				if context.discard and not context.blueprint then
					e.chips = (e.chips or 0) + e.chips_gain
					return { message = localize("hist_quyuan_sink"), colour = G.C.CHIPS, card = card }
				end
				if context.joker_main and e.chips > 0 then
					return { chips = e.chips, card = card }
				end
			end,
		}),

		-- 古腾堡：活字印刷——每回合第一次使用的消耗牌，用完后会被"印"回一张（不消耗）
		-- 机制落点："消耗牌再利用"，与鉴真（第 6 次复制）、伊姆霍特普（用 3 张成长）三足但不重叠
		SMODS.Joker({
			key = "gutenberg",
			config = { extra = {} },
			rarity = 3,
			cost = 8,
			atlas = "hist_jokers",
			pos = { x = 4, y = 4 },
			blueprint_compat = false,
			eternal_compat = true,
			perishable_compat = true,
			order = 31,
			calculate = function(self, card, context)
				if context.using_consumeable and context.consumeable
					and not context.blueprint and not G.GAME.hist_printed
				then
					G.GAME.hist_printed = true
					local key = context.consumeable.config.center.key
					G.E_MANAGER:add_event(Event({
						trigger = "after",
						delay = 0.3,
						func = function()
							if G.consumeables and #G.consumeables.cards < G.consumeables.config.card_limit then
								local c = SMODS.create_card({ key = key, area = G.consumeables })
								if c then
									c:add_to_deck()
									G.consumeables:emplace(c)
									c:juice_up(0.3, 0.5)
								end
							end
							return true
						end,
					}))
					return {
						message = localize("hist_gutenberg_press"),
						colour = G.C.GREEN,
						card = card,
					}
				end
			end,
		}),

		-- ===== 2026-09-11 第二批次：全部避开已饱和的"+筹码平铺 / X 倍率触发"两轴，
		--      改从本 mod 此前空白的维度取效果：手牌厚度 / 消耗牌持有量 / 点数和 / 回合内累积 / 牌组厚度 =====

		-- 阿基米德：出牌时，手牌里每张没打出去的牌 +4 倍率——给我一个支点
		-- 新维度：手牌张数（此前全 mod 无此轴）；与梭伦/蒙恬的手牌上限天然协同
		SMODS.Joker({
			key = "archimedes",
			config = { extra = { mult = 4 } },
			rarity = 2,
			cost = 6,
			atlas = "hist_jokers",
			pos = { x = 3, y = 1 },
			blueprint_compat = true,
			eternal_compat = true,
			perishable_compat = true,
			order = 32,
			loc_vars = function(self, info_queue, center)
				local left = G.hand and #G.hand.cards or 0
				return {
					vars = { center.ability.extra.mult, center.ability.extra.mult * left, left },
				}
			end,
			calculate = function(self, card, context)
				if context.joker_main then
					-- joker_main 时打出的牌已在 G.play，G.hand 里剩下的就是没打的
					local left = G.hand and #G.hand.cards or 0
					if left > 0 then
						return { mult = card.ability.extra.mult * left, card = card }
					end
				end
			end,
		}),

		-- 蔡伦：每持有 1 张消耗牌 +15 筹码——纸出来了，字才留得住
		-- 新维度：消耗牌持有量（此前只有"使用消耗牌"计数，没有"持有"计数）
		SMODS.Joker({
			key = "cailun",
			config = { extra = { chips = 15 } },
			rarity = 2,
			cost = 6,
			atlas = "hist_jokers",
			pos = { x = 5, y = 4 },
			blueprint_compat = true,
			eternal_compat = true,
			perishable_compat = true,
			order = 33,
			loc_vars = function(self, info_queue, center)
				local n = G.consumeables and #G.consumeables.cards or 0
				return { vars = { center.ability.extra.chips, center.ability.extra.chips * n, n } }
			end,
			calculate = function(self, card, context)
				if context.joker_main then
					local n = G.consumeables and #G.consumeables.cards or 0
					if n > 0 then
						return { chips = card.ability.extra.chips * n, card = card }
					end
				end
			end,
		}),

		-- 毕达哥拉斯：计分牌点数之和为质数时 X3——万物皆数
		-- 新维度：牌面点数的数学性质（get_id: A=14, K/Q/J=13/12/11, 数字牌为自身）
		SMODS.Joker({
			key = "pythagoras",
			config = { extra = { xmult = 3 } },
			rarity = 3,
			cost = 8,
			atlas = "hist_jokers",
			pos = { x = 6, y = 4 },
			blueprint_compat = true,
			eternal_compat = true,
			perishable_compat = true,
			order = 34,
			loc_vars = function(self, info_queue, center)
				return { vars = { center.ability.extra.xmult } }
			end,
			calculate = function(self, card, context)
				if context.joker_main and context.scoring_hand then
					local sum = 0
					for _, c in ipairs(context.scoring_hand) do
						sum = sum + (c:get_id() or 0)
					end
					if HIST.is_prime(sum) then
						return {
							x_mult = card.ability.extra.xmult,
							message = localize("hist_prime"),
							colour = G.C.XMULT,
							card = card,
						}
					end
				end
			end,
		}),

		-- 伽利略：本回合每打出一手，本手牌 X 倍率 +0.5（起手 X1.5）——可它仍在转动
		-- 新维度：回合内累积（此前没有任何"越打越强"的卡）；与屯田（省出牌次数换钱）形成取舍
		-- hist_hand_played 由 hooks 的 evaluate_play 维护，joker_main 时读到的是"本手之前打过几手"
		SMODS.Joker({
			key = "galileo",
			config = { extra = { xmult_gain = 0.5, xmult_base = 1.5 } },
			rarity = 3,
			cost = 8,
			atlas = "hist_jokers",
			pos = { x = 7, y = 4 },
			blueprint_compat = true,
			eternal_compat = true,
			perishable_compat = true,
			order = 35,
			loc_vars = function(self, info_queue, center)
				local e = center.ability.extra
				local n = G.GAME and G.GAME.hist_hand_played or 0
				return { vars = { e.xmult_gain, e.xmult_base + e.xmult_gain * n } }
			end,
			calculate = function(self, card, context)
				if context.joker_main then
					local e = card.ability.extra
					local n = G.GAME and G.GAME.hist_hand_played or 0
					return { x_mult = e.xmult_base + e.xmult_gain * n, card = card }
				end
			end,
		}),

		-- 成吉思汗：牌组每 4 张牌 +2 倍率——他走过的路，后来都成了版图
		-- 新维度：牌组厚度（与郑和宝船的 +牌、黑死病的 -牌 构成同一条"版图"轴的三种推力）
		-- 用 G.playing_cards 而非 G.deck.cards：后者只数牌堆剩余，会随抽牌抖动
		SMODS.Joker({
			key = "genghis",
			config = { extra = { mult = 2, per = 4 } },
			rarity = 2,
			cost = 6,
			atlas = "hist_jokers",
			pos = { x = 8, y = 4 },
			blueprint_compat = true,
			eternal_compat = true,
			perishable_compat = true,
			order = 36,
			loc_vars = function(self, info_queue, center)
				local e = center.ability.extra
				local n = G.playing_cards and #G.playing_cards or 0
				return {
					vars = { e.per, e.mult, e.mult * math.floor(n / e.per), n },
				}
			end,
			calculate = function(self, card, context)
				if context.joker_main then
					local e = card.ability.extra
					local n = G.playing_cards and #G.playing_cards or 0
					local gain = e.mult * math.floor(n / e.per)
					if gain > 0 then
						return { mult = gain, card = card }
					end
				end
			end,
		}),
	},
}
