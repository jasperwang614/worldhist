--- 世界历史 WORLDHIST · main.lua
--- 内容线：皇帝 / 风云小丑 / 器物 / 政策 / Boss（对应《WORLDHIST-design-v1.0.md》）
HIST = SMODS.current_mod

-- 注册表（设计案 §2.1 / 开发规范 §5.2）
-- 形态对：初始形态 key -> 皇帝形态 key
HIST.forms = {
	j_hist_yingzheng = "j_hist_qinshihuang",
	j_hist_louis_auguste = "j_hist_louis16",
	j_hist_hongli = "j_hist_qianlong",
	j_hist_bonaparte = "j_hist_napoleon",
	j_hist_julius = "j_hist_caesar",
}
-- 反向：皇帝形态 -> 初始形态（断头台还原用）
HIST.initial_forms = {
	j_hist_qinshihuang = "j_hist_yingzheng",
	j_hist_louis16 = "j_hist_louis_auguste",
	j_hist_qianlong = "j_hist_hongli",
	j_hist_napoleon = "j_hist_bonaparte",
	j_hist_caesar = "j_hist_julius",
}
-- 皇帝形态 key 集合（皇帝判定：只有皇帝形态算皇帝，设计案 §2.1）
HIST.emperor_keys = {
	j_hist_qinshihuang = true,
	j_hist_louis16 = true,
	j_hist_qianlong = true,
	j_hist_napoleon = true,
	j_hist_caesar = true,
}
-- 自我加冕：可点击自己直接登基的人物（拿破仑，设计案 §六.2）
HIST.self_crowning = {
	j_hist_bonaparte = true,
}
-- 登朝即吞并：只有登记在此的皇帝登基时吞全场（吞并为秦始皇专属）
HIST.coronation_swallow = {
	j_hist_qinshihuang = true,
}
-- 断头台特殊例外：皇帝 key -> 特殊产物 key（路易十六 → 头，设计案 §五.3）
HIST.special_guillotine = {
	j_hist_louis16 = "j_hist_louis_head",
}
-- 革命者小丑 key 集合（石人一只眼的重触发对象，设计案 §八）
HIST.revolutionary_keys = {
	j_hist_chensheng = true,
	j_hist_spartacus = true,
}
-- 革命者 Boss key 集合（头的出售跳过对象）
HIST.revolution_bosses = {
	bl_hist_robespierre = true,
}
-- 登基器物家族（断头台返还池；同效果原则，设计案 §10.2）
HIST.crown_items = {
	c_hist_yuxi = true,
	c_hist_laurel = true,
	c_hist_crown = true,
	c_hist_monomakh = true,
	c_hist_anointing = true,
}

-- 开发调试：开新局自动加入"当前测试中的卡"（unproven 同款，正式发布时置 nil 删除本段）。
-- 当前测：元老院 + 匕首 —— 尤利乌斯居中登基成凯撒，左右两张原版小丑受衔变元老；
--         桂冠登基，匕首弃牌换下一手爆发。
-- 形态映射参考：HIST.forms(:7) / initial_forms(:15) / special_guillotine(:39)
local DEBUG_ADD_CARDS = {
	"j_joker",        -- 左邻座 → 元老
	"j_hist_julius",  -- 尤利乌斯（登基后为凯撒，站在中间）
	"j_greedy_joker", -- 右邻座 → 元老
}

-- 调试负片：把这张 DEBUG 卡转成负片（测负片壳：原版自带 +1 自由槽，吞并补偿应跳过）
local DEBUG_NEGATIVE = nil -- "j_greedy_joker"

local DEBUG_ADD_CONSUMABLES = {
	"c_hist_laurel", -- 登基道具（罗马的玉玺）
	"c_hist_dagger", -- 匕首：随机弃牌，下一手 +1~10 倍率
}

if DEBUG_ADD_CARDS or DEBUG_ADD_CONSUMABLES then
	local start_run_ref = Game.start_run
	function Game:start_run(args)
		start_run_ref(self, args)
		if G.GAME and not G.GAME.hist_debug_cards_added then
			G.GAME.hist_debug_cards_added = true
			if DEBUG_ADD_CARDS then
				for _, center_key in ipairs(DEBUG_ADD_CARDS) do
					pcall(add_joker, center_key)
					if center_key == DEBUG_NEGATIVE then
						for _, c in ipairs(G.jokers.cards) do
							if c.config.center.key == center_key and not (c.edition and c.edition.negative) then
								c:set_edition({ negative = true }, true)
							end
						end
					end
				end
			end
			if DEBUG_ADD_CONSUMABLES then
				for _, center_key in ipairs(DEBUG_ADD_CONSUMABLES) do
					pcall(function()
						local c = SMODS.create_card({ key = center_key, area = G.consumeables })
						if c then
							c:add_to_deck()
							G.consumeables:emplace(c)
						end
					end)
				end
			end
		end
	end
