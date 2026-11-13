-- items/tags.lua — 标签线（对应设计案 §五.5/§10.2）
-- 占位图：不写 atlas，pos 指原版 Tag 图集帧

return {
	items = {
		-- 革命预兆：下一个 Boss 必为革命者（设计案 §五.5）
		-- 让路易十六的头"跳过革命者 Boss"可控，形成小赌局
		SMODS.Tag({
			key = "revolution_omen",
			pos = { x = 0, y = 0 },
			apply = function(self, tag, context)
				if context.type == "new_blind_choice" then
					G.GAME.round_resets.blind_choices.Boss = "bl_hist_robespierre"
					tag:yep("+", G.C.RED, function()
						return true
					end)
					return true
				end
			end,
		}),

		-- 加冕典礼：打开后生成 1 张随机登基器物（设计案 §10.2 供应层）
		SMODS.Tag({
			key = "coronation",
			pos = { x = 1, y = 0 },
			apply = function(self, tag, context)
				if context.type == "new_blind_choice" then
					local pool = {}
					for k in pairs(HIST.crown_items) do
						pool[#pool + 1] = k
					end
					local give = pseudorandom_element(pool, pseudoseed("hist_coronation"))
					tag:yep("+", G.C.GOLD, function()
						local c = SMODS.create_card({ key = give, area = G.consumeables })
						if c then
							c:add_to_deck()
							G.consumeables:emplace(c)
						end
						return true
					end)
					return true
				end
			end,
		}),
	},
}
