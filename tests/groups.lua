local ns, test, eq, H = ...
local WithBoard, AsSoldier = H.WithBoard, H.AsSoldier

print("Groups.lua: group listings on the Board, applications, invites")

-- The Board's harness (tests/run.lua's WithBoard), with the groups' own state cleared before and
-- after, their redraw at once, and the game's invite and group state stubbed.
local function WithGroups(fn)
	WithBoard(function(w, B)
		local G = ns.Groups
		local saved = { after = G.after, random = G.random, party = C_PartyInfo, invite = InviteUnit, members = GetNumGroupMembers,
			inGroup = IsInGroup, leader = UnitIsGroupLeader, count = GetNumQuestLogEntries, title = GetQuestLogTitle }
		local ok, err = pcall(function()
			G.Reset()
			w.invited = {}
			G.after = function(_, _, f) return f() end
			G.random = function(a) return a or 0 end
			C_PartyInfo = { InviteUnit = function(name) w.invited[#w.invited + 1] = name end }
			InviteUnit = nil
			GetNumGroupMembers = function() return w.members or 0 end
			IsInGroup = function() return (w.members or 0) > 0 end
			UnitIsGroupLeader = function() return not w.notLeader end
			w.quests = {}
			GetNumQuestLogEntries = function() return #w.quests end
			GetQuestLogTitle = function(i)
				local q = w.quests[i]
				if not q then return nil end
				return q.title, q.level, q.group or 0, q.header or false, false, false, 0, q.id
			end
			fn(w, G, B)
		end)
		G.after, G.random, C_PartyInfo, InviteUnit, GetNumGroupMembers = saved.after, saved.random, saved.party, saved.invite, saved.members
		IsInGroup, UnitIsGroupLeader, GetNumQuestLogEntries, GetQuestLogTitle = saved.inGroup, saved.leader, saved.count, saved.title
		G.Reset()
		if not ok then error(err, 0) end
	end)
end

-- A listing as another player's addon sends it.
local function Listing(id, guild, kind, target, need, age, note, title, every)
	return ns.Groups.Encode({ id = id, guild = guild, kind = kind, target = target, level = 30, class = "WA", need = need or "113",
		size = 2, every = every or 10, age = age or 0, title = title, note = note })
end
local function Texts(lines)
	local out = {}
	for _, l in ipairs(lines) do out[#out + 1] = tostring(l.text) .. " | " .. tostring(l.right or "") end
	return table.concat(out, "\n")
end
local function Line(lines, text)
	for _, l in ipairs(lines) do if l.text and l.text:find(text, 1, true) then return l end end
	return nil
end
local function LastWhisper(w) return w.whispered[#w.whispered] end
local function Sent(w, prefix)
	for i = #w.sent, 1, -1 do if w.sent[i].msg:sub(1, #prefix) == prefix then return w.sent[i] end end
	return nil
end

test("1.2 groups: a listing's message, its checks, its words made safe; later fields are left for later versions", function()
	local G = ns.Groups
	local msg = G.Encode({ id = "a7", guild = "Olympus II", kind = "D", target = "DM", level = 18, class = "PR", need = "103", size = 2,
		every = 10, age = 3, note = " need |cffff0000heals|r~now " })
	eq(msg, "GL~a7~Olympus II~D~DM~18~PR~103~2~10~3~~need cffff0000heals r now")
	local e = G.Decode(msg)
	eq(e.kind, "D"); eq(e.target, "DM"); eq(e.need, "103"); eq(e.size, 2); eq(e.age, 3); eq(e.title, ""); eq(e.note, "need cffff0000heals r now")
	-- A quest carries its title (cut at 40 bytes); another kind's title is never read.
	e = G.Decode(G.Encode({ id = "q", guild = "Olympus II", kind = "Q", target = "1234", level = 30, need = "012", size = 1, every = 10, age = 0,
		title = "The Defias Brotherhood " .. string.rep("x", 40) }))
	eq(e.target, "1234"); eq(#e.title, 40)
	eq(G.Decode("GL~a~Olympus II~D~DM~18~PR~113~1~10~0~smuggled~hi").title, "", "a dungeon has no title")
	eq(G.Decode("GL~a~Olympus II~R~MC~60~PR~+++~12~10~0~~hi~future").note, "hi", "fields after the note: later versions'")
	-- An unknown place of a later version still shows, as Other.
	e = G.Decode("GL~a~Olympus II~D~NEWDG~18~PR~113~1~10~0~~")
	eq(G.Target(e.kind, e.target, e.title), ns.L.GROUPS_OTHER)
	eq(G.Target("D", "MC"), ns.L.GROUPS_OTHER, "a raid's key is no dungeon")
	for _, bad in ipairs({
		"GL~ABC~Olympus II~D~DM~18~PR~113~1~10~0~~", "GL~a~Olympus II~X~DM~18~PR~113~1~10~0~~", "GL~a~Olympus II~D~dm~18~PR~113~1~10~0~~",
		"GL~a~Olympus II~Q~DM~18~PR~113~1~10~0~~", "GL~a~Olympus II~Q~0~18~PR~113~1~10~0~~", "GL~a~Olympus II~D~DM~18~PR~11~1~10~0~~",
		"GL~a~Olympus II~D~DM~18~PR~1a3~1~10~0~~", "GL~a~Olympus II~D~DM~0~PR~113~1~10~0~~", "GL~a~Olympus II~D~DM~18~Pr~113~1~10~0~~",
		"GL~a~Olympus II~D~DM~18~PR~113~0~10~0~~", "GL~a~Olympus II~D~DM~18~PR~113~41~10~0~~", "GL~a~Olympus II~D~DM~18~PR~113~1~9~0~~",
		"GL~a~Olympus II~D~DM~18~PR~113~1~10~61~~", "GL~a~Olympus II~Q~12~18~PR~113~1~10~31~~", "GL~a~~D~DM~18~PR~113~1~10~0~~",
		"GL~a~Olympus II~D~DM~18~PR~113~1~10", "G1~a~Olympus II~D~42~PR~10~3~~", 42 }) do
		eq(G.Decode(bad), nil, tostring(bad))
	end
	-- The longest it gets: one message.
	local worst = G.Encode({ id = "zz", guild = string.rep("\195\169", 24), kind = "Q", target = "9999999", level = 60, class = "WA", need = "+++",
		size = 40, every = 30, age = 29, title = string.rep("\195\169", 30), note = string.rep("\195\169", 30) })
	assert(#worst <= 250, "one message: " .. #worst)
	assert(G.Decode(worst), "the longest decodes")
	-- An application: a role, the applicant's level and class, a note.
	local a = G.DecodeApply(G.EncodeApply("a7", "Olympus Zeus", "H", 31, "PR", "|cff00ff00hi~"))
	eq(a.role, "H"); eq(a.level, 31); eq(a.note, "cff00ff00hi")
	eq(G.DecodeApply("GA~a7~Olympus Zeus~X~31~PR~"), nil, "no such role")
	eq(G.DecodeApply("GA~a7~~T~31~PR~"), nil, "no guild")
	-- What a need says.
	eq(G.NeedText("113"), "Tank, Healer, Damage x3")
	eq(G.NeedText("0++"), "Healer +, Damage +")
	eq(G.NeedText("000"), ns.L.GROUPS_NEED_NONE)
	-- A 1.1 client's Board reads none of it: GL is no flag.
	eq(ns.Board.Decode(msg), nil)
end)

test("1.2 groups: the Board's strip; the flags page is as it was; a leader lists a dungeon group (where, roles, a note logged)", function()
	WithGroups(function(w, G, B)
		AsSoldier()
		B.HandlePost("CHANNEL", "Aldric-Realm", ns.Board.Encode({ id = "f1", guild = "Olympus Zeus", flag = "R", level = 30, class = "WA", every = 10, age = 0, note = "lf raid" }))
		-- The Flags section first: the strip, then the Board's page as before.
		local lines = B.Lines()
		assert(lines[2].nav, "the strip under the way back")
		eq(#lines[2].nav, 5); eq(lines[2].nav[1].text, ns.L.GROUPS_TAB_FLAGS); eq(lines[2].nav[1].selected, true)
		assert(Line(lines, "lf raid"), "the flags as before")
		assert(Line(lines, ns.L.BOARD_RAISE:format(ns.L.BOARD_FLAG_D)), "raising a flag as before")
		-- Dungeons: nothing listed; the way to list one.
		lines[2].nav[2].onClick()
		eq(G.View(), "D")
		lines = B.Lines()
		assert(not Line(lines, "lf raid"), "no flags here")
		assert(Line(lines, ns.L.GROUPS_EMPTY), Texts(lines))
		Line(lines, ns.L.GROUPS_LIST:format(ns.L.GROUPS_KIND_D)).onClick()
		-- Where: the dungeons, by level.
		lines = B.Lines()
		local dm = Line(lines, "> Deadmines")
		assert(dm and dm.right:find(ns.L.GROUPS_FROM_LEVEL:format(16), 1, true), Texts(lines))
		assert(not Line(lines, "Molten Core"), "no raid among the dungeons")
		dm.onClick()
		-- The roles: a click steps each one; damage from 3 to 4, then round to 0 and 1.
		lines = B.Lines()
		assert(Line(lines, ns.L.GROUPS_WHERE:format("|cffffd200Deadmines|r")), Texts(lines))
		local dmg = Line(lines, ns.L.GROUPS_WANTED:format(ns.L.GROUPS_ROLE_D, "|cffffd2003|r"))
		assert(dmg, Texts(lines))
		dmg.onClick(); dmg.onClick(); dmg.onClick()
		eq(G.Composing().need, "111")
		Line(B.Lines(), ns.L.GROUPS_WANTED:format(ns.L.GROUPS_ROLE_T, "|cffffd2001|r")).onClick()
		eq(G.Composing().need, "211")
		-- Post: the dialog says what goes out and to whom, before anything does.
		eq(#w.sent, 0, "nothing sent while composing")
		Line(B.Lines(), ns.L.GROUPS_POST).onClick()
		local p = w.popups[#w.popups]
		eq(p.name, "OLYMPUS_GROUPS_LIST")
		assert(p.a:find("Deadmines", 1, true) and p.a:find(ns.L.GROUPS_NEEDS:format("Tank x2, Healer, Damage"), 1, true), p.a)
		eq(p.b, ns.Comm.Audience())
		G.ConfirmList(p.data, "  bring |cffffffffwater ")
		G.ConfirmList(p.data, "twice") -- (Enter and the button both answer: once)
		local s = Sent(w, "GL~")
		eq(s.dist, "CHANNEL"); eq(s.logged, true, "a note goes logged")
		local e = G.Decode(s.msg)
		eq(e.kind, "D"); eq(e.target, "DM"); eq(e.need, "211"); eq(e.note, "bring cffffffffwater"); eq(e.guild, "Olympus II"); eq(e.size, 1)
		eq(#w.sent, 1, "one listing")
		eq(G.Mine().id, e.id)
		lines = B.Lines()
		assert(Line(lines, ns.L.GROUPS_MINE:format("Deadmines")), Texts(lines))
		assert(Line(lines, ns.L.GROUPS_NO_APPLICANTS))
		-- Raids say ours is under Dungeons.
		G.Show("R", true)
		assert(Line(B.Lines(), ns.L.GROUPS_MINE_ELSEWHERE:format(ns.L.GROUPS_KIND_D)))
		-- A second listing waits LIST_GAP; one without a note goes plain.
		eq(select(2, G.Post("R", "MC", nil, "+++", "")), "wait")
		w.clock = w.clock + G.LIST_GAP
		assert(G.Post("R", "MC", nil, "+++", ""))
		eq(w.sent[#w.sent - 1].msg, "GX~" .. e.id, "the old one comes down first")
		eq(w.sent[#w.sent].logged, false)
		eq(G.Mine().kind, "R")
	end)
end)

test("1.2 groups: others' listings on the Board, by kind; only Olympus guilds, never an ignored or netted-off player; lowered at once", function()
	WithGroups(function(w, G, B)
		AsSoldier()
		G.HandlePost("CHANNEL", "Aldric-Realm", Listing("a1", "Olympus Zeus", "D", "SFK", "103", 2, "lfm sfk"))
		G.HandlePost("CHANNEL", "Brenna-Realm", Listing("b1", "Olympus Zeus", "R", "MC", "+++", 0))
		G.HandlePost("CHANNEL", "Outsider-Realm", Listing("c1", "Horde Guild", "D", "DM"))
		G.HandlePost("CHANNEL", "Troll-Realm", Listing("t1", "Olympus Zeus", "D", "DM"))
		G.HandlePost("GUILD", "Cora-Realm", Listing("g1", "Olympus Zeus", "D", "DM"))
		G.HandlePost("WHISPER", "Dora-Realm", Listing("d1", "Olympus Zeus", "D", "DM"))
		eq(#G.List("D"), 1); eq(#G.List("R"), 1); eq(#G.List(), 2)
		G.Show("D", true)
		local lines = B.Lines()
		local card = Line(lines, "lfm sfk")
		assert(card, Texts(lines))
		assert(card.text:find("[Shadowfang Keep]", 1, true) and card.text:find(ns.L.GROUPS_NEEDS:format("Tank, Damage x3"), 1, true), card.text)
		assert(card.right:find("2/5", 1, true), card.right)
		eq(lines[2].nav[2].text, ns.L.GROUPS_TAB_D .. " (1)")
		eq(lines[2].nav[3].text, ns.L.GROUPS_TAB_R .. " (1)")
		-- The Realm's link counts them.
		assert(B.LinkLine().right:find(ns.L.GROUPS_LINK:format(2), 1, true))
		-- The search reads where, who and the note.
		assert(Line(B.Lines(ns.Fold("shadowfang")), "lfm sfk"))
		assert(not Line(B.Lines(ns.Fold("molten")), "lfm sfk"))
		-- A refresh updates it in place; its words without the logged API are dropped.
		w.logged = false
		G.HandlePost("CHANNEL", "Aldric-Realm", Listing("a1", "Olympus Zeus", "D", "SFK", "003", 3, "lfm sfk"))
		eq(G.List("D")[1].need, "003"); eq(G.List("D")[1].note, "")
		w.logged = true
		-- Lowered: gone, and a late refresh of it doesn't bring it back.
		G.HandleLower("CHANNEL", "Aldric-Realm", "GX~a1")
		eq(#G.List("D"), 0)
		G.HandlePost("CHANNEL", "Aldric-Realm", Listing("a1", "Olympus Zeus", "D", "SFK", "003", 4))
		eq(#G.List("D"), 0, "a lowered id stays down")
		-- Its hour over, a listing leaves; a quest's after half an hour.
		G.HandlePost("CHANNEL", "Cora-Realm", Listing("q1", "Olympus Zeus", "Q", "555", "012", 25, nil, "Kill Hogger"))
		eq(#G.List("Q"), 1)
		w.clock = w.clock + 6 * 60
		eq(#G.List("Q"), 0, "half an hour for a quest")
		eq(#G.List("R"), 1)
		w.clock = w.clock + 55 * 60
		eq(#G.List("R"), 0, "an hour for the rest, refreshed or not")
	end)
end)

test("1.2 groups: apply with a role the group needs (the note logged, to the leader alone); withdraw; the leader's answers", function()
	WithGroups(function(w, G, B)
		AsSoldier()
		G.HandlePost("CHANNEL", "Aldric-Realm", Listing("a1", "Olympus Zeus", "D", "SFK", "103", 0))
		G.Show("D", true)
		Line(B.Lines(), "Shadowfang Keep").onClick()
		local lines = B.Lines()
		assert(Line(lines, ns.L.GROUPS_APPLY_AS:format(ns.L.GROUPS_ROLE_T)), Texts(lines))
		assert(not Line(lines, ns.L.GROUPS_APPLY_AS:format(ns.L.GROUPS_ROLE_H)), "no healer wanted: no healer's button")
		Line(lines, ns.L.GROUPS_WHISPER:format("Aldric")).onClick()
		eq(w.told[#w.told], "Aldric", "the whisper is the player's own")
		eq(#w.whispered, 0)
		Line(lines, ns.L.GROUPS_APPLY_AS:format(ns.L.GROUPS_ROLE_T)).onClick()
		local p = w.popups[#w.popups]
		eq(p.name, "OLYMPUS_GROUPS_APPLY")
		eq(p.a, ns.L.GROUPS_APPLY_WHAT:format(ns.L.GROUPS_ROLE_T, "Shadowfang Keep", "Aldric"))
		G.ConfirmApply(p.data, "prot war, 25")
		local wh = LastWhisper(w)
		eq(wh.to, "Aldric-Realm"); eq(wh.logged, true)
		local a = G.DecodeApply(wh.msg)
		eq(a.id, "a1"); eq(a.role, "T"); eq(a.guild, "Olympus II"); eq(a.note, "prot war, 25"); eq(a.level, 42); eq(a.class, "PR")
		eq(#w.sent, 0, "nothing on the channel")
		lines = B.Lines()
		assert(Line(lines, ns.L.GROUPS_APP_SENT:format(ns.L.GROUPS_ROLE_T)), Texts(lines))
		-- A role the group doesn't need is refused; so is a second application too soon.
		eq(select(2, G.Apply("Aldric-Realm", "H")), "role")
		eq(select(2, G.Apply("Aldric-Realm", "D")), "wait")
		-- An answer from anyone but that leader, or for another listing, changes nothing.
		G.HandleAnswer("WHISPER", "Brenna-Realm", "GR~a1~I")
		G.HandleAnswer("WHISPER", "Aldric-Realm", "GR~zz~I")
		G.HandleAnswer("CHANNEL", "Aldric-Realm", "GR~a1~I")
		eq(G.Applied("Aldric-Realm").state, "sent")
		G.HandleAnswer("WHISPER", "Aldric-Realm", "GR~a1~I")
		eq(G.Applied("Aldric-Realm").state, "invited")
		assert(Line(B.Lines(), ns.L.GROUPS_APP_INVITED:format(ns.L.GROUPS_ROLE_T)))
		-- Withdrawn: the leader is told.
		Line(B.Lines(), ns.L.GROUPS_WITHDRAW).onClick()
		eq(LastWhisper(w).msg, "GW~a1"); eq(G.Applied("Aldric-Realm"), nil)
		-- Declined, and a listing lowered, end an application.
		w.clock = w.clock + G.APPLY_GAP
		assert(G.Apply("Aldric-Realm", "D"))
		G.HandleAnswer("WHISPER", "Aldric-Realm", "GR~a1~D")
		eq(G.Applied("Aldric-Realm"), nil)
		w.clock = w.clock + G.APPLY_GAP
		assert(G.Apply("Aldric-Realm", "D"))
		G.HandleLower("CHANNEL", "Aldric-Realm", "GX~a1")
		eq(G.Applied("Aldric-Realm"), nil)
		-- Five applications waiting at most.
		for i = 1, 6 do
			G.HandlePost("CHANNEL", "Lead" .. i .. "-Realm", Listing("l" .. i, "Olympus Zeus", "D", "DM", "113", 0))
		end
		for i = 1, 5 do assert(G.Apply("Lead" .. i .. "-Realm", "D")) end
		eq(select(2, G.Apply("Lead6-Realm", "D")), "many")
	end)
end)

test("1.2 groups: the leader's applicants; Invite is the game's invite by click, takes the role off the need; the last role closes the listing", function()
	WithGroups(function(w, G, B)
		AsSoldier()
		assert(G.Post("D", "DM", nil, "112", "lfm"))
		local id = G.Mine().id
		G.HandleApply("WHISPER", "Aldric-Realm", G.EncodeApply(id, "Olympus Zeus", "T", 20, "WA", "prot"))
		G.HandleApply("WHISPER", "Brenna-Realm", G.EncodeApply(id, "Olympus Zeus", "D", 19, "MA", ""))
		G.HandleApply("WHISPER", "Cora-Realm", G.EncodeApply(id, "Olympus Zeus", "H", 18, "PR", ""))
		-- Not for this listing, not whispered, not of an Olympus guild, ignored: nothing.
		G.HandleApply("WHISPER", "Dora-Realm", G.EncodeApply("zz", "Olympus Zeus", "D", 19, "MA", ""))
		G.HandleApply("CHANNEL", "Dora-Realm", G.EncodeApply(id, "Olympus Zeus", "D", 19, "MA", ""))
		G.HandleApply("WHISPER", "Dora-Realm", G.EncodeApply(id, "Horde Guild", "D", 19, "MA", ""))
		G.HandleApply("WHISPER", "Troll-Realm", G.EncodeApply(id, "Olympus Zeus", "D", 19, "MA", ""))
		eq(#G.Applicants(), 3)
		G.Show("D", true)
		local lines = B.Lines()
		assert(Line(lines, ns.L.GROUPS_APPLICANTS:format(3)), Texts(lines))
		local tank = Line(lines, "prot")
		assert(tank and tank.text:find(ns.L.GROUPS_ROLE_T, 1, true), Texts(lines))
		-- Nothing invites until the leader clicks Invite.
		eq(#w.invited, 0)
		tank.onClick()
		lines = B.Lines()
		Line(lines, "> " .. ns.L.GROUPS_INVITE).onClick()
		eq(w.invited[1], "Aldric")
		eq(LastWhisper(w).to, "Aldric-Realm"); eq(LastWhisper(w).msg, "GR~" .. id .. "~I")
		eq(G.Mine().need, "012", "the tank is found")
		local s = Sent(w, "GL~")
		eq(G.Decode(s.msg).need, "112", "the update waits UPDATE_GAP after the listing went")
		w.clock = w.clock + G.UPDATE_GAP
		G.Tick()
		eq(G.Decode(Sent(w, "GL~").msg).need, "012", "then goes")
		-- Declined: told, and off the list.
		G.Decline("Brenna-Realm")
		eq(LastWhisper(w).msg, "GR~" .. id .. "~D")
		eq(#G.Applicants(), 2)
		-- Not the group's leader: no invite, and the player is told why.
		w.members, w.notLeader = 2, true
		eq(select(2, G.Invite("Cora-Realm")), "leader")
		eq(#w.invited, 1)
		w.notLeader = false
		-- One healer and two damage wanted: the healer found, the damage still wanted.
		G.Invite("Cora-Realm")
		eq(G.Mine().need, "002")
		-- The last of them: the listing closes, its GX goes, and the ones still waiting are told.
		w.clock = w.clock + G.APPLY_GAP
		G.HandleApply("WHISPER", "Dora-Realm", G.EncodeApply(id, "Olympus Zeus", "D", 19, "MA", ""))
		G.HandleApply("WHISPER", "Eda-Realm", G.EncodeApply(id, "Olympus Zeus", "D", 19, "MA", ""))
		G.HandleApply("WHISPER", "Finn-Realm", G.EncodeApply(id, "Olympus Zeus", "D", 19, "MA", ""))
		G.Invite("Dora-Realm"); G.Invite("Eda-Realm")
		eq(G.Mine(), nil, "every role found: lowered")
		eq(Sent(w, "GX~").msg, "GX~" .. id)
		eq(LastWhisper(w).to, "Finn-Realm"); eq(LastWhisper(w).msg, "GR~" .. id .. "~F")
		-- A party of five, however it filled, takes its listing down; a raid's doesn't.
		w.clock = w.clock + G.LIST_GAP
		w.members = 4
		assert(G.Post("D", "DM", nil, "001", ""))
		G.Tick()
		assert(G.Mine(), "four: still listed")
		w.members = 5
		G.Tick()
		eq(G.Mine(), nil, "five: lowered")
		w.clock = w.clock + G.LIST_GAP
		assert(G.Post("R", "MC", nil, "+++", ""))
		G.Tick()
		assert(G.Mine(), "a raid of five goes on")
	end)
end)

test("1.2 groups: the Board's ask is answered with our listing; it survives a /reload; it ends after its hour; /oly group", function()
	WithGroups(function(w, G, B)
		AsSoldier()
		assert(G.Post("R", "MC", nil, "+++", ""))
		local id = G.Mine().id
		-- Someone opens the Board: holders answer with their flag, and ours with the listing.
		B.HandleAsk("CHANNEL", "Asker-Realm", "GQ~")
		for _, t in ipairs(w.later) do if t.where == "board answer" then t.fn() end end
		local wh = LastWhisper(w)
		eq(wh.to, "Asker-Realm"); eq(G.Decode(wh.msg).id, id)
		-- A whispered listing is taken only after our own ask.
		G.HandlePost("WHISPER", "Brenna-Realm", Listing("b1", "Olympus Zeus", "D", "DM"))
		eq(#G.List("D"), 0)
		ns.Comm.joinedAt = w.clock - 60
		assert(B.Ask())
		G.HandlePost("WHISPER", "Brenna-Realm", Listing("b1", "Olympus Zeus", "D", "DM"))
		eq(#G.List("D"), 1)
		-- A /reload keeps our listing and its applicants.
		G.HandleApply("WHISPER", "Aldric-Realm", G.EncodeApply(id, "Olympus Zeus", "H", 60, "PR", "hi"))
		local saved = ns.rdb.groups
		G.Reset()
		ns.rdb.groups = saved
		G.Restore()
		eq(G.Mine().id, id); eq(#G.Applicants(), 1); eq(G.Applicants()[1].note, "hi")
		-- Repeated every interval, lowered after its hour.
		local before = #w.sent
		w.clock = w.clock + 10 * 60
		G.Tick()
		eq(#w.sent, before + 1)
		w.clock = w.clock + 50 * 60
		G.Tick()
		eq(G.Mine(), nil)
		eq(w.sent[#w.sent].msg, "GX~" .. id)
		-- /oly group opens the Board on a kind; off lowers ours.
		B.Slash("group", "raid")
		eq(G.View(), "R"); eq(ns.Views.BoardShown(), true)
		B.Slash("lfg", "")
		eq(G.View(), "flags", "/oly lfg: the flags")
		B.Slash("group", "off")
		B.Slash("group", "nonsense")
		assert(w.printed[#w.printed]:find("/oly group", 1, true), w.printed[#w.printed])
		G.Show("flags", true)
	end)
end)

test("1.2 groups: a quest from our own log, its title with it; quests we have come first", function()
	WithGroups(function(w, G, B)
		AsSoldier()
		w.quests = { { title = "Elwynn Forest", header = true }, { title = "Kill Hogger", level = 11, id = 176, group = 3 },
			{ title = "Wolves Across the Border", level = 6, id = 33 } }
		G.Show("Q", true)
		Line(B.Lines(), ns.L.GROUPS_LIST:format(ns.L.GROUPS_KIND_Q)).onClick()
		local lines = B.Lines()
		assert(not Line(lines, "> Elwynn Forest"), "a header is no quest")
		local hogger = Line(lines, "> Kill Hogger")
		assert(hogger and hogger.right:find(ns.L.GROUPS_GROUP_QUEST, 1, true), Texts(lines))
		hogger.onClick()
		Line(B.Lines(), ns.L.GROUPS_POST).onClick()
		G.ConfirmList(w.popups[#w.popups].data, "")
		local s = Sent(w, "GL~")
		eq(s.logged, true, "a title is words: logged")
		local e = G.Decode(s.msg)
		eq(e.target, "176"); eq(e.title, "Kill Hogger")
		-- Others' quests: the ones in our log first, marked.
		G.HandlePost("CHANNEL", "Aldric-Realm", Listing("a1", "Olympus Zeus", "Q", "999", "012", 0, nil, "Other Quest"))
		w.clock = w.clock + 1
		G.HandlePost("CHANNEL", "Brenna-Realm", Listing("b1", "Olympus Zeus", "Q", "33", "012", 0, nil, "Wolves Across the Border"))
		local list = G.List("Q")
		eq(list[1].sender, "Brenna-Realm")
		assert(G.Card(list[1]).text:find(ns.L.GROUPS_IN_LOG, 1, true))
		assert(not G.Card(list[2]).text:find(ns.L.GROUPS_IN_LOG, 1, true))
	end)
end)

test("1.2 groups: English and Portuguese for every string; the help names /oly group", function()
	local pt = {}
	local saved = GetLocale
	GetLocale = function() return "ptBR" end
	local ok, err = pcall(function() assert(loadfile(H.ADDON_DIR .. "Locales.lua"))("Olympus", pt) end)
	GetLocale = saved
	if not ok then error(err, 0) end
	local n = 0
	for key, en in pairs(ns.L) do
		if type(key) == "string" and key:find("^GROUPS_") then
			n = n + 1
			local br = rawget(pt.L, key)
			assert(type(en) == "string" and en ~= "", "English " .. key)
			assert(type(br) == "string" and br ~= "", "pt-BR " .. key)
			local function Args(s) local out = {} for a in s:gmatch("%%%a") do out[#out + 1] = a end return table.concat(out) end
			eq(Args(br), Args(en), key .. ": format arguments")
		end
	end
	assert(n > 60, "the strings: " .. n)
	assert(ns.L.HELP_GROUPS:find("/oly group", 1, true))
end)
