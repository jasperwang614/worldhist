-- items/omens.lua — 开局「时局」系统（v1.1，2026-10-18）
-- 每局开局从池子里抽 N 个，玩家选 1 个，本局生效。
-- 「时局会自动改换」本身也是一个时局（dynastic）的效果，不是全局规则：
-- 抽到带 rotate_every 的时局就开启"轮换模式"：之后每 N 个底注换一次，换到别的也不停。
-- 设计原则：每个时局 = 一条明确的构筑方向 + 一条代价，不做"纯惩罚"，
--           也不做"纯白给"（否则没有取舍，永远选同一个）。
-- 状态：G.GAME.hist_omen（字符串，跨存档）；hist_omen_pending 只用于开局弹窗；
--       hist_omen_once 记录一次性奖励已领（重商主义的启动资金每局只给一次）；
--       hist_omen_ante 记录上一次轮换发生在哪个底注（读档不重轮）。

HIST = HIST or SMODS.current_mod

-- 开局给几个选项（想改成 2 选 1 就改这里）
HIST.omen_pick_count = 3

-- ============ 即时效果辅助 ============
-- 开局时机是 BLIND_SELECT，区域已经建好，所以既要改 G.GAME 上的参数（管后续回合），
-- 也要改当前区域的 card_limit（管本回合）。

local function add_dollars(n)
	G.GAME.dollars = (G.GAME.dollars or 0) + n
end

local function add_joker_slots(n)
	if HIST.change_joker_limit then
		HIST.change_joker_limit(n)
	end
	local sp = G.GAME.starting_params
	if sp and sp.joker_slots then
		sp.joker_slots = sp.joker_slots + n
	end
end

local function add_consumable_slots(n)
	if G.consumeables then
		G.consumeables:change_size(n)
	end
	local sp = G.GAME.starting_params
	if sp and sp.consumable_slots then
		sp.consumable_slots = sp.consumable_slots + n
	end
end

local function add_hand_size(n)
	if G.hand and G.hand.config.card_limit then
		G.hand.config.card_limit = math.max(1, G.hand.config.card_limit + n)
	end
	local sp = G.GAME.starting_params
	if sp and sp.hand_size then
		sp.hand_size = math.max(1, sp.hand_size + n)
	end
end

local function add_discards(n)
	local sp = G.GAME.starting_params
	if sp and sp.discards then
		sp.discards = math.max(0, sp.discards + n)
	end
	if G.GAME.round_resets and G.GAME.round_resets.discards then
		G.GAME.round_resets.discards = math.max(0, G.GAME.round_resets.discards + n)
	end
	if G.GAME.current_round and G.GAME.current_round.discards_left then
		G.GAME.current_round.discards_left = math.max(0, G.GAME.current_round.discards_left + n)
	end
end

local function add_hands(n)
	local sp = G.GAME.starting_params
	if sp and sp.hands then
		sp.hands = math.max(1, sp.hands + n)
	end
	if G.GAME.round_resets and G.GAME.round_resets.hands then
		G.GAME.round_resets.hands = math.max(1, G.GAME.round_resets.hands + n)
	end
	if G.GAME.current_round and G.GAME.current_round.hands_left then
		G.GAME.current_round.hands_left = math.max(0, G.GAME.current_round.hands_left + n)
	end
end

-- ============ 时局专用小工具 ============
-- 发牌：set = "Joker" 进小丑区，其余（Tarot/Planet/Spectral）进消耗区。
-- rarity 只对小丑有意义：1 普通 / 2 罕见 / 3 稀有 / 4 传奇。
local function grant_cards(set_type, n, rarity)
	local area = (set_type == "Joker") and G.jokers or G.consumeables
	if not area then
		return
	end
	for _ = 1, n do
		local c = SMODS.create_card({ set = set_type, area = area, rarity = rarity })
		if c then
			c:add_to_deck()
			area:emplace(c)
			c:juice_up(0.3, 0.5)
		end
	end
end

-- 升级牌型：only 为 nil 时全部牌型各升 amount 级
local function level_hands(only, amount)
	if not (G.GAME and G.GAME.hands) then
		return
	end
	if only then
		for k, n in pairs(only) do
			if G.GAME.hands[k] then
				level_up_hand(nil, k, true, n)
			end
		end
	else
		for k in pairs(G.GAME.hands) do
			level_up_hand(nil, k, true, amount or 1)
		end
	end
