module(..., package.seeall)

local sr = require("libsysrepoLua")

local path = nil
if arg and arg[0] then
    path = arg[0]:match("(.-)[^\\/]+$") .. ""
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

local Action = {yang_model = nil, id = nil}
Action.__index = table

function new_action(yang_model, id)
    setmetatable({}, Action)
    Action.yang_model = yang_model
    Action.id = id
    return Action
end

local Snabb = {action = nil, xpath = nil, value = nil, id=nil, yang=nil}

local function format(sysrepo_xpath, yang_model)
    local xpath = nil
    -- remove yang model from start
    xpath = "/" .. string.sub(sysrepo_xpath, string.len("/" .. yang_model .. ":") + 1)
    -- remove ' from key
    xpath = xpath:gsub("='","=")
    xpath = xpath:gsub("']","]")
    return xpath
end

-- Used to initialize Animal objects
function new(action, xpath, value, id, yang)
    setmetatable({}, Snabb)
    -- Self is a reference to values for this Animal
    Snabb.action = action
    Snabb.xpath = format(xpath, yang)
    Snabb.value = value
    Snabb.id = id
    Snabb.yang = yang
    return Snabb
end

function Snabb:send()
    local COMMAND = path .. "../src/snabb config "..self.action.." "..self.id.." "..self.xpath
    if self.action == "set" then
        COMMAND = COMMAND.." '"..tostring(self.value .. "'")
    end
    local handle = io.popen(COMMAND)
    local result = handle:read("*a")
    --print("COMMAND -> " .. COMMAND)
    if (result ~= "") then
        handle:close()
        print("ERROR:"..result)
        return false
    end
    handle:close()
    return true
end


local function fill_br_address(xpath, yang_model, id)
    local br_address = ""
    local conn_snabb = sr.Connection("application")
    local sess_snabb = sr.Session(conn_snabb, sr.SR_DS_RUNNING)

    local function sysrepo_call()
       local values = sess_snabb:get_items(xpath)
       if values == nil then return end
       for i = 0, values:val_cnt() -1, 1 do
           br_address = br_address .. " " .. print_value(values:val(i))
       end
    end
    ok,res=pcall(sysrepo_call) if not ok then print(res); return nil end

    collectgarbage()
    return snabb.new("set", xpath, br_address, id, yang_model)
end

local function print_trees(trees, xpath)
    local result = ""

    local function sub_tree_length(tree)
        local count = 0
        if (tree == nil) then return count end
        while true do
            count = count + 1
            tree = tree:next()
            if tree == nil then break end
        end
        return count
    end

    if string.ends(xpath, "]") then result = result .. "{" end
    local count = 0
    for i = 0, trees:tree_cnt() -1, 1 do
        local tree = trees:tree(i)
        if count > 0 then
            count = count - 1
            if (count == 0) then result = result .. "}"; count = count - 1 end
        end
        if trees:tree_cnt() == 1 then return print_value(trees:tre(i)) end
        if (print_value(tree) ~= nil) then
            result = result .. " " .. tree:name() .." " .. print_value(tree) .. ";"
        else
            count = sub_tree_length(tree:first_child()) + 1
            result = result .. " " .. tree:name() .." {"
        end
    end
    if string.ends(xpath, "]") then result = result .. "}" end

    return result
end

local function fill_subtrees(yang_model, id, xpath, action, count)
    local result = ""
    local conn_snabb = sr.Connection("application")
    local sess_snabb = sr.Session(conn_snabb, sr.SR_DS_RUNNING)

    if (xpath == "/snabb-softwire-v1:softwire-config/binding-table/br-address") then
        return fill_br_address(xpath, yang_model, id)
    end

    if action == "remove" then return snabb.new(action, xpath, result, id, yang_model) end

    local session_xpath = xpath
    if count > 1 then session_xpath = session_xpath .. "/*" end

    local function sysrepo_call()
	    --todo check if not end leaf
        local trees = sess_snabb:get_subtrees(session_xpath)
        if trees == nil then return end
        if trees:tree_cnt() == 1 and count == 1 then result = print_value(trees:tree(0)); return; end
        result = print_trees(trees, xpath)
    end
    ok,res=pcall(sysrepo_call) if not ok then print(res); return nil end

    collectgarbage()
    return snabb.new(action, xpath, result, id, yang_model)
end

function Action:set(xpath, yang_model, id, count)
    table.insert(self, fill_subtrees(self.yang_model, self.id, xpath, "set", count))
end

function Action:delete(xpath, yang_model, id, count)
    table.insert(self, fill_subtrees(self.yang_model, self.id, xpath, "remove", count))
end

