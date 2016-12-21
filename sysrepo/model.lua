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

local Yang = {schema = nil}

function Yang:get_type(xpath)
    if xpath == nil or self.schema == nil then return nil end

    local xpath_ctx = sr.Xpath_Ctx()
    if xpath_ctx == nil then return nil end

    --local node = xpath_ctx:next_node(xpath)

    local function get_schema_type(s, x)
        local ts = type(s)
        if (ts ~= "table") then
            return s
        end
        for k,v in pairs(s) do
	    if (k == "keyword") then
	    elseif (k == "argument") then
                print("k -> " .. k .. "\nv -> " .. tostring(v) .. "\n")
		local name = x:next_node()
		if name ~= nil then
		    if v == name then print("MATCH ##########################") end
	        end
            end
	    get_schema_type(v, x)
        end
    end

    local schema = get_schema_type(self.schema, xpath_ctx)

    return nil
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


function parse(yang_model)
    setmetatable({}, Yang)
    local yang_path = path.."../src/lib/yang/"..yang_model..".yang"
    local parsed_yang = yang.parse_file(yang_path)
    Yang.schema = parsed_yang
    return Yang
end

local path = "/snabb-softwire-v1:softwire-config/external-interface"
local xpath = sr.Xpath_Ctx()

local yang_schema = parse("snabb-softwire-v1")
    print("PATH -> " .. path)
yang_schema:get_type(path)

