-- items/hooks.lua — 登基 / 吞并 / 庇护系统（对应设计案 §2.1/§2.2，开发规范 §5.2）
-- 吞并系统的所有状态读写只经过本文件的函数（开发规范 §10）。
-- 会话内状态放 HIST（不序列化）；跨存档状态只存卡自身的 ability（原版序列化）。

HIST = HIST or SMODS.current_mod

-- ============ 数值 ============

-- 元老：皇帝触发效果时，场上每位带 hist_senator 角标的小丑各 +N 倍率（凯撒登基时授予左右邻座）
HIST.SENATOR_MULT = 8

-- ============ 时局计分规则（数据在 items/omens.lua 的池子里）============
-- lock_suit：只有该花色参与计分。
--   挂点是 G.FUNCS.get_poker_hand_info 的返回值——原版 evaluate_play 的计分循环
--   只遍历它返回的 scoring_hand（state_events.lua），smods 也重写了同一个函数，
--   返回值结构一致（overrides.lua:1575）。预览和结算共用这一个入口，
--   所以过滤是无条件的：UI 上看到多少分，结算就是多少分。
local OMEN_LOCK_SUIT = {
	court_of_hearts = "Hearts",
	spade_empire = "Spades",
}

function HIST.omen_lock_suit()
	local k = G.GAME and G.GAME.hist_omen
	return k and OMEN_LOCK_SUIT[k] or nil
end

function HIST.omen_score()
	local k = G.GAME and G.GAME.hist_omen
	local o = k and HIST.omens and HIST.omens[k]
	if not o then
		return nil
	end
	-- 大清洗的收益绑定"确实烧掉了一个花色"：牌组薄到没烧成时不给 +20 筹码，
	-- 否则就成了"付不出代价却照拿收益"。
	if k == "purge_suit" and not (G.GAME and G.GAME.hist_purged_suit) then
		return nil
	end
	return o.score
end