end

-- 美术图集（assets/1x|2x，规格 71×95/格；1x 与 2x 各出一份，见开发规范 §美术）。
-- 尚未出图的卡不写 atlas，默认用原版图集帧占位；出图后在对应 items 文件里加 atlas 指过来。
SMODS.Atlas({ key = "hist_jokers", path = "jokers.png", px = 71, py = 95 })
SMODS.Atlas({ key = "hist_stickers", path = "stickers.png", px = 71, py = 95 })

-- 吞并角标：中英两帧（x=0 中文「秦」、x=1 英文「Qin」），按当前语言取。
-- G.SETTINGS 在 mod 加载时已就绪；万一拿不到就退回英文帧，不会崩。
local function hist_lang_zh()
	return G and G.SETTINGS and G.SETTINGS.language == "zh_CN"
end

-- 器物：断头台有中文版与法文版两张，故按语言选图集文件。
-- 注：Atlas 在 mod 加载时注册一次，游戏中切语言需重启才生效（与角标同理）。
-- 格位：0 传国玉玺 / 1 天子剑 / 2 断头台 / 3 桂冠 / 4 圣火令 / 5 涂油礼 / 6 和氏璧 / 7 王冠 ... 17-25 星图
SMODS.Atlas({
	key = "hist_relics",
	path = hist_lang_zh() and "relics.png" or "relics_en.png",
	px = 71,
	py = 95,
})
-- 政策（优惠券）：x=0 石人一只眼
SMODS.Atlas({ key = "hist_vouchers", path = "vouchers.png", px = 71, py = 95 })
-- 标签图标：34x34/格（0 革命预兆 / 1 加冕典礼），由 draw_tags.py 生成
SMODS.Atlas({ key = "hist_tags", path = "tags.png", px = 34, py = 34 })

-- "吞并"角标贴纸：被吞小丑右下角常驻标签（被吞=行省陈列，设计案 §3.2）
SMODS.Sticker({
	key = "hist_swallowed",
	atlas = "hist_stickers",
	pos = hist_lang_zh() and { x = 0, y = 0 } or { x = 1, y = 0 },
	badge_colour = HEX("8a6d1f"),
	prefix_config = { key = false },
	should_apply = false,
	order = 10,
	-- 贴纸文案走 descriptions.Other；按语言分表，注册时由 SMODS.process_loc_text 写入
	loc_txt = {
		["zh_CN"] = {
			name = "秦始皇",
			text = { "已被吞并，{C:attention}不再占用格子{}" },
		},
		["en-us"] = {
			name = "Qin Shi Huang",
			text = { "Swallowed: {C:attention}no longer takes up a slot{}" },
		},
	},
})

-- ===== 贴纸（hist_stickers）：中英各一帧，zh 在第 1 行、en 在第 2 行 =====
-- 图由 桌面/worldhist-art/draw_sticker_text.py 程序生成（1x 内容区 36x17，位于格子右下角）。

-- 免死金牌角标：本局第一次将被销毁时免除，用后即摘
SMODS.Sticker({
	key = "hist_exempt",
	atlas = "hist_stickers",
	pos = hist_lang_zh() and { x = 2, y = 0 } or { x = 2, y = 1 },
	badge_colour = HEX("c8a028"),
	prefix_config = { key = false },
	should_apply = false,
	order = 11,
	loc_txt = {
		["zh_CN"] = {
			name = "免死金牌",
			text = { "本局首次将被销毁时免除，", "{C:attention}随即失效{}" },
		},
		["en-us"] = {
			name = "Iron Certificate",
			text = { "Prevents the first destruction", "this run, then {C:attention}expires{}" },
		},
	},
})

