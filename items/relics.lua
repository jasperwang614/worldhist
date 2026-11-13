-- items/relics.lua — 器物 Consumable 线（对应设计案 §三/§十）
-- 占位图：不写 atlas，pos 指原版 Tarot 图集帧

-- ★ 圣火令的生效钩子：进入被标记的 Blind 时立即禁用其效果（原版 Blind.lua:392 disable）
local set_blind_ref = Blind.set_blind
function Blind:set_blind(blind, reset, silent)
	set_blind_ref(self, blind, reset, silent)
	if self.config
		and self.config.blind
		and G.GAME.hist_holy_fire
		and G.GAME.hist_holy_fire[self.config.blind.key]
	then
		self:disable()
		G.E_MANAGER:add_event(Event({
			trigger = "after",
			delay = 0.4,
			func = function()
				card_eval_status_text(G.GAME.blind, "extra", nil, nil, nil, {
					message = localize("hist_fire_active"),
					colour = G.C.RED,
				})
				return true
			end,
		}))
	end
end

return {
	items = {
		-- 传国玉玺：登基一张可登基人物（受命于天，正统凭证）
		SMODS.Consumable({
			key = "yuxi",
			set = "Tarot",
			cost = 5,
			pos = { x = 0, y = 0 },
			atlas = "hist_relics",
			can_use = function(self, card)
				return HIST.find_crownable() ~= nil
			end,
			use = function(self, card, area, copier)
				local target = HIST.find_crownable()
				if target and HIST.crown(target) then
					card_eval_status_text(target, "extra", nil, nil, nil, {
						message = localize("hist_crowned"),
						colour = G.C.GOLD,
					})
				end
			end,
		}),

		-- 桂冠：与玉玺完全相同（罗马的玉玺，同效果原则示范）
		SMODS.Consumable({
			key = "laurel",
			set = "Tarot",
			cost = 5,
			atlas = "hist_relics",
			pos = { x = 3, y = 0 },
			can_use = function(self, card)
				return HIST.find_crownable() ~= nil
			end,
			use = function(self, card, area, copier)
				local target = HIST.find_crownable()
				if target and HIST.crown(target) then
					card_eval_status_text(target, "extra", nil, nil, nil, {
						message = localize("hist_crowned"),
						colour = G.C.GOLD,
					})
				end
			end,
		}),

		-- 天子剑：选非皇帝 Joker / 扑克牌 / Consumable → 随机强化（设计案 §3.7 映射草案）
		SMODS.Consumable({
			key = "tianzi_sword",
			set = "Tarot",
			cost = 4,
			pos = { x = 1, y = 0 },
			atlas = "hist_relics",
			can_use = function(self, card)
				if G.jokers and #G.jokers.highlighted > 0 then
					local t = G.jokers.highlighted[1]
					if not HIST.is_emperor(t) and not (t.ability and t.ability.hist_absorbed) then
						return true
					end
				end
				if G.hand and #G.hand.highlighted > 0 then
					return true
				end
				if G.consumeables and #G.consumeables.highlighted > 0 then
					return true
				end
				return false
			end,
			use = function(self, card, area, copier)
				local t
				if G.jokers and #G.jokers.highlighted > 0 then
					t = G.jokers.highlighted[1]
				elseif G.hand and #G.hand.highlighted > 0 then
					t = G.hand.highlighted[1]
				elseif G.consumeables and #G.consumeables.highlighted > 0 then
					t = G.consumeables.highlighted[1]
				end
				if not t then
					return
				end
				if t.area == G.jokers then
					-- Joker → 随机版面：foil 40% / holo 40% / poly 20%
					local roll = pseudorandom(pseudoseed("hist_sword"))
					if roll < 0.4 then
						t:set_edition({ foil = true }, true)
					elseif roll < 0.8 then
						t:set_edition({ holo = true }, true)
					else
						t:set_edition({ polychrome = true }, true)
					end
				elseif t.area == G.consumeables then
					-- Consumable → 随机变成另一张（否决负片复制，设计案 §十一.2）
					local pool = {}
					for _, center in ipairs(G.P_CENTER_POOLS.Consumable) do
						if not center.hidden then
							pool[#pool + 1] = center.key
						end
					end
					if #pool > 0 then
						local key = pseudorandom_element(pool, pseudoseed("hist_sword2"))
						local new_card = SMODS.create_card({ key = key, area = G.consumeables })
						if new_card then
							new_card:add_to_deck()
							G.consumeables:emplace(new_card)
							t:start_dissolve()
						end
					end
				else
					-- 扑克牌 → 随机增强：金 / 钢 / 玻璃均分
					local roll = pseudorandom(pseudoseed("hist_sword3"))
					local key = roll < 0.34 and "m_gold" or (roll < 0.67 and "m_steel" or "m_glass")
					t:set_ability(G.P_CENTERS[key], true, nil)
				end
				t:juice_up(0.3, 0.5)
			end,
		}),

		-- 断头台：皇帝 → 还原初始形态 + 返还一张随机登基器物（设计案 §3.5）
		SMODS.Consumable({
			key = "guillotine",
			set = "Tarot",
			cost = 5,
			pos = { x = 2, y = 0 },
			atlas = "hist_relics",
			can_use = function(self, card)
				if not G.jokers then
					return false
				end
				for _, c in ipairs(G.jokers.cards) do
					if HIST.is_emperor(c) then
						return true
					end
				end
				return false
			end,
			use = function(self, card, area, copier)
				local target
				for _, c in ipairs(G.jokers.cards) do
					if HIST.is_emperor(c) then
						target = c
						break
					end
				end
				if not target then
					return
				end
				-- 树倒猢狲散：先放壳（hooks.unswallow_all 归还槽位）
				HIST.unswallow_all(target)
				local special_key = HIST.special_guillotine[target.config.center.key]
				local back_key = HIST.initial_forms[target.config.center.key]
				if special_key then
					-- 特殊例外：路易十六 → 头（不还原——断头台对他是革命，设计案 §五.3）
					target:start_dissolve()
					local head = SMODS.create_card({ key = special_key, area = G.jokers })
					if head then
						head:add_to_deck()
						G.jokers:emplace(head)
						head:juice_up(0.3, 0.5)
					end
				elseif back_key then
					target:set_ability(G.P_CENTERS[back_key], true, nil)
				end
				-- 返还一张随机登基器物
				local pool = {}
				for k in pairs(HIST.crown_items) do
					pool[#pool + 1] = k
				end
				if #pool > 0 then
					local give = pseudorandom_element(pool, pseudoseed("hist_guillotine"))
					local new_card = SMODS.create_card({ key = give, area = G.consumeables })
					if new_card then
						new_card:add_to_deck()
						G.consumeables:emplace(new_card)
					end
				end
				target:juice_up(0.3, 0.5)
			end,
		}),

		-- 匕首：凯撒的结局——弃一张手牌换下一手的爆发（设计案 §五.4 补）
		-- 随机弃 1 张手牌，下一手计分时随机 +1~10 倍率（挂起值由 hooks 的 trigger_effects 消费）
		SMODS.Consumable({
			key = "dagger",
			set = "Tarot",
			cost = 4,
			pos = { x = 4, y = 3 },
			can_use = function(self, card)
				return G.hand ~= nil and #G.hand.cards > 0
			end,
			use = function(self, card, area, copier)
				local hand = G.hand.cards
				if not hand[1] then
					return
				end
				-- 走原版弃牌堆（不销毁），随机挑一张；延迟到消耗牌动画之后动牌区
				local victim = hand[math.random(#hand)]
				G.E_MANAGER:add_event(Event({
					trigger = "after",
					delay = 0.3,
					func = function()
						if victim.area == G.hand then
							victim.ability.discarded = true
							draw_card(G.hand, G.discard, 10, "down", false, victim)
						end
						return true
					end,
				}))
				HIST.pending_mult = math.random(1, 10)
			end,
		}),

		-- 圣火令：标记当前 Boss，再遇同 Boss 禁用其效果（设计案 §3.6；Blind:disable 见 hooks 下方钩子）
		SMODS.Consumable({
			key = "holy_fire",
			set = "Tarot",
			cost = 5,
			atlas = "hist_relics",
			pos = { x = 4, y = 0 },
			can_use = function(self, card)
				local b = G.GAME and G.GAME.blind
				return b and b.config and b.config.blind and b.config.blind.key ~= nil
			end,
			use = function(self, card, area, copier)
				local b = G.GAME.blind
				local key = b.config.key or (b.config.blind and b.config.blind.key)
				if not key then
					return
				end
				G.GAME.hist_holy_fire = G.GAME.hist_holy_fire or {}
				G.GAME.hist_holy_fire[key] = true
				card_eval_status_text(card, "extra", nil, nil, nil, {
					message = localize("hist_fire_marked"),
					colour = G.C.RED,
				})
			end,
		}),

		-- 免死金牌：选一张 Joker，本局它第一次将被销毁时免除（设计案 §十）
		-- 拦截在 hooks 的 start_dissolve 钩子；丹书铁券，发牌的人都死了，对你有用一次
		SMODS.Consumable({
			key = "tieshiquan",
			set = "Tarot",
			cost = 5,
			pos = { x = 7, y = 2 },
			can_use = function(self, card)
				return G.jokers and #G.jokers.highlighted >= 1
			end,
			use = function(self, card, area, copier)
				local target = G.jokers.highlighted[1]
				if target then
					target.ability.hist_exempt = true
					target:add_sticker("hist_exempt", true)
					target:juice_up(0.3, 0.5)
				end
			end,
		}),

		-- 罪己诏：重掷本局的下一个 Boss 盲注（设计案 §十）
		-- 皇帝下罪己诏，老天换一种惩罚；get_new_boss 与 DEBUG_FORCE_BOSS 同源
		SMODS.Consumable({
			key = "zuizhao",
			set = "Tarot",
			cost = 4,
			pos = { x = 8, y = 2 },
			can_use = function(self, card)
				return true
			end,
			use = function(self, card, area, copier)
				if G.GAME.round_resets and G.GAME.round_resets.blind_choices then
					G.GAME.round_resets.blind_choices.Boss = get_new_boss()
				end
				card_eval_status_text(card, "extra", nil, nil, nil, {
					message = localize("hist_zuizhao_msg"),
					colour = G.C.PURPLE,
				})
			end,
		}),

		-- 王冠：登基，第三个来源——中国玉玺/罗马桂冠/欧洲王冠（设计案 §十）
		SMODS.Consumable({
			key = "crown",
			set = "Tarot",
			cost = 5,
			pos = { x = 9, y = 2 },
			can_use = function(self, card)
				return HIST.find_crownable() ~= nil
			end,
			use = function(self, card, area, copier)
				local target = HIST.find_crownable()
				if target and HIST.crown(target) then
					card_eval_status_text(target, "extra", nil, nil, nil, {
						message = localize("hist_crowned"),
						colour = G.C.GOLD,
					})
				end
			end,
		}),

		-- 虎符：兵符在手，先点两张——从牌堆复制 2 张牌加入手牌（设计案 §十）
		SMODS.Consumable({
			key = "hufu",
			set = "Tarot",
			cost = 4,
			pos = { x = 0, y = 3 },
			can_use = function(self, card)
				return G.deck and #G.deck.cards > 0
			end,
			use = function(self, card, area, copier)
				for _ = 1, 2 do
					if not G.deck or #G.deck.cards == 0 then
						break
					end
					local src = pseudorandom_element(G.deck.cards, pseudoseed("hist_hufu"))
					local copy = copy_card(src, nil, nil, true)
					if copy then
						copy:add_to_deck()
						G.hand:emplace(copy)
						copy:juice_up(0.3, 0.5)
					end
				end
			end,
		}),

		-- 和氏璧：它本来就是玉玺的原料，只是还没雕——使用后生成传国玉玺（设计案 §十）
		SMODS.Consumable({
			key = "heshibi",
			set = "Tarot",
			cost = 4,
			pos = { x = 1, y = 3 },
			use = function(self, card, area, copier)
				local new_card = SMODS.create_card({ key = "c_hist_yuxi", area = G.consumeables })
				if new_card then
					new_card:add_to_deck()
					G.consumeables:emplace(new_card)
					new_card:juice_up(0.3, 0.5)
				end
			end,
		}),

		-- 莫诺马赫冠：登基（俄罗斯沙皇传承之冠，设计案 §10.2 家族）
		SMODS.Consumable({
			key = "monomakh",
			set = "Tarot",
			cost = 5,
			pos = { x = 2, y = 3 },
			can_use = function(self, card)
				return HIST.find_crownable() ~= nil
			end,
			use = function(self, card, area, copier)
				local target = HIST.find_crownable()
				if target and HIST.crown(target) then
					card_eval_status_text(target, "extra", nil, nil, nil, {
						message = localize("hist_crowned"),
						colour = G.C.GOLD,
					})
				end
			end,
		}),

		-- 涂油礼：登基（欧洲加冕事件，设计案 §10.2 家族）
		SMODS.Consumable({
			key = "anointing",
			set = "Tarot",
			cost = 5,
			atlas = "hist_relics",
			pos = { x = 5, y = 0 },
			can_use = function(self, card)
				return HIST.find_crownable() ~= nil
			end,
			use = function(self, card, area, copier)
				local target = HIST.find_crownable()
				if target and HIST.crown(target) then
					card_eval_status_text(target, "extra", nil, nil, nil, {
						message = localize("hist_crowned"),
						colour = G.C.GOLD,
					})
				end
			end,
		}),

		-- 卢比孔河（幻灵）：骰子已掷下——本回合所有出牌 X2，但不能弃牌（设计案 §10.3）
		-- X2 与弃牌拦截都在 hooks（initial_scoring_step / discard_cards_from_highlighted）
		SMODS.Consumable({
			key = "rubicon",
			set = "Spectral",
			cost = 5,
			pos = { x = 0, y = 0 },
			can_use = function(self, card)
				return not HIST.rubicon
			end,
			use = function(self, card, area, copier)
				HIST.rubicon = true
				card_eval_status_text(card, "extra", nil, nil, nil, {
					message = localize("hist_rubicon_cross"),
					colour = G.C.RED,
				})
			end,
		}),

		-- 郑和宝船（幻灵 · 2026-09-11 新增批次）：永久给牌组加入 3 张随机牌
		-- 七下西洋带回来的不止是长颈鹿。落点 = 牌组改造，mod 内首次
		-- 实现：create_playing_card(card_init, area, ...)（common_events.lua:2312，补强包同款），
		--   它自己会 add_to_deck、入 G.playing_cards 并 emplace 进 G.deck
		SMODS.Consumable({
			key = "zhenghe",
			set = "Spectral",
			cost = 4,
			pos = { x = 1, y = 0 },
			can_use = function(self, card)
				return G.deck ~= nil
			end,
			use = function(self, card, area, copier)
				if not G.deck then
					return
				end
				for _ = 1, 3 do
					local c = create_playing_card({
						front = pseudorandom_element(G.P_CARDS, pseudoseed("hist_zhenghe")),
						center = G.P_CENTERS.c_base,
					}, G.deck, nil, nil, nil)
					if c then
						c:juice_up(0.3, 0.5)
					end
				end
				card_eval_status_text(card, "extra", nil, nil, nil, {
					message = localize("hist_zhenghe_return"),
					colour = G.C.BLUE,
				})
			end,
		}),

		-- ===== 2026-09-11 第二批次 =====

		-- 交子：北宋的纸币——立刻拿到 $15，代价是下一个 ante 的所有商店涨价 $2
		-- 新机制：跨 ante 的延迟代价（此前所有负面都是即时或永久生效的）
		-- 涨价走 G.GAME.hist_surcharge，hooks 的 Card:set_cost 读取；new_round 跨过该 ante 后清账
		SMODS.Consumable({
			key = "jiaozi",
			set = "Tarot",
			cost = 4,
			pos = { x = 5, y = 2 },
			can_use = function(self, card)
				return true
			end,
			use = function(self, card, area, copier)
				ease_dollars(15)
				G.GAME.hist_surcharge = (G.GAME.hist_surcharge or 0) + 2
				G.GAME.hist_surcharge_ante = (G.GAME.round_resets and G.GAME.round_resets.ante or 0) + 1
				card_eval_status_text(card, "extra", nil, nil, nil, {
					message = localize("hist_jiaozi_print"),
					colour = G.C.MONEY,
				})
			end,
		}),

		-- 琥珀屋：给一张小丑镶金——出售价值 +$8；若它是永恒的，本局可被破例卖掉一次
		-- 新机制：出售价值与"永恒可破例"（此前永恒在本 mod 里完全不可绕过）
		-- extra_value 是原版出售价公式的加数（card.lua:526），set_cost() 重算；
		-- 出售放行在 hooks 的 Card:can_sell_card（琥珀屋分支优先于永恒检查）
		SMODS.Consumable({
			key = "amber_room",
			set = "Spectral",
			cost = 4,
			pos = { x = 2, y = 0 },
			can_use = function(self, card)
				return G.jokers ~= nil and #G.jokers.highlighted > 0
			end,
			use = function(self, card, area, copier)
				local t = G.jokers and G.jokers.highlighted[1]
				if not t then
					return
				end
				t.ability.extra_value = (t.ability.extra_value or 0) + 8
				t:set_cost()
				t.ability.hist_amber = true
				t:add_sticker("hist_amber", true)
				t:juice_up(0.3, 0.5)
				card_eval_status_text(t, "extra", nil, nil, nil, {
					message = localize("hist_amber_gilt"),
					colour = G.C.MONEY,
				})
			end,
		}),
	},
}