module(..., package.seeall)

local require_rel
local path = ""
if arg and arg[0] then
    package.path = arg[0]:match("(.-)[^\\/]+$") .. "?.lua;" .. package.path
    require_rel = require
    path = arg[0]:match("(.-)[^\\/]+$") .. ""
end

local params = {...}
local yang = require_rel('parser')
local sr = require("libsysrepoLua")

local Yang = {schema = nil}

function Yang:get_type(xpath)
    if xpath == nil or self.schema == nil then return nil end

    local function xpath_to_list(xpath)
        local xpath_ctx = sr.Xpath_Ctx()
        if xpath_ctx == nil then return nil end

        local xpath_list = {}
        local node = xpath_ctx:next_node(xpath)
        if node == nil then return nil end
        local i = 1
        xpath_list[i] = node
        while true do
            i = i + 1
            xpath_list[i] = xpath_ctx:next_node(nil)
            if xpath_list[i] == nil then break end
        end
        return xpath_list
    end
    local xpath_list = xpath_to_list(xpath)

    local function get_type(s, list, pos)
        local ret = nil
        local function get_schema_type(s, list, pos)
            local ts = type(s)
            if (ts ~= "table") then
                return s
            end

            for k,v in pairs(s) do
                if (k == "keyword") then
                elseif (k == "argument") then
                    if list[pos] == v then
            	    pos = pos + 1
            	    if list[pos] == nil then ret = s["keyword"] end
                        get_schema_type(s["statements"], list, pos)
                    else
                        get_schema_type(v, list, pos)
                    end
                end
                get_schema_type(v, list, pos)
            end
        end
        get_schema_type(s, list, pos)
        return ret
    end
    return get_type(self.schema, xpath_list, 1)
end

function new_schema_ctx(yang_model)
    setmetatable({}, Yang)
    local yang_path = path.."../src/lib/yang/"..yang_model..".yang"
    local parsed_yang = yang.parse_file(yang_path)
    if parsed_yang == nil then return nil end
    Yang.schema = parsed_yang
    return Yang
end

