local extra_maps_dir = minetest.get_modpath(minetest.get_current_modname()) .. "/maps/"
local ctf_maps_dir = ctf_map.maps_dir

local old_file_exists = ctf_core.file_exists
function ctf_core.file_exists(file_path)
	local file_name = string.match(file_path, ".*/(.*)")
	local textures_dir = minetest.get_modpath("ctf_extra_maps") .. "/textures/"
	return old_file_exists(textures_dir .. file_name) or
		old_file_exists(file_path)
end

local old_skybox_exists = ctf_map.skybox_exists
function ctf_map.skybox_exists(path)
	local map_name = string.match(path, ".*/(.*)")
	local textures_dir = minetest.get_modpath("ctf_extra_maps") .. "/textures/"

	return old_file_exists(textures_dir .. map_name .. "Up.png") or
		old_skybox_exists(path)
end

local all_extra_maps = minetest.get_dir_list(extra_maps_dir, true)
table.sort(all_extra_maps)
ctf_map.maps_dir = extra_maps_dir
for i, dirname in ipairs(all_extra_maps) do
	local lua_file = extra_maps_dir .. dirname .. "/init.lua"
	if ctf_core.file_exists(lua_file) then
		dofile(lua_file)
	end

	local idx = #ctf_modebase.map_catalog.maps + 1
	if idx > 50 then idx = -(idx - 50) end -- Now we can have 99 maps without them loading outside world bounds!
	local map = ctf_map.load_map_meta(idx, dirname)
	map.source_mod = "ctf_extra_maps"

	if table.indexof(ctf_modebase.map_catalog.map_names, map.name) == -1 then
		table.insert(ctf_modebase.map_catalog.maps, map)
		table.insert(ctf_modebase.map_catalog.map_names, map.name)
		ctf_modebase.map_catalog.map_dirnames[map.dirname] = #ctf_modebase.map_catalog.maps
	end
end
ctf_map.maps_dir = ctf_maps_dir


-- CTF next map selection code
local maps_pool = {}
local used_maps = {}
local used_maps_idx = 1

for i = 1, #ctf_modebase.map_catalog.maps do
	table.insert(maps_pool, i)
end

local map_repeat_interval
local function update_repeate_interval()
	local enabled_count = 0
	for i, meta in pairs(ctf_modebase.map_catalog.maps) do
		if meta.enabled ~= false then
			enabled_count = enabled_count + 1
		end
	end
	map_repeat_interval = math.floor(enabled_count / 2)
end
update_repeate_interval()

