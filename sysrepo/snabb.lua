module(..., package.seeall)

local sr = require("libsysrepoLua")

local require_rel
local path = ""
if arg and arg[0] then
    package.path = arg[0]:match("(.-)[^\\/]+$") .. "?.lua;" .. package.path
    require_rel = require
    path = arg[0]:match("(.-)[^\\/]+$") .. ""
end

local schema = require_rel('schema')
local path = ""
if arg and arg[0] then
    path = arg[0]:match("(.-)[^\\/]+$") .. ""
end

function string.ends(String,End)
   return End=='' or string.sub(String,-string.len(End))==End
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

local Action = {yang_model = nil, id = nil, yang_schema = nil}
Action.__index = table

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

-- Used to initialize Snabb objects
function new(action, xpath, value, id, yang)
    local Snabb = {}
    -- Self is a reference to values for this Animal
    Snabb.action = action
    Snabb.xpath = format(xpath, yang)
    Snabb.value = value
    Snabb.id = id
    Snabb.yang = yang
    return Snabb
end

local function send(Snabb)
    local COMMAND = path .. "../src/snabb config "..Snabb.action.." "..Snabb.id.." "..Snabb.xpath
    if Snabb.action == "set" then
        if Snabb.value == nil then
            return false
        end
        COMMAND = COMMAND.." '"..tostring(Snabb.value) .. "'"
    end
    local handle = io.popen(COMMAND)
    local result = handle:read("*a")
    if (result ~= "") then
        handle:close()
        print("COMMAND -> " .. COMMAND)
        print("ERROR:"..result)
        return false
    end
    handle:close()
    return true
end

local function print_trees(trees, xpath, yang_schema)
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

    local function print_list(tree)
        local result = ""
        if (tree == nil) then return count end
        while true do
            if tree == nil then break
            elseif tree:type() == sr.SR_LIST_T or tree:type() == sr.SR_CONTAINER_T or tree:type() == sr.SR_CONTAINER_PRESENCE_T then
                result = result.." "..tree:name().." { "..print_list(tree:first_child()).."}"
            else
                result = result .. " " .. tree:name() .. " " .. print_value(tree) .. ";"
            end
            tree = tree:next()
        end
        return result
    end

    local yang_type = yang_schema:get_type(xpath)
    if yang_type == "list" or yang_type == "grouping" then result = result .. "{" end

    for i = 0, trees:tree_cnt() -1, 1 do
        local tree = trees:tree(i)
        if trees:tree_cnt() == 1 then return print_value(trees:tree(i)) end
        if (print_value(tree) ~= nil) then
            result = result .. " " .. tree:name() .." " .. print_value(tree) .. ";"
        elseif tree:type() == sr.SR_LIST_T or tree:type() == sr.SR_CONTAINER_T or tree:type() == sr.SR_CONTAINER_PRESENCE_T then
            result = result.." "..tree:name().." { "..print_list(tree:first_child()).."}"
        else
            result = result .. " " .. tree:name() ..""
        end
    end
    if yang_type == "list" or yang_type == "grouping" then result = result .. "}" end

    return result
end

local function fill_subtrees(yang_model, id, yang_schema, xpath, action, sess)
    local result = ""

    --TODO skip problem in snabb of setting a leaf-list directly
    if (xpath == "/snabb-softwire-v1:softwire-config/binding-table/br-address") then
        xpath = "/snabb-softwire-v1:softwire-config/binding-table"
    end

    if action == "remove" then return snabb.new(action, xpath, result, id, yang_model) end

    local session_xpath = xpath
    local yang_type = yang_schema:get_type(xpath)
    if yang_type == "container" or yang_type == "list" then session_xpath = session_xpath .. "/*" end

    local function sysrepo_call()
	    --todo check if not end leaf
        local trees = sess:get_subtrees(session_xpath)
        if trees == nil then return end
        if trees:tree_cnt() == 1 and trees:tree(0):first_child() == nil then result = print_value(trees:tree(0)); return; end
        result = print_trees(trees, xpath, yang_schema)
    end
    ok,res=pcall(sysrepo_call) if not ok then print(res); return nil end

    collectgarbage()
    return snabb.new(action, xpath, result, id, yang_model)
end

function Action:set(xpath, sess)
    local data = fill_subtrees(self.yang_model, self.id, self.yang_schema, xpath, "set", sess)
    self.action_list[#self.action_list + 1] = data
end

function Action:delete(xpath, sess)
    local data = fill_subtrees(self.yang_model, self.id, self.yang_schema, xpath, "remove", sess)
    self.action_list[#self.action_list + 1] = data
end

function Action:run()
    for i=#self.action_list,1,-1 do
        local sucess = send(self.action_list[i])
        if not sucess then
            self.failed_list[#self.failed_list + 1] = self.action_list[i]
        end
        table.remove(self.action_list, i)
    end
end

function new_ctx(yang_model, id)
    setmetatable({}, Action)
    Action.yang_model = yang_model
    Action.id = id
    Action.action_list = {}
    Action.failed_list = {}

    local yang_schema = schema.new_schema_ctx(yang_model)
    if yang_schema == nil then return nil end

    Action.yang_schema = yang_schema
    return Action
end
