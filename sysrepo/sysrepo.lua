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

local YANG_MODEL = nil
local ID = nil

function string.ends(String,End)
   return End=='' or string.sub(String,-string.len(End))==End
end

function string.compare(First, Second)
    if (First == nil or Second == nil) then return nil end
    local match = 0
    for i = 1, string.len(First) do
        if (i > string.len(Second)) then break end
        if (string.sub(First,i,i) ~= string.sub(Second,i,i)) then break end
	match = i
    end
    return string.sub(First,1,match)
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

local function send_to_sysrepo(sess_snabb, xpath, value)
    -- sysrepo expects format "/yang-model:container/..
    xpath = "/"..YANG_MODEL..":" .. string.sub(xpath, 2)
    local function set()
        sess_snabb:set_item_str(xpath, value)
    end
    ok,res=pcall(set)
    if not ok then
        -- set_item_str will fail for key elements
        -- print(res)
    end
end

local function map_to_xpath(s, path, sess_snabb)
    local ts = type(s)
    if (ts ~= "table") then
        send_to_sysrepo(sess_snabb, path, s)
    return end
    for k,v in pairs(s) do
	if (k == "keyword") then
	elseif (k == "keyword" or k == "loc" or type(k) == "number") then
            map_to_xpath(v, path, sess_snabb)
	elseif (k == "statements") then
            local xpath = path.."/"..tostring(s["keyword"])
            map_to_xpath(v, xpath..get_key_value(s, xpath), sess_snabb)
	elseif (k == "argument") then
            local xpath = path.."/"..tostring(s["keyword"])
            map_to_xpath(v, xpath..get_key_value(s, xpath), sess_snabb)
	else
            local xpath = path.."/"..tostring(s["keyword"])
            map_to_xpath(v, xpath..get_key_value(s, xpath), sess_snabb)
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

local function load_snabb_data()
    local datastore_empty = false

    local function sysrepo_call()
        local conn = sr.Connection("application")
        local sess = sr.Session(conn, sr.SR_DS_STARTUP, sr.SR_SESS_DEFAULT, "netconf")
        local values = nil
        local xpath = "/" .. YANG_MODEL .. ":*//*"
        values = sess:get_items(xpath)

	if (values == nil) then
            datastore_empty = true
        else
            datastore_empty = false
	end
    end
    ok,res=pcall(sysrepo_call) if not ok then datastore_empty = true end

    if datastore_empty then
        local conn_snabb = sr.Connection("application")
        local sess_snabb = sr.Session(conn_snabb, sr.SR_DS_STARTUP, sr.SR_SESS_DEFAULT, "netconf")

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
            map_to_xpath(parsed_data, "", sess_snabb)

            print("========== COMMIT SNABB CONFIG DATA TO SYSREPO: ==========")
            sess_snabb:commit()
            collectgarbage()
        end
        ok,res=pcall(sysrepo_call) if not ok then datastore_empty = true end
    else
        local conn_snabb = sr.Connection("application")
        local sess_snabb = sr.Session(conn_snabb, sr.SR_DS_STARTUP, sr.SR_SESS_DEFAULT, "netconf")

	local binding_table_xpath = "/"..YANG_MODEL..":softwire-config/binding-table"
        local action_list = snabb.new_action(YANG_MODEL, ID)
        action_list:set(binding_table_xpath, YANG_MODEL, ID, 2, sess_snabb)

        if action_list[1] ~= nil then
            local status = action_list[1]:send()
        end

        local ex_interface_xpath = "/"..YANG_MODEL..":softwire-config/external-interface/"
        local action_list = snabb.new_action(YANG_MODEL, ID)
        action_list:set(ex_interface_xpath, YANG_MODEL, ID, 2, sess_snabb)

        if action_list[1] ~= nil then
            local status = action_list[1]:send()
        end

        local in_interface_xpath = "/"..YANG_MODEL..":softwire-config/internal-interface/"
        local action_list = snabb.new_action(YANG_MODEL, ID)
        action_list:set(in_interface_xpath, YANG_MODEL, ID, 2, sess_snabb)

        if action_list[1] ~= nil then
            local status = action_list[1]:send()
        end
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
            local start_sess = sr.Session(start_conn, sr.SR_DS_STARTUP, sr.SR_SESS_DEFAULT, "netconf")
            start_sess:copy_config(YANG_MODEL, sr.SR_DS_RUNNING, sr.SR_DS_STARTUP)
            start_sess:commit()
        end
        ok,res=pcall(update_startup_datastore) if not ok then print(res) end

        return tonumber(sr.SR_ERR_OK)
    end

    local action_list = {}
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
		    local change = string.compare(old:xpath(), acc.xpath)
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
		    local change = string.compare(new:xpath(), acc.xpath)
		    acc.xpath = change
	        end
            end
	end
    end
    ok,res=pcall(sysrepo_call) if not ok then print(res) end

    local list_xpath = "/"..YANG_MODEL..":softwire-config/binding-table"
    if (list_xpath == string.compare(list_xpath, acc.xpath) and #acc.xpath > #list_xpath) then
        if not string.ends(acc.xpath, "/br-address") then
            acc.xpath = list_xpath
        end
	acc.action = "set"
    end

    local action_list = snabb.new_action(YANG_MODEL, ID)
    if acc.action == "remove" then
        action_list:delete(acc.xpath, YANG_MODEL, ID, acc.count, sess)
    elseif acc.action == "set" then
        action_list:set(acc.xpath, YANG_MODEL, ID, acc.count, sess)
    end

    if action_list[1] ~= nil then
        local status = action_list[1]:send()
        if not status then
            collectgarbage()
            return tonumber(sr.SR_ERR_INTERNAL)
        end
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

    -- load snabb startup data
    load_snabb_data()

    conn = sr.Connection("application")
    sess = sr.Session(conn, sr.SR_DS_RUNNING, sr.SR_SESS_DEFAULT, "netconf")
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
    os.exit(0)
end
ok,res=pcall(main) if not ok then print(res) end
