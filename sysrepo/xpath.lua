module(..., package.seeall)

local sr = require("libsysrepoLua")

-- find common xpath path with key values
function xpath_compare(First, Second, yang_model)
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

      if (node1 == nil or node2 == nil) then
         break
      end

      if (node1 == node2) then common = common.."/"..node1 end

      local keys = ""
      local mismatch = false
      while true do
         local key1 = ctx1:next_key_name(nil)
         if not key1 then
            break
         end
         if key1 then
            local key_value1 = ctx1:node_key_value(nil, key1)
            local key_value2 = ctx2:node_key_value(nil, key1)
            if key_value1 == key_value2 then
               keys = keys.."["..key1.."='"..key_value1.."']"
            else
               mismatch = true
               break
            end
         end
      end

      if mismatch then
         break
      else
         common = common..keys
      end

   end

   common = "/"..yang_model..":"..string.sub(common, 2)
   return common
end

-- skip node if the leaf is key that is in the xpath
function is_key(xpath)
   local ctx = sr.Xpath_Ctx()

   local node = ctx:next_node(xpath)
   if node == nil then
      return false
   end
   local id = 0
   local last_node
   while true do
      last_node = node
      node = ctx:next_node(nil)
      if node == nil then
         break
      end
      id = id + 1
   end

   if id < 1 then
      return true
   end

   local _ = ctx:node_idx(xpath, id - 1)

   while true do
      local key =  ctx:next_key_name(nil)
      if key == nil then
         break
      end
      if last_node == key then
         return true
      end
   end
   return false
end

-- skip node if the leaf is key that is in the xpath
function remove_last_key(xpath)
   local ctx = sr.Xpath_Ctx()
   local new_path = ""

   local node = ctx:next_node(xpath)
   if node == nil then
      return false
   end

   while true do
      if new_path == "" then
      --TODO create generic use case
         new_path = new_path.."/snabb-softwire-v1:"..node
      else
         new_path = new_path.."/"..node
      end
      local leaf = ""
      while true do
         local key =  ctx:next_key_name(nil)
         local value =  ctx:next_key_value(nil)
         if key == nil then
            break
         end
         leaf = leaf.."['"..key.."="..value.."']"
      end
      node = ctx:next_node(nil)
      if node == nil then
         break
      end
      new_path = new_path..leaf
   end

   return new_path
end
