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

-- Main client function.
function main()
    if (params[1] == nil) then
        print("Please enter file location for writeing the sysrepo config data")
        return
    end

    local file_path = params[1]

    local config_data = ""
    YANG_MODEL = "snabb-softwire-v1"
    ID = 1

    local binding_table_xpath = "/snabb-softwire-v1:softwire-config/binding-table"
    local action_list = snabb.new_action(YANG_MODEL, ID)
    action_list:set(binding_table_xpath, YANG_MODEL, ID, 2, sr.SR_DS_STARTUP)

    if action_list[1] ~= nil then
        config_data = config_data .. "binding-table { " .. action_list[1]:print() .. " }\n"
    end

    local ex_interface_xpath = "/snabb-softwire-v1:softwire-config/external-interface/"
    local action_list = snabb.new_action(YANG_MODEL, ID)
    action_list:set(ex_interface_xpath, YANG_MODEL, ID, 2, sr.SR_DS_STARTUP)

    if action_list[1] ~= nil then
        config_data = config_data .. "external-interface { ".. action_list[1]:print() .. " }\n"
    end

    local in_interface_xpath = "/snabb-softwire-v1:softwire-config/internal-interface/"
    local action_list = snabb.new_action(YANG_MODEL, ID)
    action_list:set(in_interface_xpath, YANG_MODEL, ID, 2, sr.SR_DS_STARTUP)

    if action_list[1] ~= nil then
        config_data = config_data .. "internal-interface { ".. action_list[1]:print() .. " }\n"
    end

    config_data = "softwire-config { " ..config_data .. " }\n"

    file = io.open(file_path, "w")
    io.output(file)
    io.write(config_data)
    io.close(file)

    collectgarbage()
end
ok,res=pcall(main) if not ok then print(res) end
