local params = {...}
local yang = require('parser')

sr = require("libsysrepoLua")

local YANG_MODEL = "snabb-softwire-v1"
local ID = ""

-- ################ debug functions ##########################
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

function get_key_value(s, xpath)
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

function contains(list, xpath)
    for key, value in pairs(list) do
        if string.ends(xpath, value) then return true end
    end
    return false
end

function send_to_sysrepo(sess_snabb, xpath, value)
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
    function set()
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
    -- this operation will fail for key values
    ok,res=pcall(set)
end

function map_to_xpath(s, path, sess_snabb)
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

    ok,res=pcall(clean)
    if not ok then
        print("\nError: ", res, "\nNo data in sysrepo datastore.", "\n")
    end
end

local function load_snabb_data()
    clean_startup_datastore()
    local conn_snabb = sr.Connection("application")
    local sess_snabb = sr.Session(conn_snabb, sr.SR_DS_STARTUP)

    local filePath = "/opt/fork/snabb/sysrepo/DT.conf"
    local fileContent = read_file(filePath)

    local parsed_data = yang.parse_file(filePath)
    map_to_xpath(parsed_data, "", sess_snabb)

    print("\n\n ========== COMMIT SNABB CONFIG DATA TO SYSREPO: ==========\n\n")
    sess_snabb:commit()
    collectgarbage()
end

-- return string value representation
function print_value(value)
   if (value:type() == sr.SR_CONTAINER_T) then
      return nil
   elseif (value:type() == sr.SR_CONTAINER_PRESENCE_T) then
      return nil
   elseif (value:type() == sr.SR_LIST_T) then
      return nil
   elseif (value:type() == sr.SR_STRING_T) then
      return value:data():get_string()
   elseif (value:type() == sr.SR_BOOL_T) then
         return tostring(value:data():get_bool())
   elseif (value:type() == sr.SR_INT8_T) then
      return tostring(value:data():get_int8())
   elseif (value:type() == sr.SR_INT16_T) then
      return tostring(value:data():get_int16())
   elseif (value:type() == sr.SR_INT32_T) then
      return tostring(value:data():get_int32())
   elseif (value:type() == sr.SR_INT64_T) then
      return tostring(value:data():get_int64())
   elseif (value:type() == sr.SR_UINT8_T) then
      return tostring(value:data():get_uint8())
   elseif (value:type() == sr.SR_UINT16_T) then
      return tostring(value:data():get_uint16())
   elseif (value:type() == sr.SR_UINT32_T) then
      return tostring(value:data():get_uint32())
   elseif (value:type() == sr.SR_UINT64_T) then
      return tostring(value:data():get_uint64())
   elseif (value:type() == sr.SR_IDENTITYREF_T) then
      return tostring(value:data():get_identityref())
   elseif (value:type() == sr.SR_BITS_T) then
      return tostring(value:data():get_bits())
   elseif (value:type() == sr.SR_BINARY_T) then
      return tostring(value:data():get_binary())
   else
      return nil
   end
end

-- Helper function for printing changes given operation, old and new value.
function print_change(op, old_val, new_val)
    -- prepare xpath
    -- remove "'" from key
    local xpath = new_val:xpath():gsub("'","")
    -- remove "'" from key
    xpath = new_val:xpath():gsub("'","")
    -- remove yang model from start
    xpath = "/" .. string.sub(xpath, string.len("/" .. YANG_MODEL .. ":") + 1)

    if (op == sr.SR_OP_DELETED) then
           io.write ("DELETED: ")
           io.write(old_val:to_string())
           --local COMMAND = "./snabb config remove " .. ID .. " " .. xpath .. " " .. print_value(new_val)
           --io.write("COMMAND: " .. COMMAND)
           --local handle = io.popen(COMMAND)
           --local result = handle:read("*a")
           --if (result ~= "") then
           --    print("ERROR message from snabb config.\nCOMMAND: " .. COMMAND)
           --    print("|" .. result .. "|")
           --end
           --handle:close()
    elseif (op == sr.SR_OP_MODIFIED or op == sr.SR_OP_CREATED) then
           io.write ("MODIFIED: ")
           io.write ("old value ")
           io.write(old_val:to_string())
           io.write ("new value ")
           io.write(new_val:to_string())
           --if (print_value(new_val) ~= nil) then
           --    local COMMAND = "./snabb config set " .. ID .. " " .. xpath .. " " .. print_value(new_val)
           --    io.write("COMMAND: " .. COMMAND .. "\n")
           --    local handle = io.popen(COMMAND)
           --    local result = handle:read("*a")
           --    if (result ~= "") then
           --        print("\nERROR message from snabb config.\nCOMMAND: " .. COMMAND)
           --        print("|" .. result .. "|")
           --    end
           --    handle:close()
           --end
    elseif (op == sr.SR_OP_MOVED) then
        -- TODO
        io.write ("MOVED: " .. new_val:xpath() .. " after " .. old_val:xpath() .. "\n")
    end
end

-- Function to print current configuration state.
-- It does so by loading all the items of a session and printing them out.
function print_current_config(sess, module_name)

    function run()
        xpath = "/" .. module_name .. ":*//*"
        values = sess:get_items(xpath)

	if (values == nil) then return end

	for i=0, values:val_cnt() - 1, 1 do
            io.write(values:val(i):to_string())
	end
    end

    ok,res=pcall(run)
    if not ok then
        print("\nerror: ",res, "\n")
    end

end

-- Function to be called for subscribed client of given session whenever configuration changes.
function module_change_cb(sess, module_name, event, private_ctx)
    print("\n\n ========== CONFIG HAS CHANGED, CURRENT RUNNING CONFIG: ==========\n\n")

    function run()
        -- print_current_config(sess, module_name)

        print("\n\n ========== CONFIG HAS CHANGED, CURRENT RUNNING CONFIG: ==========\n\n")

        print("\n\n ========== CHANGES: =============================================\n\n")

        change_path = "/" .. module_name .. ":*"

        it = sess:get_changes_iter(change_path)

        while true do
            change = sess:get_change_next(it)
            if (change == nil) then break end
            print_change(change:oper(), change:old_val(), change:new_val())
	end

	print("\n\n ========== END OF CHANGES =======================================\n\n")

        collectgarbage()
    end

    ok,res=pcall(run)
    if not ok then
        print("\nerror: ",res, "\n")
    end
    return tonumber(sr.SR_ERR_OK)
end

-- Main client function.
function run()
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
    subscribe:module_change_subscribe(YANG_MODEL, wrap, nil, 0, sr.SR_SUBSCR_APPLY_ONLY)

    print("\n\n ========== STARTUP CONFIG APPLIED AS RUNNING ==========\n\n")

    -- infinite loop
    sr.global_loop()

    print("Clean startup datastore.\n\n")
    clean_startup_datastore()

    print("Application exit requested, exiting.\n\n")
    return
end

ok,res=pcall(run)
if not ok then
    print("\nerror: ",res, "\n")
end
