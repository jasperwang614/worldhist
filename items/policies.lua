-- items/policies.lua — 政策 Voucher 线（对应设计案 §八）
-- 占位图：不写 atlas，pos 指原版 Voucher 图集帧

return {
	items = {
		-- 郡县制：每吞并 1 个小丑，小丑上限 +1（设计案 §3.8；吞并本身 +1 补偿，本券再加 1 → 扩张）
		-- 购买时按已吞数补发
		SMODS.Voucher({
			key = "junxian",
			cost = 10,
			atlas = "hist_vouchers",
			pos = { x = 1, y = 0 },
			apply_to_run = function(self)
				local n = 0
				if G.jokers then
					for _, c in ipairs(G.jokers.cards) do
						if c.ability.hist_absorbed then
							n = n + 1
						end
					end
				end
				if n > 0 then
					HIST.change_joker_limit(n)
				end
			end,
		}),

		-- 石人一只眼：打出的牌型为高牌时，重新触发所有革命者小丑（设计案 §八）
		-- 效果在 hooks 的 calculate_joker 包装里实现（HIST.revolutionary_keys）
		SMODS.Voucher({
			key = "stone_eye",
			cost = 10,
			atlas = "hist_vouchers",
			pos = { x = 0, y = 0 },
		}),

		-- 大宪章：每回合开始，随机一张 Joker 获"人身保护"——王权也进了法律（设计案 §八）
		-- 发放与回收在 hooks 的 new_round/set_debuff/start_dissolve 三处
		SMODS.Voucher({
			key = "magna_carta",
			cost = 10,
			atlas = "hist_vouchers",
			pos = { x = 2, y = 0 },
		}),

		-- 九十五条论纲：每回合第一次重掷免费——赎罪券？不用买了（设计案 §八）
		-- 挂在 hooks 的 reroll_shop 包装
		SMODS.Voucher({
			key = "95thesis",
			cost = 10,
			atlas = "hist_vouchers",
			pos = { x = 3, y = 0 },
		}),

		-- 献土：小丑上限 -1，回合结束 +$5——割地换和平，负面条款首例（设计案 §八）
		-- 上限在 apply_to_run；钱在 hooks 的 HIST.calculate
		SMODS.Voucher({
			key = "xiantu",
			cost = 8,
			atlas = "hist_vouchers",
			pos = { x = 4, y = 0 },
			apply_to_run = function(self)
				HIST.change_joker_limit(-1)
			end,
		}),

		-- 屯田：回合结束时每剩 1 次出牌次数 +$1——闲时屯田（设计案 §八）
		-- 钱在 hooks 的 HIST.calculate
		SMODS.Voucher({
			key = "tuntian",
			cost = 8,
			atlas = "hist_vouchers",
			pos = { x = 5, y = 0 },
		}),

		-- 分封制：小丑上限 +1；小丑售价减半——封了藩镇，卖地不值钱（设计案 §八）
		-- 售价在 hooks 的 set_cost 包装
		SMODS.Voucher({
			key = "fengjian",
			cost = 8,
			atlas = "hist_vouchers",
			pos = { x = 6, y = 0 },
			apply_to_run = function(self)
				HIST.change_joker_limit(1)
			end,
		}),

		-- 梭伦改革：手牌上限 +2；回合开始 -$2——解除债务奴隶的赎金（设计案 §八）
		-- 回合开始的赎金在 hooks 的 new_round
		SMODS.Voucher({
			key = "solon",
			cost = 8,
			atlas = "hist_vouchers",
			pos = { x = 7, y = 0 },
			apply_to_run = function(self)
				G.hand:change_size(2)
			end,
		}),

		-- 常平仓：金钱归零时回合结束 +$15，每局 2 次——谷贱籴、谷贵粜（设计案 §八）
		-- 结算在 hooks 的 HIST.calculate
		SMODS.Voucher({
			key = "changping",
			cost = 8,
			atlas = "hist_vouchers",
			pos = { x = 8, y = 0 },
		}),

		-- 拿破仑法典：每回合第一手牌的牌型按法律升一级——法律把你的牌扶正（设计案 §八）
		-- 结算在 hooks 的 HIST.calculate（initial_scoring_step 补一级的 l_chips/l_mult）
		SMODS.Voucher({
			key = "code_napoleon",
			cost = 10,
			atlas = "hist_vouchers",
			pos = { x = 9, y = 0 },
		}),

		-- 吕底亚铸币：史上第一批钱币——商店内所有卡牌与补强价格 -1（设计案 §八候选转正）
		-- 结算在 hooks 的 set_cost 包装
		-- 吕底亚铸币：史上第一批钱币——商店内所有卡牌与补强价格 -1（设计案 §八）
		-- 价格修正走 hooks 的 Card:set_cost（读 used_vouchers），这里无需 apply_to_run
		SMODS.Voucher({
			key = "lydia",
			cost = 8,
			atlas = "hist_vouchers",
			pos = { x = 0, y = 1 },
		}),

		-- 圈地运动：手牌上限 -1；回合结束 +$3——羊吃人，钱进圈（设计案 §八候选转正）
		-- 钱在 hooks 的 HIST.calculate
		SMODS.Voucher({
			key = "enclosure",
			cost = 8,
			atlas = "hist_vouchers",
			pos = { x = 1, y = 1 },
			apply_to_run = function(self)
				G.hand:change_size(-1)
			end,
		}),

		-- ===== 2026-09-11 新增批次：商店 / 槽位 / 行动次数 / 牌型等级 四条未开垦轴 =====

		-- 汉萨同盟：商店商品槽 +1——行会打通了北海到波罗的海的柜台
		-- 实现：change_shop_size(1)（common_events.lua:1443，原版 Overstock 同款 card.lua:2232）
		SMODS.Voucher({
			key = "hansa",
			cost = 10,
			atlas = "hist_vouchers",
			pos = { x = 2, y = 1 },
			apply_to_run = function(self)
				-- 原版同款：放进事件里跑，等商店结构就位再改（change_shop_size 自带 G.GAME.shop 判空）
				G.E_MANAGER:add_event(Event({
					func = function()
						change_shop_size(1)
						return true
					end,
				}))
			end,
		}),

		-- 亚历山大图书馆：消耗牌槽位 +1——它装得下整个地中海的记忆
		-- 实现：G.consumeables:change_size(1)（原版 Crystal Ball 走 config.card_limit，card.lua:2259；
		--   本 mod 统一走 change_size，与 G.jokers 的记账口径一致）
		SMODS.Voucher({
			key = "library",
			cost = 10,
			atlas = "hist_vouchers",
			pos = { x = 3, y = 1 },
			apply_to_run = function(self)
				if G.consumeables then
					G.consumeables:change_size(1)
				end
			end,
		}),

		-- 蒙古驿站（站赤）：每回合 +1 次出牌——帝国的速度就是驿站的距离
		-- 实现：原版 Grabber 同款（card.lua:2282）：round_resets.hands +1 并 ease_hands_played(1)
		SMODS.Voucher({
			key = "yam",
			cost = 10,
			atlas = "hist_vouchers",
			pos = { x = 4, y = 1 },
			apply_to_run = function(self)
				if G.GAME and G.GAME.round_resets then
					G.GAME.round_resets.hands = G.GAME.round_resets.hands + 1
					ease_hands_played(1)
				end
			end,
		}),

		-- 科举制：每回合结束时，本回合打出次数最多的牌型升一级——考什么，什么就涨
		-- 实现：牌型计数在 hooks 的 evaluate_play 包装，升级走 level_up_hand（详见 HIST.keju_graduate）
		SMODS.Voucher({
			key = "keju",
			cost = 10,
			atlas = "hist_vouchers",
			pos = { x = 5, y = 1 },
		}),

		-- ===== 2026-09-11 第二批次 =====

		-- 东印度公司：回合结束时，存款每 $10 生 $1 利息，每回合上限 $5
		-- 新轴：本 mod 唯一的"利息"机制（此前只有固定发放与门槛发放两种钱）
		-- 与常平仓（没钱给钱）互补：一个鼓励存钱，一个兜底救急；结算在 hooks 的 HIST.calculate
		SMODS.Voucher({
			key = "eic",
			cost = 10,
			atlas = "hist_vouchers",
			pos = { x = 6, y = 1 },
		}),

		-- 光荣革命：每回合开始，最右侧的小丑被议会架空（本回合静默）；
		--           作为交换，每张仍在说话的小丑使本手牌 +20 筹码
		-- 新机制：把"静默"变成可交易的资源——玩家靠摆位控制代价，靠堆小丑放大收益
		-- 静默发放走 hooks 的 HIST.glorious_silence（set_blind），筹码加成在 HIST.calculate；
		-- 静默判定统一走 HIST.is_silenced（与罗伯斯庇尔的"嫌疑"同一通道）
		SMODS.Voucher({
			key = "glorious",
			cost = 10,
			atlas = "hist_vouchers",
			pos = { x = 7, y = 1 },
		}),
	},
}