function ctf_modebase.map_catalog.select_map(filter)
	local maps = {}
	for idx, map in ipairs(maps_pool) do
		local meta = ctf_modebase.map_catalog.maps[map]
		if (not filter or filter(meta)) and meta.enabled then
			table.insert(maps, idx)
		end
	end

	assert(#maps > 0)
	local selected = maps[math.random(1, #maps)]
	ctf_modebase.map_catalog.current_map = maps_pool[selected]

	if map_repeat_interval > 0 then
		if #used_maps < map_repeat_interval then
			table.insert(used_maps, maps_pool[selected])
			maps_pool[selected] = maps_pool[#maps_pool]
			maps_pool[#maps_pool] = nil
		else
			used_maps[used_maps_idx], maps_pool[selected] = maps_pool[selected], used_maps[used_maps_idx]
			used_maps_idx = used_maps_idx + 1
			if used_maps_idx > #used_maps then
				used_maps_idx = 1
			end
		end
	end
end

local old_place_map = ctf_map.place_map
function ctf_map.place_map(mapmeta, callback)
	if mapmeta.source_mod == "ctf_extra_maps" then
		ctf_map.maps_dir = extra_maps_dir
	else
		ctf_map.maps_dir = ctf_maps_dir
	end
	old_place_map(mapmeta, callback)
	ctf_map.maps_dir = ctf_maps_dir
end

-- Disable maps based on Minetest settings
local disabled_maps_str = minetest.settings:get("ctf_extra_maps_disabled_maps") or "maze,serpents_pass"
for map_name in string.gmatch(disabled_maps_str, "([^,]+)") do
	local index
	for i, meta in pairs(ctf_modebase.map_catalog.maps) do
		if meta.dirname == map_name then
			index = i
			break
		end
	end
	if index then
		ctf_modebase.map_catalog.maps[index].enabled = false
	end
end

local function mark_disabled_map_names()
	for i, meta in pairs(ctf_modebase.map_catalog.maps) do
		if meta.enabled == false then
			ctf_modebase.map_catalog.map_names[i] =
				"DISABLED: " .. meta.name
		else
			ctf_modebase.map_catalog.map_names[i] = meta.name
		end
	end
end
mark_disabled_map_names()


-- Commands

minetest.register_chatcommand("audit_maps", {
	privs = {server = true},
	description = "Show which ctf_extra_maps maps are already in capturetheflag."
		.. " Also show capturetheflag maps that are disabled in capturetheflag but not present in ctf_extra_maps",
	func = function(name, param)
		-- You can't run minetest.get_dir_list() from a chat command !?!
		if param ~= "WTH" then
			minetest.after(0, function()
				local success, output = minetest.registered_chatcommands.audit_maps.func(name, "WTH")
				minetest.chat_send_player(name, output)
			end)
			return true, ""
		end

		local ctf_maps = minetest.get_dir_list(ctf_maps_dir, true)
		local textures_list = minetest.get_dir_list(minetest.get_modpath("ctf_extra_maps") .. "/textures", false)

		local output = ""
		local ctf_maps_enabled = {}
		local ctf_maps_disabled = {}
		for i, name in pairs(ctf_maps) do
			local meta = ctf_map.load_map_meta(1, name)
			if meta.map_version and meta.enabled then
				table.insert(ctf_maps_enabled, name)
			else
				table.insert(ctf_maps_disabled, name)
			end
		end

		output = output
			.. "Maps enabled in capturetheflag and ctf_extra_maps:"

		local tmp = ""
		for i, name in pairs(all_extra_maps) do
			if table.indexof(ctf_maps_enabled, name) ~= -1 then
				tmp = tmp .. "\n " .. name
			end
		end
		if tmp == "" then tmp = "\n(none)" end
		output = output .. tmp .. "\n\n"

		output = output .. "Maps disabled in capturetheflag but not present in ctf_extra_maps:"
		local tmp = ""
		for i, name in pairs(ctf_maps_disabled) do
			if table.indexof(all_extra_maps, name) == -1 then
				tmp = tmp .. "\n " .. name
			end
		end
		if tmp == "" then tmp = "\n(none)" end
		output = output .. tmp .. "\n\n"

		output = output .. "Textures in ctf_extra_maps with no associated map:"
		local tmp = ""
		for i, texture in pairs(textures_list) do
			local map_name = texture
			for i, suffix in pairs({"_screenshot", "Front", "Back", "Right", "Left", "Up", "Down"}) do
				map_name = map_name:gsub(suffix .. ".png$", "")
			end

			local map_found
			for i, map in pairs(all_extra_maps) do
				if map == map_name then
					map_found = true
					break
				end
			end
			if not map_found then
				tmp = tmp .. "\n" .. texture
			end
		end
		if tmp == "" then tmp = "\n(none)" end
		output = output .. tmp .. "\n\n"

		output = output .. "Maps in ctf_extra_maps that contain PNG files:"
		local tmp = ""
		for i, name in pairs(all_extra_maps) do
			local maps = minetest.get_dir_list(extra_maps_dir .. name, false)
			for i, file in pairs(maps) do
				if file:find(".png$") then
					tmp = tmp .. "\n" .. name
					break
				end
			end
		end
		if tmp == "" then tmp = "\n(none)" end
		output = output .. tmp .. "\n\n"

		return true, output
	end,
})

local env = minetest.request_insecure_environment()
minetest.register_chatcommand("fix_screenshots", {
	privs = {server = true},
	description = "Fix the map screenshots in Capture The Flag game",
	func = function(name, param)
		if not env then
			return false, "ERROR: ctf_extra_maps must be added as a trusted mod in Minetest settings."
		end
		minetest.after(0, function()
			local ctf_maps = minetest.get_dir_list(ctf_maps_dir, true)
			for i, name in pairs(ctf_maps) do
				for i, suffix in pairs({"screenshot", "Back", "Down", "Front", "Left", "Right", "Up"}) do
					local in_name = ctf_maps_dir .. name .. "/skybox/" .. suffix .. ".png"
					local out_name = ctf_maps_dir .. "../textures/" .. name .. suffix .. ".png"
					if suffix == "screenshot" then
						in_name = ctf_maps_dir .. name .. "/screenshot.png"
						out_name = ctf_maps_dir .. "../textures/" .. name .. "_screenshot.png"
					end
					local in_file = env.io.open(in_name, "rb")
					if in_file then
						local data = in_file:read("*all")
						local out_file = env.io.open(out_name, "wb")
						if out_file then
							out_file:write(data)
							out_file:close()
						end
					end
				end
			end
			minetest.chat_send_player(name, "Finished copying images. Restart the server for the changes to take effect.")
		end)
		return true, ""
	end
})

local formspec_state = {}
minetest.register_chatcommand("disable_maps", {
	privs = {server = true},
	description = "Disable/enable CTF maps",
	func = function(player_name, param)
		local formspec = "formspec_version[3]size[10,13]"
			.. "label[1,1;Uncheck maps to disable them]"
			.. "scroll_container[0.5,2;9,9;scrollbar;vertical;0.5]"

		local map_meta_list = ctf_modebase.map_catalog.maps
		local disabled_maps = {}
		for i, meta in pairs(map_meta_list) do
			local selected = meta.enabled ~= false
			local name = meta.dirname
			formspec = formspec
				.. "checkbox[0," .. (i - 0.5) * 0.5 .. ";:" .. name .. ";" .. name .. ";" .. tostring(selected) .. "]"

			if not selected then
				disabled_maps[meta.dirname] = true
			end
		end

		formspec = formspec ..
			"scroll_container_end[]"
			.. "scrollbaroptions[max=" .. #map_meta_list - 18 .. ";smallstep=1]"
			.. "scrollbar[9,2;0.5,9;vertical;scrollbar;0]"
			.. "button_exit[0.5,11.5;4,1;save;Save]"
			.. "button_exit[5.5,11.5;4,1;cancel;Cancel]"
		minetest.show_formspec(player_name, "ctf_extra_maps:disable_maps", formspec)

		formspec_state[player_name] = disabled_maps
		return true
	end,
})

minetest.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= "ctf_extra_maps:disable_maps" then return false end
	local player_name = player:get_player_name()
	for key, value in pairs(fields) do
		if key:find("^:") then
			local map_name = key:gsub(":", "")
			if value == "false" then
				formspec_state[player_name][map_name] = true
			else
				formspec_state[player_name][map_name] = nil
			end
		end
	end

	if fields.save then
		local disabled_maps = formspec_state[player_name]

		for i, meta in pairs(ctf_modebase.map_catalog.maps) do
			ctf_modebase.map_catalog.maps[i].enabled = disabled_maps[meta.dirname] == nil
		end

		local disabled_list = {}
		for map_name in pairs(disabled_maps) do
			table.insert(disabled_list, map_name)
		end
		minetest.settings:set("ctf_extra_maps_disabled_maps", table.concat(disabled_list, ","))

		mark_disabled_map_names()
		update_repeate_interval()
	end

	if fields.quit then formspec_state[player_name] = nil end
	return true
end)
