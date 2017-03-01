local require_rel
local path = ""
if arg and arg[0] then
    package.path = arg[0]:match("(.-)[^\\/]+$") .. "?.lua;" .. package.path
    require_rel = require
    path = arg[0]:match("(.-)[^\\/]+$") .. ""
end

local params = {...}
local yang = require_rel('parser')
local snabb = require_rel('snabb')

local sr = require("libsysrepoLua")

local action = nil

function string.ends(String,End)
   return End=='' or string.sub(String,-string.len(End))==End
end

function string.starts(String,Starts)
   return Starts=='' or string.sub(String,1,string.len(Starts))==Starts
end

function string.xpath_compare(First, Second, yang_model)
    local ctx1 = sr.Xpath_Ctx()
    local ctx2 = sr.Xpath_Ctx()

    local common = ""
    local node1
    local node2

    while true do
        if node1 == nil then
            node1 = ctx1:next_node(First)
	else
            node1 = ctx1:next_node(nil)
        end
        if node2 == nil then
            node2 = ctx2:next_node(Second)
	else
            node2 = ctx2:next_node(nil)
        end

        if (node1 == nil or node2 == nil) then break end

	if (node1 == node2) then common = common.."/"..node1 end

	--//TODO add namespace and keys
    end

    common = "/"..yang_model..":" .. string.sub(common, 2)
    return common
end

function string.skip_node(xpath)
    local ctx = sr.Xpath_Ctx()

    local node = ctx:next_node(xpath)
    if node == nil then return false end
    local id = 0
    while true do
        node = ctx:next_node(nil)
	if node == nil then break end
        id = id + 1
    end

    if id < 1 then return true end

    local last_node = ctx:node_idx(xpath, id)
    local prev_node = ctx:node_idx(xpath, id - 1)

    while true do
        local key =  ctx:next_key_name(nil)
        if key == nil then break end
	if last_node == key then return true end
    end
    return false
end

local function get_key_value(s, xpath)
    local keys = ""
    if (xpath == "/softwire-config/binding-table/psid-map") then
        for k1,v1 in pairs(s) do if (type(v1) == "table") then for k,v in pairs(v1) do
            if (v["keyword"] == "addr") then
                keys = "[addr='"..v["argument"].."']"
            end
        end end end
    elseif (xpath == "/softwire-config/binding-table/softwire") then
        local default_padding = nil
        for k1,v1 in pairs(s) do if (type(v1) == "table") then for k,v in pairs(v1) do
            if (v["keyword"] == "ipv4") then
                keys = keys.."[ipv4='"..v["argument"].."']"
            end
        end end end
        for k1,v1 in pairs(s) do if (type(v1) == "table") then for k,v in pairs(v1) do
            if (v["keyword"] == "psid") then
                keys = keys.."[psid='"..v["argument"].."']"
            end
        end end end
        for k1,v1 in pairs(s) do
            if (type(v1) == "table") then for k,v in pairs(v1) do if (v["keyword"] == "padding") then
            default_padding = v["argument"]
                keys = keys.."[padding='"..v["argument"].."']"
            end
        end end end
        if (default_padding == nil) then
            keys = keys.."[padding='0']"
            --TODO add padding
        end
    end
    return keys
end

local function send_to_sysrepo(set_item_list, sess_snabb, xpath, value)
    -- sysrepo expects format "/yang-model:container/..
    xpath = "/"..YANG_MODEL..":" .. string.sub(xpath, 2)
--    ret = string.xpath_compare(xpath, xpath2, "snabb-softwire-v1")
--    print("RET -> " .. ret)

    local skip_node = string.skip_node(xpath)
    if not skip_node then
	if not string.starts(value, "<unknown>:") then
            table.insert(set_item_list, {xpath, value})
        end
    end
    --local function set()
    --    sess_snabb:set_item_str(xpath, value)
    --    collectgarbage()
    --end
    --ok,res=pcall(set)
    --if not ok then
    --    -- set_item_str will fail for key elements
    --    -- print(res)
    --end
end

