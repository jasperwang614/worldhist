-- items/emperors.lua — 皇帝线（对应设计案 §三/开发规范 §5.3）
-- 美术：已接 hist_jokers 图集（assets/1x|2x/jokers.png）——
--   嬴政 (0,0) / 秦始皇 (1,0) / 路易·奥古斯特 (2,0) / 路易十六 (3,0) / 路易十六的头 (4,0) / 凯撒 (5,0)
-- 其余形态尚未出图，不写 atlas、pos 仍指原版 Joker 图集帧占位。

return {
	items = {
		SMODS.Joker({
			key = "yingzheng",
			atlas = "hist_jokers",
			config = { extra = { xmult = 2 } },
			rarity = 2,
			cost = 6,
			pos = { x = 0, y = 0 },
			blueprint_compat = true,
			eternal_compat = true,
			perishable_compat = true,
			order = 1,
			loc_vars = function(self, info_queue, center)
				return { vars = { center.ability.extra.xmult } }
			end,
			calculate = function(self, card, context)
				-- 嬴政：扫六合——打出的计分牌包含全部四种花色 → X2（设计案 §3.1，每手判定）
				-- 注：登基前不是皇帝（§2.1 皇帝判定），断头台选不中他
				if context.joker_main and not context.blueprint then
					local suits = {}
					for _, c in ipairs(context.scoring_hand or {}) do
						suits[c.base.suit] = true
					end
					if suits.Hearts and suits.Spades and suits.Diamonds and suits.Clubs then
						return { xmult = card.ability.extra.xmult, card = card }
					end
				end
			end,
		}),

		SMODS.Joker({
			key = "qinshihuang",
			atlas = "hist_jokers",
			config = { extra = { chips_per = 25, absorbed = {} } },
			rarity = 3,
			cost = 8,
			pos = { x = 1, y = 0 },
			blueprint_compat = true,
			eternal_compat = true,
			perishable_compat = true,
			order = 2,
			loc_vars = function(self, info_queue, center)
				return {
					vars = { center.ability.extra.chips_per, #(center.ability.extra.absorbed or {}) },
				}
			end,
			calculate = function(self, card, context)
				-- 秦始皇：吞并系统本体 + 每吞并 1 个小丑 +25 筹码（统一度量衡，设计案 §3.2）
				if context.joker_main then
					-- ① 统一代发：本手牌把所有壳的效果在这一层依次结算，气泡按壳自己归属显示
					--    （蓝图复制秦始皇 = context.blueprint 原样透传 → 复制整棵效果树，设计案 §2.1）
					HIST.dispatching = true
					for _, shell in ipairs(G.jokers.cards) do
						if shell.ability.hist_absorbed and shell.hist_emperor == card then
							local ret = shell:calculate_joker(context)
							if ret then
								-- 手动转发效果表并按壳显示（smods utils.lua:1546）
								SMODS.calculate_effect(ret, shell)
							end
						end
					end
					HIST.dispatching = nil
					-- ② 本体效果（先代发后结算本体）
					local n = #(card.ability.extra.absorbed or {})
					if n > 0 then
						return { chips = card.ability.extra.chips_per * n, card = card }
					end
				end
				-- ③ 其余上下文（individual/before/after/end_of_round 等）同样逐个代发，
				--    壳的逐牌/回合结束效果才能生效；joker_main 的派发已在上面返回，这里只管其余。
				if not context.joker_main then
					HIST.dispatching = true
					for _, shell in ipairs(G.jokers.cards) do
						if shell.ability.hist_absorbed and shell.hist_emperor == card then
							local ret = shell:calculate_joker(context)
							if ret then
								SMODS.calculate_effect(ret, shell)
							end
						end
					end
					HIST.dispatching = nil
				end
			end,
		}),

		-- 路易·奥古斯特：王太子（还是个修锁爱好者）→ 王室年金（设计案 §五.1）
		SMODS.Joker({
			key = "louis_auguste",
			config = { extra = { dollars = 3 } },
			rarity = 2,
			cost = 6,
			atlas = "hist_jokers",
			pos = { x = 2, y = 0 },
			blueprint_compat = true,
			eternal_compat = true,
			perishable_compat = true,
			order = 3,
			loc_vars = function(self, info_queue, center)
				return { vars = { center.ability.extra.dollars } }
			end,
			calculate = function(self, card, context)
				-- 每回合首手牌含 K → +$3；hist_hand_played 由 hooks 的 evaluate_play 计数，
				-- 结算期间读旧值，0 = 首手
				if context.joker_main and not context.blueprint
					and (G.GAME.hist_hand_played or 0) == 0
				then
					for _, c in ipairs(context.scoring_hand or {}) do
						if c:get_id() == 13 then
							return { dollars = card.ability.extra.dollars, card = card }
						end
					end
				end
			end,
		}),

		-- 路易十六：皇帝形态（登基获得）→ 波旁家底 + 赤字通胀（设计案 §五.2）
		-- 强度本身就是靶子：他越富有，越值得上断头台
		SMODS.Joker({
			key = "louis16",
			config = { extra = { dollars = 5 } },
			rarity = 2,
			cost = 6,
			atlas = "hist_jokers",
			pos = { x = 3, y = 0 },
			blueprint_compat = false,
			eternal_compat = true,
			perishable_compat = true,
			order = 4,
			loc_vars = function(self, info_queue, center)
				return { vars = { center.ability.extra.dollars } }
			end,
			calc_dollar_bonus = function(self, card)
				return card.ability.extra.dollars
			end,
		}),

		-- 路易十六的头：特殊 Joker，不可购买，只能由断头台产生（设计案 §五.3）
		-- 白板；革命者 Boss 战中出售 → 直接终结该 Blind（hooks 的 sell_card 钩子，
		-- HIST.revolution_bosses 登记罗伯斯庇尔后生效）
		SMODS.Joker({
			key = "louis_head",
			config = {},
			rarity = 1,
			cost = 0,
			atlas = "hist_jokers",
			pos = { x = 4, y = 0 },
			blueprint_compat = false,
			eternal_compat = true,
			perishable_compat = false,
			order = 5,
			in_pool = function(self, args)
				return false
			end,
		}),

		-- 弘历：练章——登基前先在牌上练盖章（每盲注首手，随机 1 张没盖过章的手牌永久 +30 筹码）
		-- 原设计"+25 纯站桩"因同质性重做（2026-09-04 六轮）
		SMODS.Joker({
			key = "hongli",
			config = { extra = { chips = 30 } },
			rarity = 2,
			cost = 6,
			atlas = "hist_jokers",
			pos = { x = 7, y = 0 },
			blueprint_compat = false,
			eternal_compat = true,
			perishable_compat = true,
			order = 6,
			loc_vars = function(self, info_queue, center)
				return { vars = { center.ability.extra.chips } }
			end,
			calculate = function(self, card, context)
				if context.first_hand_drawn and not context.blueprint
					and G.hand and #G.hand.cards > 0
				then
					local pool = {}
					for _, c in ipairs(G.hand.cards) do
						if not c.ability.hist_lian then
							pool[#pool + 1] = c
						end
					end
					if #pool > 0 then
						local picked = pseudorandom_element(pool, pseudoseed("hist_lian"))
						picked.ability.hist_lian = true
						picked.ability.hist_lian_chips = (picked.ability.hist_lian_chips or 0)
							+ card.ability.extra.chips
						picked:juice_up(0.3, 0.5)
					end
				end
				if context.individual and context.cardarea == G.play
					and context.other_card.ability.hist_lian_chips
				then
					return { chips = context.other_card.ability.hist_lian_chips, card = context.other_card }
				end
			end,
		}),

		-- 乾隆：皇帝形态（登基获得）→ 盖章狂魔（设计案 §六.1）
		-- 首手抽齐时随机盖"御批"；该牌每计分一次 +50 筹码
		SMODS.Joker({
			key = "qianlong",
			config = { extra = { yubi_chips = 50 } },
			rarity = 3,
			cost = 8,
			atlas = "hist_jokers",
			pos = { x = 8, y = 0 },
			blueprint_compat = true,
			eternal_compat = true,
			perishable_compat = true,
			order = 7,
			loc_vars = function(self, info_queue, center)
				return { vars = { center.ability.extra.yubi_chips } }
			end,
			calculate = function(self, card, context)
				-- 御批发放：每盲注首手抽齐时一次（context.first_hand_drawn 每局每盲注只发一次）
				if context.first_hand_drawn and not context.blueprint then
					local pool = {}
					for _, c in ipairs(G.hand.cards) do
						pool[#pool + 1] = c
					end
					if #pool > 0 then
						local picked = pseudorandom_element(pool, pseudoseed("hist_yubi"))
						picked.ability.hist_yubi = true
						picked:add_sticker("hist_yubi", true)
						picked:juice_up(0.3, 0.5)
					end
				end
				-- 见啥盖啥：被御批的牌每计分一次 +50 筹码（蓝图复制也可受益）
				if context.individual and context.cardarea == G.play
					and context.other_card.ability.hist_yubi
				then
					return { chips = card.ability.extra.yubi_chips, card = context.other_card }
				end
			end,
		}),

		-- 波拿巴：炮兵——每回合第一次弃牌后，下一手牌 +40 筹码（先蓄力，再开炮）
		-- 原设计"首手 +40"因首手触发堆同质性重做（2026-09-04 六轮）；弃牌标志在 hooks
		SMODS.Joker({
			key = "bonaparte",
			config = { extra = { chips = 40 } },
			rarity = 2,
			cost = 6,
			atlas = "hist_jokers",
			pos = { x = 9, y = 0 },
			blueprint_compat = true,
			eternal_compat = true,
			perishable_compat = true,
			order = 8,
			loc_vars = function(self, info_queue, center)
				return { vars = { center.ability.extra.chips } }
			end,
			calculate = function(self, card, context)
				if context.joker_main and not context.blueprint
					and HIST.artillery_ready
				then
					HIST.artillery_ready = nil
					return { chips = card.ability.extra.chips, card = card }
				end
			end,
		}),

		-- 拿破仑一世：皇帝形态（登基获得）→ 自己加冕 + 每场胜仗都是加冕礼（设计案 §六.2）
		-- 点击自己即登基（hooks 的 Card:click 分支）；每击败一个 Boss Blind 永久 +12 倍率
		SMODS.Joker({
			key = "napoleon",
			config = { extra = { mult_gain = 12, mult = 0 } },
			rarity = 3,
			cost = 8,
			atlas = "hist_jokers",
			pos = { x = 0, y = 1 },
			blueprint_compat = true,
			eternal_compat = true,
			perishable_compat = true,
			order = 9,
			loc_vars = function(self, info_queue, center)
				local e = center.ability.extra
				return { vars = { e.mult_gain, e.mult } }
			end,
			calculate = function(self, card, context)
				if context.end_of_round and not context.blueprint and not context.retrigger_joker then
					local b = G.GAME.blind
					if b and b.boss and b.defeated then
						card.ability.extra.mult = card.ability.extra.mult
							+ card.ability.extra.mult_gain
						return { message = localize("hist_napoleon_win"), colour = G.C.MULT, card = card }
					end
				end
				if context.joker_main and card.ability.extra.mult > 0 then
					return { mult = card.ability.extra.mult, card = card }
				end
			end,
		}),

		-- 尤利乌斯：高卢战功（设计案 §六.3）
		SMODS.Joker({
			key = "julius",
			config = { extra = { mult = 4 } },
			rarity = 2,
			cost = 6,
			atlas = "hist_jokers",
			pos = { x = 6, y = 0 },
			blueprint_compat = true,
			eternal_compat = true,
			perishable_compat = true,
			order = 10,
			loc_vars = function(self, info_queue, center)
				return { vars = { center.ability.extra.mult } }
			end,
			calculate = function(self, card, context)
				if context.joker_main then
					return { mult = card.ability.extra.mult, card = card }
				end
			end,
		}),

		-- 凯撒：皇帝形态（登基获得）→ Veni Vidi Vici：每回合首手牌 X3（设计案 §六.3）
		-- 配套布鲁图：同场时每局第 15 张计分牌触发刺杀
		SMODS.Joker({
			key = "caesar",
			atlas = "hist_jokers",
			config = { extra = { xmult = 3 } },
			rarity = 3,
			cost = 8,
			pos = { x = 5, y = 0 },
			blueprint_compat = true,
			eternal_compat = true,
			perishable_compat = true,
			order = 11,
			loc_vars = function(self, info_queue, center)
				return { vars = { center.ability.extra.xmult } }
			end,
			calculate = function(self, card, context)
				if context.joker_main and not context.blueprint
					and (G.GAME.hist_hand_played or 0) == 0
				then
					return { xmult = card.ability.extra.xmult, card = card }
				end
			end,
		}),

		-- 索菲娅：德意志嫁妆——回合结束 +$2（设计案 §六.4）
		SMODS.Joker({
			key = "sofia",
			config = { extra = { dollars = 2 } },
			rarity = 2,
			cost = 6,
			atlas = "hist_jokers",
			pos = { x = 1, y = 1 },
			blueprint_compat = false,
			eternal_compat = true,
			perishable_compat = true,
			order = 12,
			loc_vars = function(self, info_queue, center)
				return { vars = { center.ability.extra.dollars } }
			end,
			calc_dollar_bonus = function(self, card)
				return card.ability.extra.dollars
			end,
		}),

		-- 叶卡捷琳娜二世：皇帝形态（登基获得）→ 政变抢壳（设计案 §六.4）
		-- 点击她 → 点击秦始皇的壳 → 夺归自己（hooks 的 steal_shell）；
		-- 每拥有一个壳，回合结束 +$2
		SMODS.Joker({
			key = "catherine",
			config = { extra = { dollars_per = 2 } },
			rarity = 3,
			cost = 8,
			atlas = "hist_jokers",
			pos = { x = 2, y = 1 },
			blueprint_compat = false,
			eternal_compat = true,
			perishable_compat = true,
			order = 13,
			loc_vars = function(self, info_queue, center)
				return { vars = { center.ability.extra.dollars_per } }
			end,
			calculate = function(self, card, context)
				if context.end_of_round and not context.blueprint and not context.retrigger_joker then
					local n = 0
					for _, c in ipairs(G.jokers.cards) do
						if c.ability.hist_absorbed and c.hist_emperor == card then
							n = n + 1
						end
					end
					if n > 0 then
						return {
							dollars = card.ability.extra.dollars_per * n,
							card = card,
						}
					end
				end
			end,
		}),
	},
}