local get_poker_hand_info_ref = G.FUNCS.get_poker_hand_info
function G.FUNCS.get_poker_hand_info(cards, ...)
	local a, b, c, d, e = get_poker_hand_info_ref(cards, ...)
	local suit = HIST.omen_lock_suit()
	if suit and type(d) == "table" then
		local keep = {}
		for _, card in ipairs(d) do
			if card.base and card.base.suit == suit then
				keep[#keep + 1] = card
			end
		end
		d = keep
	end
	return a, b, c, d, e
end

-- Splash（原版小丑「水花」）会绕开上面的花色过滤。
-- 原版 evaluate_play 拿到 scoring_hand 之后还有一段（state_events.lua）：
--     if next(find_joker('Splash')) then scoring_hand[i] = G.play.cards[i] end
-- 也就是只要场上有 Splash，打出的每一张牌都会重新进入计分表，
-- 锁花色的代价当场归零（还白拿红桃 +4 / 黑桃 +50）。
-- find_joker 是全局函数（functions/misc_functions.lua），返回小丑表，调用方用 next() 判空；
-- 锁花色时让它返回空表，Splash 就"不存在"了。
-- ★ 不用包装 evaluate_play：smods 的 Blind:debuff_hand（overrides.lua:2584）也调 find_joker('Splash')
--   来算 Boss 的废牌型范围，包这一层两条路径同时生效，口径一致。
-- ★ 石头牌另说：它没有花色（原版把纯筹码牌视作不依赖花色），锁花色时仍按原版逻辑计分，
--   但拿不到 +50/+4 的花色加成（下面 get_chip_bonus / get_chip_mult 有花色判定）。
-- ★ 幂等标记：mod 重载时 hooks.lua 会再执行一遍，没有标记就会把包装套在自己身上，无限递归。
if not _G.HIST_FIND_JOKER_WRAPPED and type(find_joker) == "function" then
	_G.HIST_FIND_JOKER_WRAPPED = true
	local find_joker_ref = find_joker
	function find_joker(name, ...)
		if name == "Splash" and HIST.omen_lock_suit() then
			return {}
		end
		return find_joker_ref(name, ...)
	end
end

-- 察举制：所有牌型升级效果翻倍。level_up_hand 是全局函数（common_events.lua），
-- 包在这里后，星球牌 / 券 / 小丑等所有升级来源都多升 1 级。
local level_up_hand_ref = level_up_hand
function level_up_hand(card, hand, instant, amount)
	local amt = amount or 1
	if G.GAME and G.GAME.hist_omen == "meritocracy" then
		amt = amt + 1
	end
	return level_up_hand_ref(card, hand, instant, amt)
end

-- 时局计分加成（血色宫廷 / 黑铁时代 / 大清洗）
-- ★ 必须挂在 get_chip_bonus / get_chip_mult 上，不能挂 calculate_joker：
--   原版 eval_card 把扑克牌 calculate_joker 的返回值塞进 ret.jokers 子表，
--   而 evaluate_play 的计分循环只读 effects[ii].chips / .mult 这两个**顶层**字段，
--   并不会展开 jokers 子表 —— 从 calculate_joker 加数是无效的。
--   get_chip_bonus / get_chip_mult 的返回值才是真正进计分池的数值。
local get_chip_bonus_ref = Card.get_chip_bonus
function Card:get_chip_bonus()
	local n = get_chip_bonus_ref(self)
	local s = HIST.omen_score()
	if s and s.chips and not self.debuff
		and (not s.suit or (self.base and self.base.suit == s.suit))
	then
		n = n + s.chips
	end
	return n
end

local get_chip_mult_ref = Card.get_chip_mult
function Card:get_chip_mult()
	local n = get_chip_mult_ref(self)
	local s = HIST.omen_score()
	-- 幸运牌未触发时 get_chip_mult 返回 0，这不是"基础倍率 0"，不能往上加
	local lucky_miss = self.ability and self.ability.effect == "Lucky Card" and not self.lucky_trigger
	if s and s.mult and not self.debuff and not lucky_miss
		and (not s.suit or (self.base and self.base.suit == s.suit))
	then
		n = n + s.mult
	end
	return n
end

-- ============ 判定 ============

-- 皇帝判定：只有皇帝形态算皇帝（设计案 §2.1 补充拍板）
function HIST.is_emperor(card)
	return card
		and card.config
		and card.config.center
		and HIST.emperor_keys[card.config.center.key]
		or false
end

-- 返回场上第一张可登基人物（v1 只有一对形态；多形态后改返回列表交给器物选目标）
function HIST.find_crownable()
	if not G.jokers then
		return nil
	end
	for _, c in ipairs(G.jokers.cards) do
		if c.config and c.config.center and HIST.forms[c.config.center.key] then
			return c
		end
	end
	return nil
end

-- 场上是否存在皇帝形态（蒙恬、罗伯斯庇尔等"皇帝在场"判定用）
function HIST.emperor_present()
	if not G.jokers then
		return false
	end
	for _, c in ipairs(G.jokers.cards) do
		if HIST.is_emperor(c) then
			return true
		end
	end
	return false
end

-- 指定 key 的皇帝是否在场（路易十六通胀用）
function HIST.emperor_key_present(key)
	if not G.jokers then
		return false
	end
	for _, c in ipairs(G.jokers.cards) do
		if c.config and c.config.center and c.config.center.key == key then
			return true
		end
	end
	return false
end

-- 空着的小丑槽位数（伊壁鸠鲁的"闲适"用；吞并释放的槽位算空位，天然协同）
function HIST.empty_joker_slots()
	if not G.jokers then
		return 0
	end
	local limit = G.jokers.config and G.jokers.config.card_limit or 0
	return math.max(0, limit - #G.jokers.cards)
end

-- 某张小丑左右相邻的小丑数量（苏秦"合纵"用；位置机制，场上顺序即 G.jokers.cards 顺序）
function HIST.neighbour_count(card)
	if not (G.jokers and card) then
		return 0
	end
	local cards = G.jokers.cards
	local n = 0
	for i, c in ipairs(cards) do
		if c == card then
			if cards[i - 1] then
				n = n + 1
			end
			if cards[i + 1] then
				n = n + 1
			end
			break
		end
	end
	return n
end

-- 质数判定（毕达哥拉斯"万物皆数"用；点数之和最小 2 张×A14=…，上界不设）
function HIST.is_prime(n)
	n = math.floor(n or 0)
	if n < 2 then
		return false
	end
	if n % 2 == 0 then
		return n == 2
	end
	local i = 3
	while i * i <= n do
		if n % i == 0 then
			return false
		end
		i = i + 2
	end
	return true
end

-- ★ 统一静默判定：罗伯斯庇尔的"嫌疑"与光荣革命的"议会架空"走同一条静默通道
--   两者都只让小丑不结算，不动 debuff（避免和原版每手 debuff 重算打架）
function HIST.is_silenced(card)
	if not card then
		return false
	end
	if HIST.suspect_card == card then
		return true
	end
	return (card.ability and card.ability.hist_silenced) or false
end

-- ★ 光荣革命（Voucher）：每回合开始，最右侧的小丑被议会架空——本回合静默
--   只静默一张、且总是最右（玩家可控：把想保的往左挪），代价可预期
function HIST.glorious_silence()
	if not (G.jokers and G.jokers.cards) then
		return
	end
	for _, c in ipairs(G.jokers.cards) do
		if c.ability.hist_silenced then
			c.ability.hist_silenced = nil
			c:remove_sticker("hist_silenced")
		end
	end
	if G.GAME.used_vouchers and G.GAME.used_vouchers["v_hist_glorious"] and #G.jokers.cards > 0 then
		local last = G.jokers.cards[#G.jokers.cards]
		last.ability.hist_silenced = true
		last:add_sticker("hist_silenced", true)
	end
end

-- ============ 登基 ============

-- 凯撒登基：左右相邻的小丑获授"元老"角标（皇帝触发效果时，每位元老 +SENATOR_MULT 倍率）
-- 只授给普通小丑：皇帝不吃皇帝，被吞并的壳已有主人，都不授衔
function HIST.roman_senate(caesar)
	if not (G.jokers and caesar) then
		return
	end
	local idx
	for i, c in ipairs(G.jokers.cards) do
		if c == caesar then
			idx = i
			break
		end
	end
	if not idx then
		return
	end
	local granted = 0
	for _, i in ipairs({ idx - 1, idx + 1 }) do
		local c = G.jokers.cards[i]
		if c and c ~= caesar
			and not HIST.is_emperor(c)
			and not (c.ability and c.ability.hist_absorbed)
			and not (c.ability and c.ability.hist_senator)
		then
			c.ability.hist_senator = true
			c:add_sticker("hist_senator", true)
			c:juice_up(0.3, 0.5)
			granted = granted + 1
		end
	end
	return granted
end

-- 登基：人物 → 皇帝形态（同一张卡转形态，站位/版面保留），随即吞并全场（登朝）
function HIST.crown(card)
	if not (card and card.config and card.config.center) then
		return false
	end
	local emperor_key = HIST.forms[card.config.center.key]
	if not emperor_key or HIST.is_emperor(card) then
		return false
	end
	-- set_ability(center, initial, delay_sprites)：initial=true 不广播 setting_ability（smods overrides.lua:2701）
	card:set_ability(G.P_CENTERS[emperor_key], true, nil)
	-- 登朝即吞并为秦始皇专属（设计案 §2.1）：只有登记在 coronation_swallow 的皇帝才吞全场
	if HIST.coronation_swallow[emperor_key] then
		HIST.swallow_all(card)
	end
	-- 凯撒：登基即召开元老院——左右邻座受衔（元老效果见 Card:calculate_joker 包装）
	if emperor_key == "j_hist_caesar" then
		HIST.roman_senate(card)
	end
	card:juice_up(0.3, 0.5)
	return true
end

-- ============ 吞并（套壳）============

-- ★ 槽位增减的唯一通道：CardArea:change_size(delta)。
--   1.0.1o 的 config.card_limit 是元表虚字段（cardarea.lua:13）：读 = total_slots - extra_slots_used
--   （可能过期），写 = 只改 card_limits.mod、不刷 total_slots——直接 "+1" 读到过期值会被吞，
--   两次吞并 mod 只剩 1（实测 HUD 卡在 3/6 的根因）。change_size 的 SMODS bypass 正确累加 mod
--   （cardarea.lua:114），再镜像 smods utils.lua:3696 的公式立即刷新 total_slots。
function HIST.change_joker_limit(delta)
	if not G.jokers then
		return
	end
	G.jokers:change_size(delta)
	local cl = G.jokers.config.card_limits
	if cl then
		-- 同上兜底：字段缺失时这里设置的 total_slots 与元表读 card_limit 都会算错
		if cl.extra_slots_used == nil then
			cl.extra_slots_used = 0
		end
		cl.total_slots = (cl.extra_slots or 0) + (cl.base or 0) + (cl.mod or 0)
	end
	HIST.expected_limit = G.jokers.config.card_limit
end

-- 吞并一个小丑：打标 + 角标 + 释放槽位 + 记清单 + 会话内反向链接
-- 皇帝与壳都留在 G.jokers，序列化天然安全；断头台/出售皇帝时 unswallow_all 原地复活。
function HIST.swallow(emperor, target)
	if not (emperor and target and target ~= emperor) then
		return false
	end
	-- 皇帝不吃皇帝（设计案 §2.2）；一仆不事二主
	if HIST.is_emperor(target) or (target.ability and target.ability.hist_absorbed) then
		return false
	end
	target.ability.hist_absorbed = true
	target.hist_emperor = emperor -- 仅会话内，读档后由 start_run 钩子重建
	target:add_sticker("hist_swallowed", true)
	-- 吞并即释放槽位：壳仍占一个计数位（仍在 G.jokers.cards，判定是 #cards < card_limit），
	-- 所以走负片版同款的 +1 补偿记账（dump Card.lua:551 negative 分支同向）；
	-- 郡县制 Voucher 再 +1：吞并即扩张（设计案 §10.2，见 policies.lua）
	-- 吞并即释放：+1 补偿（壳仍占计数位）；郡县制再 +1（吞并即扩张）
	-- 不看 added_to_deck：壳恰处于 debuff 瞬窗（原版 remove_from_deck(true) 会让它变 false）时
	-- 也要照常计账，否则此时吞并会永久漏账；hist_limit_applied 标志保证收支严格对称
	--
	-- 负片壳例外：负片自身已经由原版 add_to_deck 的 edition.negative 分支 +1 自由槽，
	-- 我们的补偿不再叠加（否则双重腾位）；它的收费/回收也全权交还原版
	target.hist_limit_applied = nil
	target.hist_junxian_applied = nil
	if not (target.edition and target.edition.negative) then
		HIST.change_joker_limit(1)
		target.hist_limit_applied = true
	end
	if G.GAME.used_vouchers and G.GAME.used_vouchers["v_hist_junxian"] then
		HIST.change_joker_limit(1)
		target.hist_junxian_applied = true
	end
	HIST.dbg(("[worldhist] swallow %s(neg=%s) -> limit=%d cards=%d"):format(
		target.config.center.key, tostring(target.edition and target.edition.negative),
		G.jokers.config.card_limit, #G.jokers.cards))
	local e = emperor.ability.extra
	e.absorbed = e.absorbed or {}
	e.absorbed[#e.absorbed + 1] = target.config.center.key
	target:juice_up(0.3, 0.5)
	return true
end

-- 登朝：吞并场上所有可吞小丑
function HIST.swallow_all(emperor)
	if not G.jokers then
		return
	end
	for _, c in ipairs(G.jokers.cards) do
		if c ~= emperor then
			HIST.swallow(emperor, c)
		end
	end
end

-- 政变：把壳从一个皇帝手里夺给另一个（叶卡捷琳娜，设计案 §六.4）
-- 槽位补偿跟壳走不动账（壳本来就是免占位状态），只改归属与双方清单
function HIST.steal_shell(new_emperor, shell)
	local old = shell.hist_emperor
	if not (old and old ~= new_emperor) then
		return false
	end
	if old.ability.extra and old.ability.extra.absorbed then
		for i, k in ipairs(old.ability.extra.absorbed) do
			if k == shell.config.center.key then
				table.remove(old.ability.extra.absorbed, i)
				break
			end
		end
	end
	local e = new_emperor.ability.extra
	e.absorbed = e.absorbed or {}
	e.absorbed[#e.absorbed + 1] = shell.config.center.key
	shell.hist_emperor = new_emperor
	shell:juice_up(0.3, 0.5)
	return true
end

-- 解除吞并（出售/断头台/皇帝被毁）：恢复独立 + 归还槽位（树倒猢狲散）
function HIST.unswallow_all(emperor)
	if not G.jokers then
		return
	end
	for _, c in ipairs(G.jokers.cards) do
		if c.ability.hist_absorbed and c.hist_emperor == emperor then
			c.ability.hist_absorbed = nil
			c.hist_emperor = nil
			c:remove_sticker("hist_swallowed")
			-- 对称回收：只看已计账标志（负片壳没有补偿账，这里自动跳过；郡县制按各自标志收）
			if c.hist_limit_applied then
				c.hist_limit_applied = nil
				HIST.change_joker_limit(-1)
			end
			if c.hist_junxian_applied then
				c.hist_junxian_applied = nil
				HIST.change_joker_limit(-1)
			end
			HIST.dbg(("[worldhist] unswallow %s -> limit=%d"):format(
				c.config.center.key, G.jokers.config.card_limit))
		end
	end
	emperor.ability.extra.absorbed = {}
	HIST.expected_limit = G.jokers.config.card_limit
	HIST.dbg(("[worldhist] unswallow_all -> limit=%d cards=%d"):format(
		G.jokers.config.card_limit, #G.jokers.cards))
end

-- ============ 全局钩子 ============

-- ★ 槽位字段兜底（2026-09-14 崩溃修复）
--   smods src/utils.lua:3662 直接拿 card_limits.extra_slots_used 做算术，且没有 or 0 保护
--   （原版元表读 card_limit 有 or 0 保护，smods 这一行没有）。该字段只在
--   `if not G.TAROT_INTERRUPT then` 分支里赋值，而 G.TAROT_INTERRUPT 在使用消耗牌期间
--   等于 G.STATE（button_callbacks.lua:2212）。于是：某 joker 区的第一次 update 若正好
--   落在消耗牌结算期间（本 mod 的断头台就是消耗牌），字段永远是 nil -> 每帧 update 崩：
--   "utils.lua:3662: attempt to perform arithmetic on field 'extra_slots_used' (a nil value)"
--   这里在每次调用前补 0（兜住所有创建路径：init、读档 load、其它 mod 新建区），
--   并打印一次现场信息便于确认根因。
local HIST_slot_fix_logged = false
local handle_card_limit_ref = CardArea.handle_card_limit
function CardArea:handle_card_limit(...)
	local cl = self.config and self.config.card_limits
	if cl and cl.extra_slots_used == nil then
		cl.extra_slots_used = 0
		if not HIST_slot_fix_logged then
			HIST_slot_fix_logged = true
			HIST.dbg(("[worldhist] slot fix: extra_slots_used 补 0 (type=%s, is_G.jokers=%s, TAROT_INTERRUPT=%s)")
				:format(
					tostring(self.config and self.config.type),
					tostring(G.jokers and self == G.jokers),
					tostring(G.TAROT_INTERRUPT)
				))
		end
	end
	return handle_card_limit_ref(self, ...)
end

-- ★ 统一代发的门：被吞小丑静默，只有皇帝派发期间放行（HIST.dispatching 标志）
--   挂在 Card:calculate_joker 上：原版 1.0.1o 没有 Card:calculate，小丑结算全部走这里
--   （dump Card.lua:2655，smods overrides.lua:2693 在其外再包一层）。
--   副作用：皇帝（及壳）被 Boss debuff 时 calculate_joker 提前返回 → 帝国停摆（设计案 §一.5，自动成立）
local card_calculate_joker_ref = Card.calculate_joker
function Card:calculate_joker(context, ...)
	if self.ability and self.ability.hist_absorbed and not HIST.dispatching then
		return nil
	end
	-- 静默：被标记小丑本回合不结算（罗伯斯庇尔的"嫌疑"、光荣革命的"议会架空"）
	-- 与吞并门同一通道，皇帝代发时不拦截
	if HIST.is_silenced(self) and not HIST.dispatching then
		return nil
	end
	local ret = card_calculate_joker_ref(self, context, ...)
	-- 时局·军国主义：所有 X 倍率效果 ×1.25。
	-- 跳过蓝图/幻灵：它们自己不算 X 倍率，复制目标时目标卡的包装已经乘过一次。
	if ret and type(ret) == "table" and context.joker_main
		and G.GAME.hist_omen == "militarism"
		and self.ability and self.ability.set == "Joker"
		and self.ability.name ~= "Blueprint" and self.ability.name ~= "Brainstorm"
	then
		for _, k in ipairs({"xmult", "x_mult", "Xmult"}) do
			if type(ret[k]) == "number" and ret[k] ~= 1 then
				ret[k] = ret[k] * 1.25
			end
		end
	end
	-- ★ 元老（凯撒登基时授予邻座）：**皇帝触发效果时**，场上每位元老各 +SENATOR_MULT 倍率。
	--   触发者是皇帝，元老自己计分时不产生任何额外效果——所以这段放在 ret 出来之后，
	--   且条件里判的是 self（当前结算的这张卡）是不是皇帝。
	--   皇帝若被 debuff / 被噤声（ret == nil，原版提前返回），元老自然也不加。
	--   每位元老单独发 effect（不并进皇帝的 ret）：这样 +8 飘字和数字动画落在元老自己身上，
	--   而不是借用皇帝那张卡的反馈。
	if context.joker_main and type(ret) == "table" and HIST.is_emperor(self) then
		for _, c in ipairs(G.jokers and G.jokers.cards or {}) do
			if c.ability and c.ability.hist_senator
				and not c.ability.hist_absorbed
				and not c.debuffed
				and not HIST.is_silenced(c)
			then
				SMODS.calculate_effect({
					mult = HIST.SENATOR_MULT,
					message = localize("hist_senator_raise"),
					colour = G.C.MULT,
					card = c,
				}, c)
			end
		end
	end
	-- 石人一只眼（Voucher）：打出的牌型为高牌时，重新触发所有革命者小丑（设计案 §八）
	-- 实现：对原卡再结算一次，额外效果经 calculate_effect 转发；
	-- 蓝图/幻灵卡的 center.key 不是革命者 → 只翻原卡本尊
	if ret and not HIST.dispatching
		and context.joker_main
		and context.scoring_name == "High Card"
		and HIST.revolutionary_keys[self.config.center.key]
		and G.GAME.used_vouchers and G.GAME.used_vouchers["v_hist_stone_eye"]
	then
		local ret2 = card_calculate_joker_ref(self, context, ...)
		if ret2 then
			SMODS.calculate_effect(ret2, self)
		end
	end
	return ret
end

-- ★ 庇护：被吞小丑不可出售（售出按钮置灰；vanilla Card.lua:1975）
local can_sell_ref = Card.can_sell_card
function Card:can_sell_card(context)
	-- 周厉王·弭谤：本回合道路以目，什么都卖不得（设计案 §九）
	if G.GAME.blind and G.GAME.blind.config and G.GAME.blind.config.blind
		and G.GAME.blind.config.blind.key == "bl_hist_zhouliwang"
	then
		return false
	end
	-- 琥珀屋：被点过的小丑身价翻倍且本局可破例出售一次，连永恒也能卖（设计案 §器物）
	if self.ability and self.ability.hist_amber then
		return true
	end
	if self.ability and self.ability.hist_absorbed then
		return false
	end
	return can_sell_ref(self, context)
end

-- ★ 结绳记事·印加（Boss）：本盲注内不能使用任何消耗牌（card.lua:1840 是唯一的可用性入口）
--   一个没有文字的帝国，靠绳结记账——你的塔罗、星球、器物在这片土地上都读不出来
local can_use_consumeable_ref = Card.can_use_consumeable
function Card:can_use_consumeable(any_state, skip_check)
	if G.GAME and G.GAME.blind and G.GAME.blind.config and G.GAME.blind.config.blind
		and G.GAME.blind.config.blind.key == "bl_hist_inca"
	then
		return false
	end
	return can_use_consumeable_ref(self, any_state, skip_check)
end

-- ★ 出售钩子：卖皇帝先放壳（树倒猢狲散）；路易十六的头在革命者 Boss 战中出售 → 终结该 Blind
--   （blind:defeat 与 Cryptid lib/modifiers.lua:411 同款；revolution_bosses 罗伯斯庇尔加入后生效）
local sell_card_ref = Card.sell_card
function Card:sell_card()
	if self.config
		and self.config.center
		and self.config.center.key == "j_hist_louis_head"
		and G.GAME.blind
		and G.GAME.blind.config
		and G.GAME.blind.config.blind
		and HIST.revolution_bosses[G.GAME.blind.config.blind.key]
	then
		G.GAME.blind:defeat()
	end
	if HIST.is_emperor(self) then
		HIST.unswallow_all(self)
	end
	return sell_card_ref(self)
end

-- ★ 点击交互：点皇帝进入吞并模式 → 再点任意小丑完成吞并；再点皇帝取消。
--   （Cryptid items/pointer.lua Card:click 包装同款先例）
local card_click_ref = Card.click
function Card:click()
	-- 拿破仑：自己加冕——点击可自登基人物即登基，无需器物（设计案 §六.2）
	if self.config and self.config.center
		and HIST.self_crowning[self.config.center.key]
		and self.area == G.jokers
	then
		HIST.crown(self)
		return
	end
	if HIST.is_emperor(self) and self.area == G.jokers then
		if HIST.eat_mode == self then
			HIST.eat_mode = nil
		else
			HIST.eat_mode = self
			card_eval_status_text(self, "extra", nil, nil, nil, {
				message = localize("hist_eat_prompt"),
				colour = G.C.GOLD,
			})
		end
		return
	end
	-- 叶卡捷琳娜：政变——点击她进入抢壳模式，再点击别人的壳夺走（设计案 §六.4）
	if self.config and self.config.center
		and self.config.center.key == "j_hist_catherine"
		and self.area == G.jokers
	then
		if HIST.steal_mode == self then
			HIST.steal_mode = nil
		else
			HIST.steal_mode = self
			card_eval_status_text(self, "extra", nil, nil, nil, {
				message = localize("hist_steal_prompt"),
				colour = G.C.GOLD,
			})
		end
		return
	end
	if HIST.steal_mode and self.area == G.jokers
		and self.ability and self.ability.hist_absorbed
		and self.hist_emperor and self.hist_emperor ~= HIST.steal_mode
	then
		if HIST.steal_shell(HIST.steal_mode, self) then
			HIST.steal_mode = nil
		end
		return
	end
	if HIST.eat_mode and self.area == G.jokers and self ~= HIST.eat_mode then
		local emperor = HIST.eat_mode
		if HIST.swallow(emperor, self) then
			HIST.eat_mode = nil
			card_eval_status_text(emperor, "extra", nil, nil, nil, {
				message = localize("hist_swallowed_msg"),
				colour = G.C.GOLD,
			})
		end
		return
	end
	return card_click_ref(self)
end

-- ★ 壳离场兜底：已计账的壳若未解除就被移出牌组（销毁类效果），在这里对称收回
local remove_from_deck_ref = Card.remove_from_deck
function Card:remove_from_deck(from_debuff)
	remove_from_deck_ref(self, from_debuff)
	-- from_debuff=true 是 debuff 瞬窗，不算真离场（负片版同款口径）
	if not from_debuff and self.ability and self.ability.hist_absorbed and self.hist_limit_applied then
		self.hist_limit_applied = nil
		HIST.change_joker_limit(-1)
		HIST.dbg(("[worldhist] shell left deck %s -> limit=%d"):format(
			self.config.center.key, G.jokers.config.card_limit))
	end
end

-- ★ 黑死病（Boss）：从牌组永久带走若干张牌（2026-09-11 新增批次）
--   牌组卡走 start_dissolve：原版 Card:remove 会把它从 G.playing_cards 里摘掉（card.lua:5150），
--   与手牌销毁同一条路径；牌组留 8 张底，避免把牌组抽干导致无牌可打
function HIST.plague_kill(n)
	if not (G.deck and G.deck.cards) then
		return 0
	end
	local pool = {}
	for _, c in ipairs(G.deck.cards) do
		pool[#pool + 1] = c
	end
	if #pool <= 8 then
		return 0
	end
	local take = math.min(n, #pool - 8)
	local killed = 0
	for _ = 1, take do
		if #pool == 0 then
			break
		end
		local victim = pseudorandom_element(pool, pseudoseed("hist_plague"))
		for i, c in ipairs(pool) do
			if c == victim then
				table.remove(pool, i)
				break
			end
		end
		if victim then
			victim:start_dissolve()
			killed = killed + 1
		end
	end
	return killed
end

-- ★ 科举制（Voucher）：回合结束时，把本回合打出次数最多的牌型升一级
--   level_up_hand(card, hand, instant, amount)（common_events.lua:470）；无来源卡时走 instant=true，
--   from=nil 时 SMODS.upgrade_poker_hands 内部对 card 做了判空（utils.lua:3773），安全
function HIST.keju_graduate()
	local counts = G.GAME.hist_hand_counts
	if not counts or not G.GAME.hands then
		return nil
	end
	local best, bestn = nil, 0
	for k, n in pairs(counts) do
		if G.GAME.hands[k] and n > bestn then
			best, bestn = k, n
		end
	end
	if not best then
		return nil
	end
	local ok = pcall(level_up_hand, nil, best, true, 1)
	HIST.dbg(("[worldhist] keju: %s x%d -> %s"):format(best, bestn, tostring(ok)))
	return best, ok
end

-- ★ 槽位自愈 + 罗伯斯庇尔的恐怖统治（设计案 §五.4）
local set_blind_sync_ref = Blind.set_blind
function Blind:set_blind(blind, reset, silent)
	set_blind_sync_ref(self, blind, reset, silent)
	HIST.suspect_card = nil
	-- 时局·乱世 / 治世：本局所有 Boss 的**要求分数**（chips，即界面上的那个大数字）修正。
	-- 幂等：以首次算出的原始 chips 为基准，reset=true 或重复 set_blind 时不会叠乘。
	if not reset and self.boss and self.chips then
		if not self.hist_base_chips then
			self.hist_base_chips = self.chips
		end
		local mul = (G.GAME.hist_omen == "chaos" and 1.35)
			or (G.GAME.hist_omen == "pax" and 0.8)
			or nil
		if mul then
			self.chips = math.max(1, math.floor(self.hist_base_chips * mul))
			self.chip_text = number_format(self.chips)
		end
	end
	-- 光荣革命：议会开会，最右那张本回合闭嘴
	HIST.glorious_silence()
	-- 黑死病：进场即从牌组带走 2 张（永久）
	if self.config and self.config.blind and self.config.blind.key == "bl_hist_plague" then
		local killed = HIST.plague_kill(2)
		G.E_MANAGER:add_event(Event({
			trigger = "after",
			delay = 0.5,
			func = function()
				card_eval_status_text(G.GAME.blind, "extra", nil, nil, nil, {
					message = killed > 0 and localize("hist_plague_hit") or localize("hist_plague_spare"),
					colour = G.C.RED,
				})
				return true
			end,
		}))
	end
	-- 罗伯斯庇尔：皇帝在场则随机一张非皇帝小丑（含吞并壳以外的独立小丑）标记"嫌疑"
	-- 嫌疑不走原版 debuff，靠结算门静默，避免和原版每手 debuff 重算打架
	if self.config and self.config.blind
		and self.config.blind.key == "bl_hist_robespierre"
		and HIST.emperor_present()
	then
		local pool = {}
		for _, c in ipairs(G.jokers.cards) do
			if not HIST.is_emperor(c) and not (c.ability and c.ability.hist_absorbed) then
				pool[#pool + 1] = c
			end
		end
		if #pool > 0 then
			HIST.suspect_card = pseudorandom_element(pool, pseudoseed("hist_robespierre"))
			HIST.suspect_card:add_sticker("hist_suspect", true)
		end
	end
	-- 玄奘：每 ante 开始取回一卷真经——随机生成 1 张星球牌（设计案 §十五·宗教史）
	local ante_now = G.GAME.round_resets and G.GAME.round_resets.ante or 0
	if ante_now ~= (HIST.last_ante or -1) and G.jokers then
		HIST.last_ante = ante_now
		for _, c in ipairs(G.jokers.cards) do
			if c.config.center.key == "j_hist_xuanzang" then
				local sutra = SMODS.create_card({ set = "Planet", area = G.consumeables })
				if sutra then
					sutra:add_to_deck()
					G.consumeables:emplace(sutra)
					sutra:juice_up(0.3, 0.5)
				end
			end
		end
		-- 时局·改朝换代：一旦抽到就开启轮换模式（G.GAME.hist_omen_rotating），
		-- 之后每 N 个底注从整个池子重抽一个，**换到别的时局也不停**，直到本局结束。
		-- hist_omen_ante 记在档里 → 读档不会重轮。
		local every = G.GAME.hist_omen_rotating and G.GAME.hist_omen_rotate_every
		if every and every > 0 and ante_now > 1
			and (ante_now - 1) % every == 0
			and G.GAME.hist_omen_ante ~= ante_now
			and HIST.rotate_omen
		then
			G.GAME.hist_omen_ante = ante_now
			HIST.rotate_omen()
		end
		-- 底注变了，"下次几号底注换"的倒计时要跟着变
		if HIST.refresh_omen_hud then
			HIST.refresh_omen_hud()
		end
	end
	-- 槽位自愈：若上限被外部重算洗掉，按记录值补回（必须走 change_size，禁裸写虚字段）
	if HIST.expected_limit and G.jokers and G.jokers.config.card_limit < HIST.expected_limit then
		HIST.change_joker_limit(HIST.expected_limit - G.jokers.config.card_limit)
		HIST.dbg("[worldhist] limit wiped, restored to " .. G.jokers.config.card_limit)
	end
end

-- DebugPlus 控制台诊断：控制台里运行 HIST.debug_limit() 查看当前记账
function HIST.debug_limit()
	local n, linked = 0, 0
	for _, c in ipairs(G.jokers.cards or {}) do
		if c.ability.hist_absorbed then
			n = n + 1
			if c.hist_emperor then
				linked = linked + 1
			end
		end
	end
	return ("cards=%d limit=%d shells=%d(linked=%d) expected_limit=%s junxian=%s"):format(
		#(G.jokers and G.jokers.cards or {}),
		G.jokers and G.jokers.config.card_limit or -1,
		n, linked,
		tostring(HIST.expected_limit),
		tostring(G.GAME.used_vouchers and G.GAME.used_vouchers["v_hist_junxian"]))
end

-- ★ 大宪章"人身保护"：走 SMODS 原生 prevent_debuff 通道
--   （Card:set_debuff 遍历 mod_list，返回 'prevent_debuff' 即拒绝禁用，含正确的 add_to_deck(true) 记账）
HIST.set_debuff = function(card)
	if card.ability and card.ability.hist_habeas then
		return "prevent_debuff"
	end
end

-- ★ 路易十六：赤字通胀——皇帝在场时商店内卡牌价格 +1（设计案 §五.2）
--   set_cost 每次都从零重算 cost，这里追加不叠加
-- ★ 分封制：藩镇割据，卖地不值钱——小丑售价减半（设计案 §八）
local set_cost_ref = Card.set_cost
function Card:set_cost()
	set_cost_ref(self)
	if HIST.emperor_key_present("j_hist_louis16")
		and self.area and self.area.config and self.area.config.type == "shop"
	then
		self.cost = self.cost + 1
	end
	if G.GAME.used_vouchers and G.GAME.used_vouchers["v_hist_fengjian"]
		and self.area == G.jokers
	then
		self.sell_cost = math.max(1, math.floor((self.sell_cost or 0) / 2))
	end
	-- 路易十四：朕即国家——商店内所有卡牌价格翻倍（设计案 §九）
	if G.GAME.blind and G.GAME.blind.config and G.GAME.blind.config.blind
		and G.GAME.blind.config.blind.key == "bl_hist_louis14"
		and self.area and self.area.config and self.area.config.type == "shop"
	then
		self.cost = self.cost * 2
	end
	-- 吕底亚铸币：史上第一批钱币——商店内所有卡牌与补强价格 -1（设计案 §八候选转正）
	if G.GAME.used_vouchers and G.GAME.used_vouchers["v_hist_lydia"]
		and self.area and self.area.config and self.area.config.type == "shop"
	then
		self.cost = math.max(0, self.cost - 1)
	end
	-- 交子：北宋的预支——下一个商店所有价格 +2（延迟代价，跨 ante 记在 G.GAME 上）
	if (G.GAME.hist_surcharge or 0) > 0
		and self.area and self.area.config and self.area.config.type == "shop"
	then
		self.cost = self.cost + G.GAME.hist_surcharge
	end
	-- 时局·重商主义：商店所有价格 +25%（钱多但东西贵）
	if G.GAME.hist_omen == "mercantilism"
		and self.cost and self.cost > 0
		and self.area and self.area.config and self.area.config.type == "shop"
	then
		self.cost = math.max(self.cost + 1, math.ceil(self.cost * 1.25))
	end
	-- 时局·军械库 / 大赦天下：消耗牌价格 +50%（换槽位、换等级都要付账）
	if (G.GAME.hist_omen == "arsenal" or G.GAME.hist_omen == "jubilee")
		and self.ability and self.ability.consumeable
		and self.area and self.area.config and self.area.config.type == "shop"
	then
		self.cost = math.max((self.cost or 0) + 1, math.ceil((self.cost or 0) * 1.5))
	end
	-- 时局·门阀：小丑售价 -50%（开局送的小丑不能立刻变现）
	if G.GAME.hist_omen == "patronage"
		and self.ability and self.ability.set == "Joker"
		and self.area == G.jokers
	then
		self.sell_cost = math.max(1, math.floor((self.sell_cost or 0) / 2))
	end
end

-- ★ 销毁拦截：免死金牌（本局一次，用后即弃）与大宪章人身保护（当回合，可多次）都在此免除
--   SMODS.destroy_cards 内部同样走 start_dissolve，两条销毁路都被覆盖
local start_dissolve_ref = Card.start_dissolve
function Card:start_dissolve(dissolve_colours, silent, dissolve_time_fac, no_juice)
	if self.ability and (self.ability.hist_exempt or self.ability.hist_habeas) then
		if self.ability.hist_exempt then
			self.ability.hist_exempt = nil
			self:remove_sticker("hist_exempt")
		end
		card_eval_status_text(self, "extra", nil, nil, nil, {
			message = localize("hist_exempt_saved"),
			colour = G.C.GOLD,
		})
		return
	end
	local rets = { start_dissolve_ref(self, dissolve_colours, silent, dissolve_time_fac, no_juice) }
	-- 销毁观察回调（司马迁"史家绝唱"用；免死金牌救下的不算，没死就不进这里）
	-- ★ 只统计小丑：黑死病等效果销毁的是扑克牌，不能给司马迁加成（2026-09-11 修）
	if HIST.on_destroyed and self.ability and self.ability.set == "Joker" then
		HIST.on_destroyed(self)
	end
	return unpack(rets)
end

-- ★ 九十五条论纲：每回合第一次重掷免费（反对赎罪券）。
--   把重掷费用清零后调原版（原版扣 0 元）；已知小瑕疵：之后 calculate_reroll_cost 从 0 起涨，
--   本次商店后续重掷比正常便宜一点，草案阶段接受
local reroll_shop_ref = G.FUNCS.reroll_shop
function G.FUNCS.reroll_shop(e)
	if G.GAME.used_vouchers and G.GAME.used_vouchers["v_hist_95thesis"]
		and not G.GAME.hist_free_reroll_used
		and (G.GAME.current_round.reroll_cost or 0) > 0
	then
		G.GAME.current_round.reroll_cost = 0
		G.GAME.hist_free_reroll_used = true
	end
	return reroll_shop_ref(e)
end

-- ★ 卢比孔河：骰子已掷下——本回合不能弃牌（state_events.lua:390 入口）
-- ★ 波拿巴：第一次弃牌后炮兵就位（下一手牌 +40 筹码，emperors.lua 消费标志）
local discard_ref = G.FUNCS.discard_cards_from_highlighted
function G.FUNCS.discard_cards_from_highlighted(e, hook)
	if HIST.rubicon then
		return
	end
	HIST.artillery_ready = true
	return discard_ref(e, hook)
end

-- ★ 匕首：下一手计分时 +1~10 倍率
-- 消耗牌写入 HIST.pending_mult，这里在 joker 结算阶段消费：
--   SMODS.trigger_effects 对每张小丑调用一次，返回值直接累加进本手 mult；
--   只认 ability.set == "Joker"，避免在手牌计分阶段重复注入。
local trigger_effects_ref = SMODS.trigger_effects
function SMODS.trigger_effects(effects, card)
	if HIST.pending_mult
		and card and card.ability and card.ability.set == "Joker"
		and G.play and G.play.cards and #G.play.cards > 0
	then
		local n = HIST.pending_mult
		HIST.pending_mult = nil
		effects = effects or {}
		effects[#effects + 1] = {
			jokers = {
				mult = n,
				message = localize("hist_dagger_boost"),
				colour = G.C.MULT,
				card = card,
			},
		}
	end
	return trigger_effects_ref(effects, card)
end

-- ★ 手牌计数：路易·奥古斯特"每回合首手牌"判定用（结算期间读旧值，0 = 首手）
local evaluate_play_ref = G.FUNCS.evaluate_play
function G.FUNCS.evaluate_play(e)
	evaluate_play_ref(e)
	G.GAME.hist_hand_played = (G.GAME.hist_hand_played or 0) + 1
	-- 科举制：记本回合各牌型打出的次数（G.GAME.last_hand_played 由 evaluate_play_intro 写入）
	local hk = G.GAME.last_hand_played
	if hk and G.GAME.hands and G.GAME.hands[hk] then
		G.GAME.hist_hand_counts = G.GAME.hist_hand_counts or {}
		G.GAME.hist_hand_counts[hk] = (G.GAME.hist_hand_counts[hk] or 0) + 1
	end
end

local new_round_ref = new_round
function new_round()
	new_round_ref()
	G.GAME.hist_hand_played = 0
	G.GAME.hist_free_reroll_used = nil
	G.GAME.hist_hand_counts = nil -- 科举制：本回合牌型计数
	G.GAME.hist_printed = nil -- 古腾堡：本回合是否已印回一张
	HIST.suspect_card = nil
	-- 交子：代价持续一整个 ante，跨过即清账（使用时记的是"下个 ante"）
	if G.GAME.hist_surcharge_ante and G.GAME.round_resets
		and G.GAME.round_resets.ante > G.GAME.hist_surcharge_ante
	then
		G.GAME.hist_surcharge = nil
		G.GAME.hist_surcharge_ante = nil
	end
	-- 大宪章角标逐回合重发：先清上一回合的
	if G.jokers then
		for _, c in ipairs(G.jokers.cards) do
			if c.ability.hist_habeas then
				c.ability.hist_habeas = nil
				c:remove_sticker("hist_habeas")
			end
		end
	end
	-- 乾隆御批角标逐回合重发：先清旧（打在手牌上，回合结束牌已回牌堆）
	if G.playing_cards then
		for _, c in ipairs(G.playing_cards) do
			if c.ability.hist_yubi then
				c.ability.hist_yubi = nil
				c:remove_sticker("hist_yubi")
			end
		end
	end
	-- 卢比孔河/萨拉丁均为一次性回合态，回合开始清账
	HIST.rubicon = nil
	HIST.saladin_discount = nil
	-- 梭伦改革：回合开始 -$2（解除债务奴隶的赎金，设计案 §八）
	if G.GAME.used_vouchers and G.GAME.used_vouchers["v_hist_solon"] then
		ease_dollars(-2)
	end
end

-- 数值安全转换（Talisman/Amulet 兼容，unproven 同款思路）
function HIST.num(v)
	if type(v) == "number" then
		return v
	end
	if type(v) == "string" then
		local s = v:gsub(",", ""):gsub("%s+", "")
		return tonumber(s) or 1
	end
	local ok, s = pcall(tostring, v)
	if ok and s then
		local n = tonumber((s:gsub(",", "")))
		if n then
			return n
		end
	end
	return 1
end

-- ★ 政策 Voucher / 全局效果结算通道（SMODS 把各上下文喂给 current_mod.calculate，unproven 同款）
HIST.calculate = function(self, context)
	-- 时局·乱世 / 治世：Boss 掉落修正（end_of_round 在盲注通过后触发，blind.boss 仍是刚打的这个）
	if context.end_of_round and G.GAME and G.GAME.blind and G.GAME.blind.boss then
		if G.GAME.hist_omen == "chaos" then
			ease_dollars(12)
		elseif G.GAME.hist_omen == "pax" then
			ease_dollars(-5)
		end
	end
	if context.end_of_round and G.GAME and G.GAME.used_vouchers then
		local v = G.GAME.used_vouchers
		-- 献土：回合结束 +$5（割地换和平，设计案 §八）
		if v["v_hist_xiantu"] then
			ease_dollars(5)
		end
		-- 屯田：回合结束时每剩 1 次出牌次数 +$1（闲时屯田，设计案 §八）
		if v["v_hist_tuntian"] then
			local left = math.max(0, G.GAME.current_round.hands_left or 0)
			if left > 0 then
				ease_dollars(left)
			end
		end
		-- 常平仓：金钱归零时回合结束 +$15，每局 2 次（官仓赈济，设计案 §八）
		if v["v_hist_changping"] and HIST.num(G.GAME.dollars) <= 0
			and (G.GAME.hist_changping or 0) < 2
		then
			G.GAME.hist_changping = (G.GAME.hist_changping or 0) + 1
			ease_dollars(15)
		end
		-- 圈地运动：回合结束 +$3（上限代价在 apply_to_run，设计案 §八候选转正）
		if v["v_hist_enclosure"] then
			ease_dollars(3)
		end
		-- 东印度公司：回合结束时，存款每 $10 生 $1 利息，每回合上限 $5（设计案 §八候选）
		if v["v_hist_eic"] then
			local purse = math.max(0, math.floor(HIST.num(G.GAME.dollars)))
			local interest = math.min(5, math.floor(purse / 10))
			if interest > 0 then
				ease_dollars(interest)
			end
		end
		-- 科举制：本回合打出最多的牌型升一级（2026-09-11 新增批次）
		if v["v_hist_keju"] then
			local best = HIST.keju_graduate()
			if best then
				card_eval_status_text(G.deck and G.deck.cards[1] or G.jokers, "extra", nil, nil, nil, {
					message = localize(best, "poker_hands"),
					colour = G.C.MULT,
				})
			end
		end
	end
	-- 卢比孔河：本回合所有出牌 X2；拿破仑法典：每回合第一手牌按法律升一级
	-- 都在 initial_scoring_step 动全局倍率（unproven 验证过：before 上下文会被基础倍率冲掉）
	if context.initial_scoring_step and G.GAME then
		local msg, colour
		if HIST.rubicon then
			mult = mod_mult(HIST.num(mult) * 2)
			msg, colour = localize("hist_rubicon_x"), G.C.XMULT
		elseif G.GAME.used_vouchers and G.GAME.used_vouchers["v_hist_code_napoleon"]
			and (G.GAME.hist_hand_played or 0) == 0
			and context.scoring_name and G.GAME.hands[context.scoring_name]
		then
			local hand = G.GAME.hands[context.scoring_name]
			hand_chips = mod_chips(HIST.num(hand_chips) + (hand.l_chips or 0))
			mult = mod_mult(HIST.num(mult) + (hand.l_mult or 0))
			msg, colour = localize("hist_code_up"), G.C.MULT
		end
		-- 光荣革命：王还在，发言的是议会——每张仍在说话的小丑 +20 筹码
		if G.GAME.used_vouchers and G.GAME.used_vouchers["v_hist_glorious"] then
			local speaking = 0
			if G.jokers then
				for _, c in ipairs(G.jokers.cards) do
					if not HIST.is_silenced(c) then
						speaking = speaking + 1
					end
				end
			end
			if speaking > 0 then
				hand_chips = mod_chips(HIST.num(hand_chips) + 20 * speaking)
				msg, colour = msg or localize("hist_parliament"), colour or G.C.CHIPS
			end
		end
		if msg then
			return { message = msg, colour = colour }
		end
	end
end

-- ============ 存档恢复 ============

-- 读档后：按皇帝身上的 absorbed 清单重建反向链接（card 引用不可序列化），
-- 并按实际壳数重贴槽位扣减（vanilla 的 card_limit 在读档时重算，负片同款自愈）。
local start_run_ref = Game.start_run
function Game:start_run(args)
	start_run_ref(self, args)
	-- 读档后把 HUD 上的时局文字恢复（HUD 可能在存档前就建好了）
	if HIST.refresh_omen_hud then
		HIST.refresh_omen_hud()
	end
	if not (G.jokers and G.jokers.cards) then
		return
	end
	for _, c in ipairs(G.jokers.cards) do
		c.hist_emperor = nil
	end
	for _, em in ipairs(G.jokers.cards) do
		if HIST.is_emperor(em) and em.ability.extra and em.ability.extra.absorbed then
			for _, key in ipairs(em.ability.extra.absorbed) do
				for _, c in ipairs(G.jokers.cards) do
					if c.ability.hist_absorbed and not c.hist_emperor and c.config.center.key == key then
						c.hist_emperor = em
						break
					end
				end
			end
		end
	end
	local n = 0
	for _, c in ipairs(G.jokers.cards) do
		if c.ability.hist_absorbed then
			n = n + 1
		end
	end
	-- card_limits 随存档持久化（CardArea:save 连 config 一起存，补偿已在档内），
	-- 读档只重建反向链接，不得重贴补偿
	HIST.expected_limit = G.jokers.config.card_limit
	HIST.dbg(("[worldhist] start_run: limit=%d cards=%d shells=%d"):format(
		G.jokers.config.card_limit, #G.jokers.cards, n))
end