-- 大宪章"人身保护"角标：当回合不可禁用/销毁，每回合随机重发
SMODS.Sticker({
	key = "hist_habeas",
	atlas = "hist_stickers",
	pos = hist_lang_zh() and { x = 3, y = 0 } or { x = 3, y = 1 },
	badge_colour = HEX("3f6e5a"),
	prefix_config = { key = false },
	should_apply = false,
	order = 12,
	loc_txt = {
		["zh_CN"] = {
			name = "人身保护",
			text = { "本回合不会被{C:attention}禁用{}或{C:attention}销毁{}" },
		},
		["en-us"] = {
			name = "Habeas Corpus",
			text = { "Cannot be {C:attention}debuffed{} or", "{C:attention}destroyed{} this round" },
		},
	},
})

-- 罗伯斯庇尔的"嫌疑"角标：被标记者本回合不结算
SMODS.Sticker({
	key = "hist_suspect",
	atlas = "hist_stickers",
	pos = hist_lang_zh() and { x = 4, y = 0 } or { x = 4, y = 1 },
	badge_colour = HEX("7c1f1f"),
	prefix_config = { key = false },
	should_apply = false,
	order = 13,
	loc_txt = {
		["zh_CN"] = {
			name = "嫌疑",
			text = { "本回合{C:attention}不结算{}" },
		},
		["en-us"] = {
			name = "Suspect",
			text = { "{C:attention}Does not score{} this round" },
		},
	},
})

-- 乾隆"御批"角标：打在手牌上，该牌每计分一次 +50 筹码，逐回合重发
SMODS.Sticker({
	key = "hist_yubi",
	atlas = "hist_stickers",
	pos = hist_lang_zh() and { x = 5, y = 0 } or { x = 5, y = 1 },
	badge_colour = HEX("b03a2e"),
	prefix_config = { key = false },
	should_apply = false,
	order = 14,
	loc_txt = {
		["zh_CN"] = {
			name = "御批",
			text = { "每次计分{C:chips}+50{} 筹码" },
		},
		["en-us"] = {
			name = "Imperial Red",
			text = { "{C:chips}+50{} Chips each time scored" },
		},
	},
})

-- 光荣革命"议会架空"角标：被标记的小丑本回合静默，每回合重发到最右侧
SMODS.Sticker({
	key = "hist_silenced",
	atlas = "hist_stickers",
	pos = hist_lang_zh() and { x = 6, y = 0 } or { x = 6, y = 1 },
	badge_colour = HEX("2f4858"),
	prefix_config = { key = false },
	should_apply = false,
	order = 15,
	loc_txt = {
		["zh_CN"] = {
			name = "议会架空",
			text = { "本回合{C:attention}静默{}，不触发效果" },
		},
		["en-us"] = {
			name = "Silenced",
			text = { "{C:attention}Silent{} this round,", "its effect does not trigger" },
		},
	},
})

-- 琥珀屋"镶金"角标：该小丑售价 +$8，且本局可被破例出售一次
SMODS.Sticker({
	key = "hist_amber",
	atlas = "hist_stickers",
	pos = hist_lang_zh() and { x = 7, y = 0 } or { x = 7, y = 1 },
	badge_colour = HEX("c9a227"),
	prefix_config = { key = false },
	should_apply = false,
	order = 16,
	loc_txt = {
		["zh_CN"] = {
			name = "镶金",
			text = { "售价{C:money}+$8{}，", "本局可破例出售一次" },
		},
		["en-us"] = {
			name = "Amber Clad",
			text = { "Sell value {C:money}+$8{};", "may be sold once this run" },
		},
	},
})

-- 凯撒登基"元老院"角标：凯撒左右相邻的小丑被授予元老身份，皇帝触发效果时各 +倍率
SMODS.Sticker({
	key = "hist_senator",
	atlas = "hist_stickers",
	pos = hist_lang_zh() and { x = 8, y = 0 } or { x = 8, y = 1 },
	badge_colour = HEX("7d3c98"),
	prefix_config = { key = false },
	should_apply = false,
	order = 17,
	loc_txt = {
		["zh_CN"] = {
			name = "元老",
			text = { "皇帝触发效果时", "{C:mult}+8{} 倍率" },
		},
		["en-us"] = {
			name = "Senator",
			text = { "When an Emperor triggers,", "gives {C:mult}+8{} Mult" },
		},
	},
})

local function load_folder(folder)
	local files = NFS.getDirectoryItems(HIST.path .. folder)
	table.sort(files)
	for _, f in ipairs(files) do
		if f:match("%.lua$") then
			assert(SMODS.load_file(folder .. "/" .. f))()
		end
	end
end

load_folder("items")
