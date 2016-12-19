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

function string.starts(String,Start)
   return string.sub(String,1,string.len(Start))==Start
end
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

function string.compare_xpath(First, Second)
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

local yang_string = {"/ip", "/addr", "/end-addr", "/br-address", "/b4-ipv6", "/ingress-filter", "/egress-filter", "/mac"}
local yang_uint8 = {"/psid-length", "/shift", "/reserved-ports-bit-count"}
local yang_uint16 = {"/psid", "/padding", "/vlan-tag", "/mtu"}
local yang_uint32 = {"/period", "/max-fragments-per-packet", "/max-packets", "/br", "/packets"}
local yang_bool = {"/allow-incoming-icmp", "/generate-icmp-errors", "/hairpinning"}
local yang_keys = {"/psid", "/addr"}

local function contains(list, xpath)
    for key, value in pairs(list) do
        if string.ends(xpath, value) then return true end
    end
    return false
end

local function send_to_sysrepo(sess_snabb, xpath, value)
    -- sysrepo expects format "/yang-model:container/..
    xpath = "/snabb-softwire-v1:" .. string.sub(xpath, 2)
    local function set()
        if contains(yang_keys, xpath) then
            -- skip yang keys, will generate sysrepo logs
        elseif contains(yang_string, xpath) then
            local val = sr.Val(value, sr.SR_STRING_T)
            sess_snabb:set_item(xpath, val)
        elseif contains(yang_uint8, xpath) then
            local val = sr.Val(tonumber(value), sr.SR_UINT8_T)
            sess_snabb:set_item(xpath, val)
        elseif contains(yang_uint16, xpath) then
            local val = sr.Val(tonumber(value), sr.SR_UINT16_T)
            sess_snabb:set_item(xpath, val)
        elseif contains(yang_uint32, xpath) then
            local val = sr.Val(tonumber(value), sr.SR_UINT32_T)
            sess_snabb:set_item(xpath, val)
        elseif contains(yang_bool, xpath) then
           if (value == "true") then
               local val = sr.Val(true, sr.SR_BOOL_T)
               sess_snabb:set_item(xpath, val)
           elseif (value == "false") then
               local val = sr.Val(false, sr.SR_BOOL_T)
               sess_snabb:set_item(xpath, val)
           end
        end
    end
    ok,res=pcall(set) if not ok then print(res) end
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

local function load_snabb_data()
    local datastore_empty = false

    local function sysrepo_call()
        local conn = sr.Connection("application")
        local sess = sr.Session(conn, sr.SR_DS_STARTUP)
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
        local sess_snabb = sr.Session(conn_snabb, sr.SR_DS_STARTUP)

        local content
        local COMMAND = path.."../src/snabb config get " .. ID .. ' "/"'
        local handle = io.popen(COMMAND)
        local result = handle:read("*a")
        if (result == "") then
            print("COMMAND: " .. COMMAND)
            print("\nERROR message from snabb config.\nCOMMAND: " .. COMMAND)
            print("|" .. result .. "|")
        else
            content = result
        end
        handle:close()

        local parsed_data = yang.parse(content, nil)
        map_to_xpath(parsed_data, "", sess_snabb)

        print("========== COMMIT SNABB CONFIG DATA TO SYSREPO: ==========")
        sess_snabb:commit()
        collectgarbage()
    else
        local binding_table_xpath = "/snabb-softwire-v1:softwire-config/binding-table"
        local action_list = snabb.new_action(YANG_MODEL, ID)
        action_list:set(binding_table_xpath, YANG_MODEL, ID, 2, sr.SR_DS_STARTUP)

        if action_list[1] ~= nil then
            local status = action_list[1]:send()
        end

        local ex_interface_xpath = "/snabb-softwire-v1:softwire-config/external-interface/"
        local action_list = snabb.new_action(YANG_MODEL, ID)
        action_list:set(ex_interface_xpath, YANG_MODEL, ID, 2, sr.SR_DS_STARTUP)

        if action_list[1] ~= nil then
            local status = action_list[1]:send()
        end

        local in_interface_xpath = "/snabb-softwire-v1:softwire-config/internal-interface/"
        local action_list = snabb.new_action(YANG_MODEL, ID)
        action_list:set(in_interface_xpath, YANG_MODEL, ID, 2, sr.SR_DS_STARTUP)

        if action_list[1] ~= nil then
            local status = action_list[1]:send()
        end
        print("========== COMMIT SYSREPO CONFIG DATA TO SNABB: ==========")
        collectgarbage()
    end
end

-- Function to print current configuration state.
-- It does so by loading all the items of a session and printing them out.
local function print_current_config(sess, module_name)

    local function sysrepo_call()
        xpath = "/" .. module_name .. ":*//*"
        values = sess:get_items(xpath)

	if (values == nil) then return end
	for i=0, values:val_cnt() - 1, 1 do
            io.write(values:val(i):to_string())
	end
    end
    ok,res=pcall(sysrepo_call) if not ok then print(res) end
end

-- Function to be called for subscribed client of given session whenever configuration changes.
function module_change_cb(sess, module_name, event, private_ctx)
    if (event ~= sr.SR_EV_APPLY) then return tonumber(sr.SR_ERR_OK) end

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

    -- commit changes to startup datastore
    local function update_startup_datastore()
        local start_conn = sr.Connection("application")
        local start_sess = sr.Session(start_conn, sr.SR_DS_STARTUP)
        start_sess:copy_config(YANG_MODEL, sr.SR_DS_RUNNING, sr.SR_DS_STARTUP)
        start_sess:commit()
    end
    ok,res=pcall(update_startup_datastore) if not ok then print(res) end


    local list_xpath = "/snabb-softwire-v1:softwire-config/binding-table"
    if (list_xpath == string.compare(list_xpath, acc.xpath) and #acc.xpath > #list_xpath) then
        if not string.ends(acc.xpath, "/br-address") then
            acc.xpath = list_xpath
        end
	acc.action = "set"
    end

    local action_list = snabb.new_action(YANG_MODEL, ID)
    if acc.action == "remove" then
        action_list:delete(acc.xpath, YANG_MODEL, ID, acc.count, sr.SR_DS_RUNNING)
    elseif acc.action == "set" then
        action_list:set(acc.xpath, YANG_MODEL, ID, acc.count, sr.SR_DS_RUNNING)
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

    -- infinite loop
    sr.global_loop()

    print("Application exit requested, exiting.")
    os.exit(0)
end
ok,res=pcall(main) if not ok then print(res) end
