local require_rel
if arg and arg[0] then
    package.path = arg[0]:match("(.-)[^\\/]+$") .. "?.lua;" .. package.path
    require_rel = require
end

local params = {...}
local yang = require_rel('parser')
local snabb = require_rel('snabb')

local sr = require("libsysrepoLua")

local YANG_MODEL = nil
local ID = nil

-- ################ debug functions ##########################
local function print_r (t)
    local print_r_cache={}
    local function sub_print_r(t,indent)
        if (print_r_cache[tostring(t)]) then
            print(indent.."*"..tostring(t))
        else
            print_r_cache[tostring(t)]=true
            if (type(t)=="table") then
                for pos,val in pairs(t) do
                    if (type(val)=="table") then
                        print(indent.."["..pos.."] => "..tostring(t).." {")
                        sub_print_r(val,indent..string.rep(" ",string.len(pos)+8))
                        print(indent..string.rep(" ",string.len(pos)+6).."}")
                    elseif (type(val)=="string") then
                        print(indent.."["..pos..'] => "'..val..'"')
                    else
                        print(indent.."["..pos.."] => "..tostring(val))
                    end
                end
            else
                print(indent..tostring(t))
            end
        end
    end
    if (type(t)=="table") then
        print(tostring(t).." {")
        sub_print_r(t,"  ")
        print("}")
    else
        sub_print_r(t,"  ")
    end
    print()
end

local function read_file(path)
    local file = io.open(path, "rb") -- r read mode and b binary mode
    if not file then return nil end
    local content = file:read "*a" -- *a or *all reads the whole file
    file:close()
    return content
end
-- ################ debug functions ##########################

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
    if (xpath == "/binding-table/psid-map") then
        for k1,v1 in pairs(s) do if (type(v1) == "table") then for k,v in pairs(v1) do
            if (v["keyword"] == "addr") then
                keys = "[addr='"..v["argument"].."']"
            end
        end end end
    elseif (xpath == "/binding-table/softwire") then
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
    -- hack for missing "binding-table"
    -- replace 'internal-interface' with 'softwire-config/internal-interface'
    if ("/internal-interface" == string.sub(xpath, 1, string.len("/internal-interface"))) then
        xpath = "/softwire-config/internal-interface"..string.sub(xpath, string.len("/internal-interface") + 1)
    -- replace 'internal-exterface' with 'softwire-config/external-interface'
    elseif ("/external-interface" == string.sub(xpath, 1, string.len("/external-interface"))) then
        xpath = "/softwire-config/external-interface"..string.sub(xpath, string.len("/external-interface") + 1)
    end

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

local function clean_startup_datastore()
    local conn_snabb = sr.Connection("application")
    local sess_snabb = sr.Session(conn_snabb, sr.SR_DS_STARTUP)

    -- clean datastore
    function clean()
       sess_snabb:delete_item("/"..YANG_MODEL..":*")
       sess_snabb:commit()
    end
    ok,res=pcall(clean) if not ok then end
end

local function load_snabb_data()
    clean_startup_datastore()
    local conn_snabb = sr.Connection("application")
    local sess_snabb = sr.Session(conn_snabb, sr.SR_DS_STARTUP)

    -- local content
    -- local COMMAND = "../src/snabb config get " .. ID .. ' "/"'
    -- io.write("COMMAND: " .. COMMAND .. "\n")
    -- local handle = io.popen(COMMAND)
    -- local result = handle:read("*a")
    -- if (result == "") then
    --     print("\nERROR message from snabb config.\nCOMMAND: " .. COMMAND)
    --     print("|" .. result .. "|")
    -- else
    --     content = result
    -- end
    -- handle:close()

    local filePath = "/opt/fork/snabb/sysrepo/lwaftr.conf"
    local content = read_file(filePath)

    local parsed_data = yang.parse(content, nil)
    map_to_xpath(parsed_data, "", sess_snabb)

    print("========== COMMIT SNABB CONFIG DATA TO SYSREPO: ==========")
    sess_snabb:commit()
    collectgarbage()
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
    local  acc = {xpath = nil, action = nil, count = 0}

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
		    acc.action = "delete"
	        else
		    local change = string.compare(old:xpath(), acc.xpath)
		    if (change == old:xpath() and snabb.print_value(old) == nil and delete_all) then
                        acc.xpath = change
                        acc.action = "delete"
                    else
                        acc.xpath = change
                        acc.action = "set"
                    end
                end
	    elseif (op == sr.SR_OP_CREATED or op == sr.SR_OP_CREATED) then
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

    local list_xpath = "/snabb-softwire-v1:binding-table"
    if (list_xpath == string.compare(list_xpath, acc.xpath) and #acc.xpath > #list_xpath) then
        acc.xpath = list_xpath .. "/*"
	acc.action = "set"
    end

    local list_xpath = "/snabb-softwire-v1:softwire-config"
    if (list_xpath == string.compare(list_xpath, acc.xpath) and #acc.xpath > #list_xpath) then
        acc.xpath = list_xpath .."/*"
	acc.action = "set"
    end

print("xpath -> " .. acc.xpath)
    if acc.count > 1 then
        acc.xpath = acc.xpath .. ""
    end

    local action_list = snabb.new_action(YANG_MODEL, ID)
    if acc.action == "delete" then
        action_list:delete(acc.xpath)
    elseif acc.action == "set" then
        action_list:set(acc.xpath)
    end
    print_r(action_list)


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

    -- load snabb startup data
    load_snabb_data()

    conn = sr.Connection("application")
    sess = sr.Session(conn, sr.SR_DS_RUNNING)
    subscribe = sr.Subscribe(sess)
    wrap = sr.Callback_lua(module_change_cb)
    subscribe:module_change_subscribe(YANG_MODEL, wrap)

    print("========== STARTUP CONFIG APPLIED AS RUNNING ==========")

    -- infinite loop
    sr.global_loop()

    print("Clean startup datastore.")
    clean_startup_datastore()

    print("Application exit requested, exiting.")
    os.exit(0)
end
ok,res=pcall(main) if not ok then print(res) end