local function map_to_xpath(set_item_list, s, path, sess_snabb)
    local ts = type(s)
    if (ts ~= "table") then
        send_to_sysrepo(set_item_list, sess_snabb, path, s)
    return end
    for k,v in pairs(s) do
	if (k == "keyword") then
	elseif (k == "keyword" or k == "loc" or type(k) == "number") then
            map_to_xpath(set_item_list, v, path, sess_snabb)
	elseif (k == "statements") then
            local xpath = path.."/"..tostring(s["keyword"])
            map_to_xpath(set_item_list, v, xpath..get_key_value(s, xpath), sess_snabb)
	elseif (k == "argument") then
            local xpath = path.."/"..tostring(s["keyword"])
            map_to_xpath(set_item_list, v, xpath..get_key_value(s, xpath), sess_snabb)
	else
            local xpath = path.."/"..tostring(s["keyword"])
            map_to_xpath(set_item_list, v, xpath..get_key_value(s, xpath), sess_snabb)
        end
    end
    return
end

local function map_to_oper(s, path, oper_list)
    local ts = type(s)
    if (ts ~= "table") then
        xpath = "/"..YANG_MODEL..":" .. string.sub(path, 2)
	oper_list[#oper_list + 1] = {xpath, s}
    return end
    for k,v in pairs(s) do
	if (k == "keyword") then
	elseif (k == "keyword" or k == "loc" or type(k) == "number") then
            map_to_oper(v, path, oper_list)
	elseif (k == "statements") then
            local xpath = path.."/"..tostring(s["keyword"])
            map_to_oper(v, xpath, oper_list)
	elseif (k == "argument") then
            local xpath = path.."/"..tostring(s["keyword"])
            map_to_oper(v, xpath, oper_list)
	else
            local xpath = path.."/"..tostring(s["keyword"])
            map_to_oper(v, xpath, oper_list)
        end
    end
    return
end

local function load_snabb_data(action)
	local datastore_empty = false

	local function sysrepo_call()
		local conn = sr.Connection("application")
		local sess = sr.Session(conn, sr.SR_DS_STARTUP, sr.SR_SESS_DEFAULT)
		local values = nil
		local xpath = "/" .. YANG_MODEL .. ":*//*"
		values = sess:get_items(xpath)

		if (values == nil) then
			datastore_empty = true
		else
			datastore_empty = false
		end
		collectgarbage()
	end
	ok,res=pcall(sysrepo_call) if not ok then datastore_empty = true end

	if datastore_empty then
		local conn_snabb = sr.Connection("application")
		local sess_snabb = sr.Session(conn_snabb, sr.SR_DS_STARTUP, sr.SR_SESS_DEFAULT)

		local content
		local COMMAND = path.."../src/snabb config get " .. ID .. ' "/"'
		local handle = io.popen(COMMAND)
		local result = handle:read("*a")
		if (result == "") then
			print("COMMAND: " .. COMMAND)
		else
			content = result
		end
		handle:close()

		local function sysrepo_call()
			local parsed_data = yang.parse(content, nil)
			local set_item_list = {}
			map_to_xpath(set_item_list, parsed_data, "", sess_snabb)
			-- set all items in the list
			for i, el in ipairs(set_item_list) do
			    sess_snabb:set_item_str(el[1], el[2])
			end

			print("========== COMMIT SNABB CONFIG DATA TO SYSREPO: ==========")
			sess_snabb:commit()
			collectgarbage()
		end
		ok,res=pcall(sysrepo_call) if not ok then datastore_empty = true end
	else
		local conn_snabb = sr.Connection("application")
		local sess_snabb = sr.Session(conn_snabb, sr.SR_DS_STARTUP, sr.SR_SESS_DEFAULT)

		local binding_table_xpath = "/"..YANG_MODEL..":softwire-config"
		action:set(binding_table_xpath, sess_snabb)

		action:run()

		print("========== COMMIT SYSREPO CONFIG DATA TO SNABB: ==========")
		collectgarbage()
	end
end

-- Function to be called for subscribed client of given session whenever configuration changes.
function module_change_cb(sess, module_name, event, private_ctx)
	if (event == sr.SR_EV_APPLY) then
		-- commit changes to startup datastore
		local function update_startup_datastore()
			local start_conn = sr.Connection("application")
			local start_sess = sr.Session(start_conn, sr.SR_DS_STARTUP, sr.SR_SESS_DEFAULT)
			start_sess:copy_config(YANG_MODEL, sr.SR_DS_RUNNING, sr.SR_DS_STARTUP)
			start_sess:commit()
			collectgarbage()
		end
		ok,res=pcall(update_startup_datastore) if not ok then print(res) end

		return tonumber(sr.SR_ERR_OK)
	end

	local delete_all = true
	local acc = {xpath = nil, action = nil, count = 0}

	local function sysrepo_call()
		local change_path = "/" .. module_name .. ":*"
		local it = sess:get_changes_iter(change_path)

		while true do
			local change = sess:get_change_next(it)
			if (change == nil) then break end
			acc.count = acc.count + 1
			if (change:oper() ~= sr.SR_OP_DELETED) then delete_all = false end
			local op = change:oper()
			local new = change:new_val()
			local old = change:old_val()
			if (op == sr.SR_OP_DELETED) then
				if (acc.xpath == nil) then
					acc.xpath = old:xpath()
					acc.action = "remove"
				else
					local change = string.xpath_compare(old:xpath(), acc.xpath, module_name)
					if (change == old:xpath() and snabb.print_value(old) == nil and delete_all) then
						acc.xpath = change
						acc.action = "remove"
					else
						acc.xpath = change
						acc.action = "set"
					end
				end
			elseif (op == sr.SR_OP_CREATED or op == sr.SR_OP_MODIFIED) then
				delete_all = false
				acc.action = "set"
				if (acc.xpath == nil) then
					acc.xpath = new:xpath()
				else
					local change = string.xpath_compare(new:xpath(), acc.xpath, module_name)
					acc.xpath = change
				end
			end
		end
		collectgarbage()
	end
	ok,res=pcall(sysrepo_call) if not ok then print(res) end

	if acc.action == "remove" then
		action:delete(acc.xpath, sess)
	elseif acc.action == "set" then
		action:set(acc.xpath, sess)
	end

	collectgarbage()
	local status = action:run()
	if not status then
		return tonumber(sr.SR_ERR_INTERNAL)
	end

	return tonumber(sr.SR_ERR_OK)
end

-- Function to be called for operational data
function dp_get_items_cb(xpath, val_holder, private_ctx)

	local snabb_state
	local COMMAND = path.."../src/snabb config get-state " .. ID .. ' "/"'
	local handle = io.popen(COMMAND)
	local result = handle:read("*a")
	if (result == "") then
		print("COMMAND: " .. COMMAND)
		return tonumber(sr.SR_ERR_INTERNAL)
	else
		snabb_state = result
	end
	handle:close()

	function oper_snabb_to_sysrepo()
		local oper_list = {}
		local parsed_data = yang.parse(snabb_state, nil)
		map_to_oper(parsed_data, "", oper_list)

		vals = val_holder:allocate(#oper_list)

		for i, oper in ipairs(oper_list) do
			vals:val(i-1):set(oper[1], tonumber(oper[2]), sr.SR_UINT64_T)
		end
		collectgarbage()
	end
	ok,res=pcall(oper_snabb_to_sysrepo) if not ok then print(res) end

	collectgarbage()
	return tonumber(sr.SR_ERR_OK)
end

-- Main client function.
function main()
	if (params[1] == nil and params[2] == nil) then
		print("Please enter first parameter, the yang model and the ID for second")
		return
	end
	YANG_MODEL = params[1]
	ID = params[2]

	action = snabb.new_ctx(YANG_MODEL, ID)
	if action == nil then print("can not find yang model in snabb"); os.exit(0) end

	-- load snabb startup data
	load_snabb_data(action)

    conn = sr.Connection("application")
    sess = sr.Session(conn, sr.SR_DS_RUNNING, sr.SR_SESS_DEFAULT)
    subscribe = sr.Subscribe(sess)

    wrap = sr.Callback_lua(module_change_cb)
    subscribe:module_change_subscribe(YANG_MODEL, wrap)

    print("========== STARTUP CONFIG APPLIED AS RUNNING ==========")

    wrap_oper = sr.Callback_lua(dp_get_items_cb)
    subscribe:dp_get_items_subscribe("/"..YANG_MODEL..":softwire-state", wrap_oper)

    print("========== SUBSCRIBE TO OPERATIONAL DATA ==========")
    -- infinite loop
    sr.global_loop()

    print("Application exit requested, exiting.")
    collectgarbage()
    os.exit(0)
end
ok,res=pcall(main) if not ok then print(res) end