end

-- 牌组硬下限：任何"烧牌"都不能把牌组烧到少于这个数。
-- 原版一副 52 张；大清洗 -13、焦土 -8。玩家局内还会加牌/删牌，
-- 所以这里不做"整局只能删一次"的全局锁——只保证任何一次烧牌之后，
-- 牌组仍够发牌（不至于死局）。
HIST.MIN_DECK_SIZE = 20

-- 从牌组永久移除一个花色的全部牌（开局阶段，手牌还没发，只动 G.deck）
-- 烧完必须还剩 MIN_DECK_SIZE 张，不够就整单放弃（返回 0，由调用方决定不记 debuff）
local function purge_suit(suit)
	if not (G.deck and G.deck.cards) then
		return 0
	end
	local victims = {}
	for _, c in ipairs(G.deck.cards) do
		if c.base and c.base.suit == suit then
			victims[#victims + 1] = c
		end
	end
	if #victims == 0 or #G.deck.cards - #victims < HIST.MIN_DECK_SIZE then
		return 0
	end
	for _, c in ipairs(victims) do
		c:start_dissolve()
	end
	return #victims
end

-- 随机弃掉 n 张牌（不指定花色）
local function purge_random(n)
	if not (G.deck and G.deck.cards) then
		return 0
	end
	local pool = {}
	for _, c in ipairs(G.deck.cards) do
		pool[#pool + 1] = c
	end
	local take = math.min(n, #pool - HIST.MIN_DECK_SIZE)
	local killed = 0
	for i = 1, math.max(0, take) do
		if #pool == 0 then
			break
		end
		-- 用游戏的 pseudorandom 而不是 math.random：Lua 5.1 的 math.random 不播种时
		-- 每次启动都是同一串，会导致"焦土"永远烧同样的位置
		local victim = pseudorandom_element(pool, pseudoseed("hist_scorch" .. i))
		for j, c in ipairs(pool) do
			if c == victim then
				table.remove(pool, j)
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

-- ============ 时局池 ============
-- tag 只用于界面配色/分类：reward 奖励 / double 双刃 / risk 风险 / steady 稳健 / random 随机
-- slots 是"可逆的槽位修正"：轮换时旧时局按 -slots 撤销，新时局按 +slots 应用，收支严格对称。
-- once 是"一次性奖励"：整局最多触发一次，轮换走也不收回（钱已经花进构筑里了，硬扣会变成负债）。
-- rotate_every = N：抽到它就开启轮换模式——每 N 个底注从整个池子随机换一个，换到别的也不停。
-- 持久效果（商店涨价、Boss 要求分数、Boss 奖励、X 倍率）在 hooks.lua 里按 G.GAME.hist_omen 判定，
-- 这里只写"选中/换入"瞬间要改的东西。

-- ============ 时局池（v2，20 个）============
-- tag 只用于界面配色/分类：reward 奖励 / double 双刃 / risk 风险 / steady 稳健 / random 随机
-- slots 是"可逆的槽位修正"：轮换时旧时局按 -slots 撤销，新时局按 +slots 应用，收支严格对称。
-- once 是"一次性奖励"：整局最多触发一次，轮换走也不收回（钱已经花进构筑里了，硬扣会变成负债）。
-- rotate_every = N：抽到它就开启轮换模式——每 N 个底注从整个池子随机换一个，换到别的也不停。
--
-- 两类"真正决定方向"的字段（由 hooks.lua 读，不在选中瞬间改任何东西）：
--   lock_suit = "Hearts"    只有该花色参与计分（其他花色的牌、增强、贴纸效果全部无效）
--   score = { suit=..., mult=..., chips=... }   每张计分牌额外加成；suit 省略 = 所有牌
-- 弃牌型（risk）：开局直接烧掉牌组的一部分，玩家必须在"更薄的牌组"上重建构筑。
-- 持久效果（商店涨价、Boss 要求分数、Boss 奖励、X 倍率）在 hooks.lua 里按 G.GAME.hist_omen 判定。

HIST.omens = {
	-- 随机：选它 = 从其余时局里当场抽一个（不想要的时局太多时的兜底出口）
	random = {
		tag = "random",
	},
	-- 改朝换代：坐上龙椅的人一直在换——多一个槽位，但时局每 2 个底注就重新洗一次
	dynastic = {
		tag = "random",
		rotate_every = 2,
		slots = { joker = 1 },
	},

	-- ===== 规则型：锁定计分花色 =====
	-- 血色宫廷：只有红桃算数，红桃每张再 +4 倍率——把整局钉死在红桃上
	court_of_hearts = {
		tag = "double",
		lock_suit = "Hearts",
		score = { suit = "Hearts", mult = 4 },
	},
	-- 黑铁时代：只有黑桃算数，黑桃每张 +50 筹码——筹码轴，适合高牌型/大数字
	spade_empire = {
		tag = "double",
		lock_suit = "Spades",
		score = { suit = "Spades", chips = 50 },
	},

	-- ===== 弃牌型：烧牌组 =====
	-- ★ 标 purge = true：轮换模式里"总共只允许出现一次弃牌类"。
	--   第一次轮到它照常生效（这就是改朝换代的变数：世道真的会把你半副牌烧掉），
	--   之后本轮换再也不会抽到任何弃牌类时局——不是靠入口约定，是 resolve_omen
	--   读 G.GAME.hist_rotate_purged 这个状态来筛。
	--   轮换只由「改朝换代」开启，所以这条规则天然只作用于轮换局。
	-- 大清洗：随机烧掉一个花色（13 张），但活下来的每张牌 +20 筹码
	purge_suit = {
		tag = "risk",
		purge = true,
		once = function()
			local suits = { "Hearts", "Diamonds", "Clubs", "Spades" }
			-- 同 purge_random：必须用 pseudorandom，否则每次启动都烧同一个花色
			local picked = pseudorandom_element(suits, pseudoseed("hist_purge_suit"))
			local n = purge_suit(picked)
			G.GAME.hist_purged_suit = n > 0 and picked or nil
			HIST.dbg(("[worldhist] omen purge: %s x%d"):format(picked, n))
			-- 一张都没烧掉（牌组低于下限）→ 不记已领，也不算这个时局生效
			return n > 0
		end,
		score = { chips = 20 },
	},
	-- 焦土：随机烧 8 张，换 $25 启动资金——薄牌组 + 高现金流
	scorched_earth = {
		tag = "risk",
		purge = true,
		once = function()
			local n = purge_random(8)
			if n <= 0 then
				return false
			end
			add_dollars(25)
			return true
		end,
	},

	-- ===== 牌型等级 =====
	-- 同花时代：同花系四种牌型开局 +3 级，但手牌上限 -2
	flush_era = {
		tag = "double",
		slots = { hand = -2 },
		once = function()
			level_hands({
				["Flush"] = 3,
				["Straight Flush"] = 3,
				["Flush House"] = 3,
				["Flush Five"] = 3,
			})
		end,
	},
	-- 大赦天下：所有牌型开局 +1 级，但消耗牌价格 +50%
	jubilee = {
		tag = "reward",
		once = function()
			level_hands(nil, 1)
		end,
	},
	-- 察举制：所有牌型升级效果翻倍（每次 +2 级），但每回合出牌 -1
	meritocracy = {
		tag = "double",
		slots = { hands = -1 },
		level_boost = true,
	},

	-- ===== 资源型 =====
	-- 重商主义：先给一笔启动资金，但商店变贵——逼你早点把钱变成构筑
	mercantilism = {
		tag = "reward",
		once = function()
			add_dollars(20)
		end,
	},
	-- 门阀：开局送 2 张罕见以上小丑，直接定小丑流；代价是小丑卖不出价
	patronage = {
		tag = "reward",
		once = function()
			grant_cards("Joker", 2, 2)
		end,
	},
	-- 军械库：消耗牌槽 +2、小丑槽 -2，再送 3 张塔罗——极端消耗牌线
	arsenal = {
		tag = "double",
		slots = { consumable = 2, joker = -2 },
		once = function()
			grant_cards("Tarot", 3)
		end,
	},
	-- 金牛犊：开局 +$40，但利息上限从 $5 砍到 $2——有钱，但存钱不再生钱
	golden_bull = {
		tag = "reward",
		interest_cap = 10,
		once = function()
			add_dollars(40)
		end,
	},

	-- ===== 结构型 =====
	-- 官僚制：多一个小丑槽，但手牌上限 -1（更依赖小丑而非手牌组合）
	bureaucracy = {
		tag = "double",
		slots = { joker = 1, hand = -1 },
	},
	-- 百家争鸣：多一个消耗牌槽，但小丑槽 -1（消耗牌/星球线）
	hundred_schools = {
		tag = "double",
		slots = { consumable = 1, joker = -1 },
	},
	-- 分裂：手牌上限 +3，小丑槽 -2——用更大的牌型替代小丑
	schism = {
		tag = "double",
		slots = { hand = 3, joker = -2 },
	},
	-- 征兵制：每回合多一次出牌，但弃牌 -2
	conscription = {
		tag = "double",
		slots = { hands = 1, discards = -2 },
	},

	-- ===== 风险 / 稳健 =====
	-- 军国主义：X 倍率构筑更强，但每回合少一次弃牌
	militarism = {
		tag = "double",
		slots = { discards = -1 },
	},
	-- 乱世：Boss 更硬，但每个 Boss 掉落更多
	chaos = {
		tag = "risk",
	},
	-- 治世：Boss 更软，但 Boss 奖励更少
	pax = {
		tag = "steady",
	},
}

-- ============ 效果应用 / 撤销 ============

local function apply_slots(s)
	if not s then
		return
	end
	if s.joker then
		add_joker_slots(s.joker)
	end
	if s.consumable then
		add_consumable_slots(s.consumable)
	end
	if s.hand then
		add_hand_size(s.hand)
	end
	if s.discards then
		add_discards(s.discards)
	end
	if s.hands then
		add_hands(s.hands)
	end
end

local function negate_slots(s)
	if not s then
		return nil
	end
	local out = {}
	for k, v in pairs(s) do
		out[k] = -v
	end
	return out
end

-- 选中/换入：应用槽位修正 + 一次性奖励（每局最多一次）
-- ★ 抽到带 rotate_every 的时局 = 开启"时局轮换"模式，本局剩余时间一直生效：
--   之后每 N 个底注换一次，换到别的时局也不停（用户 2026-10-18 明确）。
--   模式标志存在 G.GAME 上（随存档走），当前时局只是"这一段的世道"。
function HIST.apply_omen(key)
	local o = HIST.omens[key]
	if not o then
		return
	end
	apply_slots(o.slots)
	-- 利息上限是"规则修正"，轮换时必须能还原，所以记基准值（原版默认 25 = 上限 $5）
	if o.interest_cap then
		if not G.GAME.hist_base_interest_cap then
			G.GAME.hist_base_interest_cap = G.GAME.interest_cap
		end
		G.GAME.interest_cap = o.interest_cap
	end
	if o.rotate_every and o.rotate_every > 0 then
		G.GAME.hist_omen_rotating = true
		G.GAME.hist_omen_rotate_every = o.rotate_every
	end
	if o.once then
		G.GAME.hist_omen_once = G.GAME.hist_omen_once or {}
		if not G.GAME.hist_omen_once[key] then
			-- once 可以返回 false 表示"这次没生效"（比如牌组已经薄到不能烧），
			-- 这时不记已领：否则玩家付了代价却永远拿不到收益。
			local ok = o.once()
			if ok ~= false then
				G.GAME.hist_omen_once[key] = true
			end
		end
	end
end

-- 换出：只撤销槽位修正（一次性奖励不回滚）
function HIST.remove_omen(key)
	local o = HIST.omens[key]
	if not o then
		return
	end
	apply_slots(negate_slots(o.slots))
	if o.interest_cap and G.GAME.hist_base_interest_cap then
		G.GAME.interest_cap = G.GAME.hist_base_interest_cap
		G.GAME.hist_base_interest_cap = nil
	end
end

-- 把 "random" 解析成具体时局
--   exclude    轮换时排除当前那个，避免"换了等于没换"
--   for_rotate 轮换模式专用
--
-- ★ 轮换只由「改朝换代」开启：开局选了弃牌类时局的局，根本不会进入轮换，
--   所以"开局选的弃牌"和"轮换里再抽到弃牌"这两个场景不可能同时出现。
--   下面两条规则都只作用于轮换内部。
--
-- 筛选规则：
--   ① 本轮换已经出过一次弃牌类（G.GAME.hist_rotate_purged）
--      → 之后不再抽到任何 purge 时局。
--   ② once 已经领过 —— 收益是一次性的，代价却是持续的
--      （商店涨价 / 手牌 -2 / 出牌 -1…），再抽到就是纯惩罚。
-- ★ 大清洗烧掉的花色，其对应的锁定时局必须排除：牌组里已经没这个花色了，
--   再抽到"只有红桃计分"就是死局（玩家一手牌全部不计分）。
local LOCK_BY_SUIT = {
	Hearts = "court_of_hearts",
	Spades = "spade_empire",
}

function HIST.resolve_omen(key, exclude, for_rotate)
	key = key or "random"
	if key ~= "random" then
		return key
	end
	local purged = G.GAME and G.GAME.hist_purged_suit
	local dead = purged and LOCK_BY_SUIT[purged]
	local claimed = for_rotate and G.GAME and G.GAME.hist_omen_once or nil
	local purge_used = for_rotate and G.GAME and G.GAME.hist_rotate_purged

	-- 第一轮按全部规则筛；万一筛空了（理论上不会，池子 20 个），
	-- 退一步去掉"已领过"这条，保证随机永远有结果，不会卡住不动。
	local function build(strict)
		local pool = {}
		for k, o in pairs(HIST.omens) do
			local skip = (k == "random") or (k == exclude) or (k == dead)
			if purge_used and o.purge then
				skip = true
			end
			if strict and claimed and claimed[k] then
				skip = true
			end
			if not skip then
				pool[#pool + 1] = k
			end
		end
		return pool
	end

	local pool = build(true)
	if #pool == 0 then
		pool = build(false)
	end
	if #pool == 0 then
		return nil
	end
	table.sort(pool)
	-- 种子带上底注：否则同一局两次轮换、池子恰好一样时会抽到同一个
	local ante = (G.GAME and G.GAME.round_resets and G.GAME.round_resets.ante) or 0
	local seed = for_rotate and ("hist_omen_rotate_" .. tostring(ante)) or "hist_omen_pick"
	return pseudorandom_element(pool, pseudoseed(seed))
end

-- ============ 抽取 ============

function HIST.roll_omens(n)
	n = n or 3
	local pool = {}
	for k in pairs(HIST.omens) do
		pool[#pool + 1] = k
	end
	table.sort(pool) -- 先排序再洗，保证同种子下顺序稳定（否则 pairs 顺序不定）
	-- 用游戏的 pseudoshuffle（内部会 math.randomseed(pseudoseed)）：
	-- 裸 math.random 虽然启动时播过种，但会被其他地方 math.randomseed 反复污染，
	-- 同种子下不可复现，调试和回放都对不上。
	pseudoshuffle(pool, pseudoseed("hist_omen_roll"))

	local out = {}
	local purge_taken = false
	for _, k in ipairs(pool) do
		if #out >= n then
			break
		end
		local o = HIST.omens[k]
		-- 三个选项里最多一个弃牌类：大清洗和焦土同时出现等于白占一个位置
		if o.purge then
			if not purge_taken then
				purge_taken = true
				out[#out + 1] = k
			end
		else
			out[#out + 1] = k
		end
	end
	return out
end

-- ============ 界面 ============

local TAG_COLOUR = {
	reward = G.C.GOLD or G.C.ORANGE,
	double = G.C.BLUE,
	risk = G.C.RED,
	steady = G.C.GREEN,
	random = G.C.PURPLE or G.C.BLUE,
}

local function omen_card(key)
	local o = HIST.omens[key]
	local tag = o.tag or "double"
	local colour = TAG_COLOUR[tag] or G.C.BLUE

	return {
		n = G.UIT.C,
		config = {
			align = "tm",
			minw = 4.7,
			minh = 3.2,
			padding = 0.1,
			r = 0.1,
			colour = G.C.L_BLACK,
			emboss = 0.08,
		},
		nodes = {
			{n = G.UIT.R, config = {align = "cm", padding = 0.04}, nodes = {
				{n = G.UIT.T, config = {text = localize("hist_omen_tag_" .. tag), scale = 0.26, colour = colour}},
			}},
			{n = G.UIT.R, config = {align = "cm", padding = 0.06}, nodes = {
				{n = G.UIT.T, config = {text = localize("hist_omen_" .. key), scale = 0.42, colour = G.C.UI.TEXT_LIGHT, shadow = true}},
			}},
			{n = G.UIT.R, config = {align = "cm", padding = 0.04, minh = 0.9}, nodes = {
				{n = G.UIT.T, config = {text = localize("hist_omen_" .. key .. "_up"), scale = 0.29, colour = G.C.GREEN}},
			}},
			{n = G.UIT.R, config = {align = "cm", padding = 0.04, minh = 0.6}, nodes = {
				{n = G.UIT.T, config = {text = localize("hist_omen_" .. key .. "_down"), scale = 0.29, colour = G.C.RED}},
			}},
			{n = G.UIT.R, config = {align = "cm", padding = 0.08}, nodes = {
				UIBox_button({
					label = {localize("hist_omen_pick")},
					button = "hist_omen_" .. key,
					colour = colour,
					minw = 3.6,
					minh = 0.75,
					focus_args = {nav = "wide"},
				}),
			}},
		},
	}
end

function HIST.build_omen_ui(picks)
	local cards = {}
	for _, key in ipairs(picks) do
		cards[#cards + 1] = omen_card(key)
	end

	-- contents 的顶层节点按"列"排（原版惯例），所以外面再包一个 C 做纵向三行
	return create_UIBox_generic_options({
		no_back = true,
		contents = {
			{n = G.UIT.C, config = {align = "cm", padding = 0.08}, nodes = {
				{n = G.UIT.R, config = {align = "cm", padding = 0.06}, nodes = {
					{n = G.UIT.T, config = {text = localize("hist_omen_title"), scale = 0.62, colour = G.C.UI.TEXT_LIGHT, shadow = true}},
				}},
				{n = G.UIT.R, config = {align = "cm", padding = 0.04}, nodes = {
					{n = G.UIT.T, config = {text = localize("hist_omen_sub"), scale = 0.3, colour = G.C.UI.TEXT_LIGHT}},
				}},
				{n = G.UIT.R, config = {align = "tm", padding = 0.12}, nodes = cards},
			}},
		},
	})
end

-- 飘字：优先挂在一张真实的小丑上（card_eval_status_text 会读 card.T/area，盲注对象不保证安全）
function HIST.omen_toast(msg)
	local anchor = (G.jokers and G.jokers.cards and G.jokers.cards[1])
		or (G.hand and G.hand.cards and G.hand.cards[1])
		or nil
	if not anchor then
		return
	end
	card_eval_status_text(anchor, "extra", nil, nil, nil, {
		message = msg,
		colour = G.C.PURPLE or G.C.BLUE,
	})
end

-- ============ 选择 ============

function HIST.pick_omen(key)
	if not (G.GAME and G.GAME.hist_omen_pending) then
		return
	end
	local wanted = key
	local chosen = HIST.resolve_omen(key)
	if not (chosen and HIST.omens[chosen]) then
		return
	end

	G.GAME.hist_omen_pending = nil
	G.GAME.hist_omen_picks = nil
	G.GAME.hist_omen = chosen
	G.GAME.hist_omen_ante = G.GAME.round_resets and G.GAME.round_resets.ante or 1
	HIST.apply_omen(chosen)
	HIST.refresh_omen_hud()

	G.FUNCS.exit_overlay_menu()
	-- 选了"随机"的话，得让玩家知道自己抽到了什么
	if wanted ~= chosen then
		G.E_MANAGER:add_event(Event({
			trigger = "after",
			delay = 0.6,
			func = function()
				HIST.omen_toast(localize("hist_omen_drawn") .. " · " .. localize("hist_omen_" .. chosen))
				return true
			end,
		}))
	end
	HIST.dbg(("[worldhist] omen chosen: %s%s"):format(chosen, wanted ~= chosen and (" (random of " .. wanted .. ")") or ""))
end

-- 时局自行改换（轮换模式开启后由 hooks.lua 在底注变化时调用，换到别的时局也不停）
-- 从整个池子里抽（random 解析掉，排除当前那个，避免"换了等于没换"）
function HIST.rotate_omen()
	local old = G.GAME.hist_omen
	local new = HIST.resolve_omen("random", old, true)
	if not (new and new ~= old) then
		return
	end
	if old then
		HIST.remove_omen(old)
	end
	G.GAME.hist_omen = new
	HIST.apply_omen(new)
	-- 轮换已经出过一次弃牌类 → 之后本轮换不再抽到任何 purge 时局。
	-- 只在"轮换"这条路径上置位：开局选的和听天由命抽到的弃牌不占这个名额。
	if HIST.omens[new] and HIST.omens[new].purge then
		G.GAME.hist_rotate_purged = true
	end
	HIST.refresh_omen_hud()
	G.E_MANAGER:add_event(Event({
		trigger = "after",
		delay = 0.5,
		func = function()
			HIST.omen_toast(localize("hist_omen_changed") .. " · " .. localize("hist_omen_" .. new))
			return true
		end,
	}))
	HIST.dbg(("[worldhist] omen rotated: %s -> %s (ante %s)"):format(
		tostring(old), tostring(new), tostring(G.GAME.round_resets and G.GAME.round_resets.ante)))
end

function HIST.open_omen_menu()
	if not (G.GAME and G.GAME.hist_omen_pending) or G.OVERLAY_MENU then
		return
	end
	local picks = HIST.roll_omens(HIST.omen_pick_count)
	G.GAME.hist_omen_picks = picks
	G.SETTINGS.paused = true
	-- 不设 no_esc：万一界面出问题，ESC 能退出，只是这局没有时局加成（G.GAME.hist_omen 保持 nil）
	G.FUNCS.overlay_menu({
		definition = HIST.build_omen_ui(picks),
	})
end

-- 每个时局一个 G.FUNCS，避免在按钮 config 里传自定义字段（原版不保证透传）
-- ★ 必须 local k = key：LuaJIT/Lua 5.1 的 for 循环变量是同一个，闭包会全部指向最后一个 key
for key in pairs(HIST.omens) do
	local k = key
	G.FUNCS["hist_omen_" .. k] = function()
		HIST.pick_omen(k)
	end
end

-- ============ 局内常驻 HUD ============
-- 原版右侧 HUD 面板（blind / 金钱 / 手牌 / 回合）里插一行，显示当前时局。
-- 用 DynaText 绑自己维护的表（不是 G.GAME）：换时局时只改字段，DynaText 每帧自动刷新，
-- 不需要重建 HUD，也不会被原版的 HUD 重建逻辑冲掉（重建时会重新调用 create_UIBox_HUD）。
-- 改朝换代额外显示"下一次几号底注换"——轮换型时局里，这是玩家唯一能预判的锚点。

HIST.omen_hud_state = { text = "" }

-- 悬停 tooltip 的内容表：原版 UIElement:hover 走 on_demand_tooltip →
-- create_popup_UIBox_tooltip({title, text})，每次 hover 现建，所以这里改字段立即生效。
-- ★ 只在 text 里放纯字符串：create_popup_UIBox_tooltip 对 table 项只认 ref_table/ref_value，
--   不支持逐行配色，收益/代价靠前缀文字区分。
HIST.omen_tooltip = { title = "", text = {} }

-- 轮换模式下，下一次更换发生在哪个底注
local function next_rotate_ante()
	if not (G.GAME and G.GAME.hist_omen_rotating) then
		return nil
	end
	local every = G.GAME.hist_omen_rotate_every or 2
	local ante = (G.GAME.round_resets and G.GAME.round_resets.ante) or 1
	return ante + (every - ((ante - 1) % every))
end

function HIST.refresh_omen_hud()
	local state = HIST.omen_hud_state
	local tip = HIST.omen_tooltip
	if not (G.GAME and G.GAME.hist_omen) then
		state.text = ""
		tip.title = ""
		tip.text = {}
		return
	end
	local key = G.GAME.hist_omen
	local name = localize("hist_omen_" .. key)
	state.text = localize("hist_omen_hud_label") .. " · " .. name
	tip.title = state.text
	tip.text = {
		localize("hist_omen_tip_up") .. localize("hist_omen_" .. key .. "_up"),
		localize("hist_omen_tip_down") .. localize("hist_omen_" .. key .. "_down"),
	}
	local nxt = next_rotate_ante()
	if nxt then
		local hint = string.format(localize("hist_omen_hud_next"), nxt)
		state.text = state.text .. "   " .. hint
		tip.text[#tip.text + 1] = hint
	end
end

local function omen_hud_row()
	return {
		n = G.UIT.R,
		config = {align = "cm", padding = 0.04, r = 0.1, colour = G.C.DYN_UI.BOSS_DARK, minw = 4.5},
		nodes = {
			-- 外壳可悬停：hover=true + can_collide=true 是原版 cycle_main 那类节点的写法
			{n = G.UIT.C, config = {
				align = "cm",
				padding = 0.02,
				hover = true,
				can_collide = true,
				on_demand_tooltip = HIST.omen_tooltip,
			}, nodes = {
				{n = G.UIT.O, config = {object = DynaText({
					string = {{ref_table = HIST.omen_hud_state, ref_value = "text"}},
					colours = {G.C.PURPLE or G.C.BLUE},
					shadow = true,
					scale = 0.3,
					maxw = 4.3,
					silent = true,
				})}},
			}},
		},
	}
end

local function find_by_id(node, id)
	if type(node) ~= "table" then
		return nil
	end
	if node.config and node.config.id == id then
		return node
	end
	for _, child in ipairs(node.nodes or {}) do
		local found = find_by_id(child, id)
		if found then
			return found
		end
	end
	return nil
end

local function insert_before(nodes, target, new_node)
	for i, child in ipairs(nodes) do
		if child == target then
			table.insert(nodes, i, new_node)
			return true
		end
		if type(child) == "table" and child.nodes and insert_before(child.nodes, target, new_node) then
			return true
		end
	end
	return false
end

-- 包装 HUD 定义：在 row_blind（盲注信息块）上方插一行时局
-- 失败只打印，不阻断 HUD 构建——UI 不能因为一个附加行把游戏搞崩
if type(create_UIBox_HUD) == "function" then
	local create_hud_ref = create_UIBox_HUD
	function create_UIBox_HUD(...)
		local def = create_hud_ref(...)
		local ok, err = pcall(function()
			HIST.refresh_omen_hud()
			local target = find_by_id(def, "row_blind")
			if target then
				insert_before(def.nodes, target, omen_hud_row())
			end
		end)
		if not ok then
			HIST.dbg("[worldhist] omen HUD insert failed: " .. tostring(err))
		end
		return def
	end
end

-- ============ 开局钩子 ============

local game_start_run_ref = Game.start_run
function Game:start_run(args)
	game_start_run_ref(self, args)

	-- 读档不弹；教程不弹；挑战模式规则固定，不弹
	if args and args.savetext then
		-- 清掉可能残留的 pending（选了之前就退出的话），避免以后误弹
		if G.GAME then
			G.GAME.hist_omen_pending = nil
		end
		return
	end
	if args and args.challenge then
		return
	end
	if not (G.GAME and G.GAME.pseudorandom) then
		return
	end
	if G.GAME.pseudorandom.seed == "TUTORIAL" then
		return
	end

	G.GAME.hist_omen_pending = true
	-- 等开局那几个动画/区域稳定后再弹，避免 overlay 建在未初始化的 UI 上。
	-- func 返回 false 时事件会在下一帧继续调用，直到 BLIND_SELECT 与 UI 都就绪。
	G.E_MANAGER:add_event(Event({
		trigger = "after",
		delay = 0.5,
		blocking = false,
		blockable = false,
		func = function()
			if not (G.GAME and G.GAME.hist_omen_pending) then
				return true
			end
			if G.STATE == G.STATES.BLIND_SELECT and G.ROOM and G.HUD then
				HIST.open_omen_menu()
				return true
			end
			return false
		end,
	}))
end
