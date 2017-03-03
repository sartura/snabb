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
local xpath_lib = require_rel('xpath')

local sr = require("libsysrepoLua")

local action = nil

local YANG_MODEL = nil
local ID = nil

local function string_starts(String,Starts)
   return Starts=='' or string.sub(String,1,string.len(Starts))==Starts
end

local function get_key_value(s, xpath)
   local keys = ""
   if (xpath == "/softwire-config/binding-table/psid-map") then
      for _,v1 in pairs(s) do
			if (type(v1) == "table") then for _,v in pairs(v1) do
            if (v["keyword"] == "addr") then
               keys = "[addr='"..v["argument"].."']"
            end
         end
      end
	end
   elseif (xpath == "/softwire-config/binding-table/softwire") then
      local default_padding = nil
      for _,v1 in pairs(s) do
			if (type(v1) == "table") then for _,v in pairs(v1) do
            if (v["keyword"] == "ipv4") then
               keys = keys.."[ipv4='"..v["argument"].."']"
            end
         end
	   end
	end
      for _,v1 in pairs(s) do
			if (type(v1) == "table") then for _,v in pairs(v1) do
            if (v["keyword"] == "psid") then
               keys = keys.."[psid='"..v["argument"].."']"
            end
         end
	   end
   end
      for _,v1 in pairs(s) do
         if (type(v1) == "table") then
				for _,v in pairs(v1) do
               if (v["keyword"] == "padding") then
                  default_padding = v["argument"]
                  keys = keys.."[padding='"..v["argument"].."']"
               end
            end
	      end
	   end
      if (default_padding == nil) then
         keys = keys.."[padding='0']"
         --TODO add padding
      end
   end
   return keys
end

local function send_to_sysrepo(set_item_list, xpath, value)
   -- sysrepo expects format "/yang-model:container/..
   xpath = "/"..YANG_MODEL..":" .. string.sub(xpath, 2)

   local skip_node = xpath_lib.is_key(xpath)
   if not skip_node then
      if not string_starts(value, "<unknown>:") then
         table.insert(set_item_list, {xpath, value})
      end
   end
end

local function map_to_xpath(set_item_list, s, current_xpath)
   local ts = type(s)
   if (ts ~= "table") then
      send_to_sysrepo(set_item_list, current_xpath, s)
      return end
   for k,v in pairs(s) do
      if (k == "keyword" or k == "loc" or type(k) == "number") then
         map_to_xpath(set_item_list, v, current_xpath)
      elseif (k == "statements") then
         local xpath = current_xpath.."/"..tostring(s["keyword"])
         map_to_xpath(set_item_list, v, xpath..get_key_value(s, xpath))
      elseif (k == "argument") then
         local xpath = current_xpath.."/"..tostring(s["keyword"])
         map_to_xpath(set_item_list, v, xpath..get_key_value(s, xpath))
      else
         local xpath = current_xpath.."/"..tostring(s["keyword"])
         map_to_xpath(set_item_list, v, xpath..get_key_value(s, xpath))
      end
   end
   return
end

local function map_to_oper(s, current_xpath, oper_list)
   local ts = type(s)
   if (ts ~= "table") then
      local xpath = "/"..YANG_MODEL..":" .. string.sub(current_xpath, 2)
      oper_list[#oper_list + 1] = {xpath, s}
      return end
   for k,v in pairs(s) do
      if (k == "keyword" or k == "loc" or type(k) == "number") then
         map_to_oper(v, current_xpath, oper_list)
      elseif (k == "statements") then
         local xpath = current_xpath.."/"..tostring(s["keyword"])
         map_to_oper(v, xpath, oper_list)
      elseif (k == "argument") then
         local xpath = current_xpath.."/"..tostring(s["keyword"])
         map_to_oper(v, xpath, oper_list)
      else
         local xpath = current_xpath.."/"..tostring(s["keyword"])
         map_to_oper(v, xpath, oper_list)
      end
   end
   return
end

local function load_snabb_data(actions)
   local datastore_empty = false

   local function sysrepo_call()
      local conn = sr.Connection("application")
      local sess = sr.Session(conn, sr.SR_DS_STARTUP, sr.SR_SESS_DEFAULT)
      local xpath = "/" .. YANG_MODEL .. ":*//*"
      local values = sess:get_items(xpath)

      if (values == nil) then
         datastore_empty = true
      else
         datastore_empty = false
      end
      collectgarbage()
   end
   local ok=pcall(sysrepo_call)
	if not ok then
	   datastore_empty = true
	end

   if datastore_empty then
      local conn_snabb = sr.Connection("application")
      local sess_snabb = sr.Session(conn_snabb, sr.SR_DS_STARTUP, sr.SR_SESS_DEFAULT)

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

      local function sysrepo_call_commit()
         local parsed_data = yang.parse(content, nil)
         local set_item_list = {}
         map_to_xpath(set_item_list, parsed_data, "")
         -- set all items in the list
         for _, el in ipairs(set_item_list) do
            sess_snabb:set_item_str(el[1], el[2])
         end

         print("========== COMMIT SNABB CONFIG DATA TO SYSREPO: ==========")
         sess_snabb:commit()
         collectgarbage()
      end
      local ok_commit, res=pcall(sysrepo_call_commit)
		if not ok_commit then
		   print(res)
		end
   else
      local conn_snabb = sr.Connection("application")
      local sess_snabb = sr.Session(conn_snabb, sr.SR_DS_STARTUP, sr.SR_SESS_DEFAULT)

      local binding_table_xpath = "/"..YANG_MODEL..":softwire-config"
      actions:set(binding_table_xpath, sess_snabb)

      actions:run()

      print("========== COMMIT SYSREPO CONFIG DATA TO SNABB: ==========")
      collectgarbage()
   end
end

-- Function to be called for subscribed client of given session whenever configuration changes.
local function module_change_cb(sess, module_name, event, _)
   if (event == sr.SR_EV_APPLY) then
      -- commit changes to startup datastore
      local function update_startup_datastore()
         local start_conn = sr.Connection("application")
         local start_sess = sr.Session(start_conn, sr.SR_DS_STARTUP, sr.SR_SESS_DEFAULT)
         start_sess:copy_config(YANG_MODEL, sr.SR_DS_RUNNING, sr.SR_DS_STARTUP)
         start_sess:commit()
         collectgarbage()
      end
      local ok,res=pcall(update_startup_datastore)
		if not ok then
			print(res)
		end

      return tonumber(sr.SR_ERR_OK)
   end

   local delete_all = true
   local acc = {xpath = nil, action = nil, count = 0}

   local function sysrepo_call()
      local change_path = "/" .. module_name .. ":*"
      local it = sess:get_changes_iter(change_path)

      while true do
         local change = sess:get_change_next(it)
         if (change == nil) then
				break
			end
         acc.count = acc.count + 1
         if (change:oper() ~= sr.SR_OP_DELETED) then
			   delete_all = false
			end
         local op = change:oper()
         local new = change:new_val()
         local old = change:old_val()
         if (op == sr.SR_OP_DELETED) then
            if (acc.xpath == nil) then
               acc.xpath = old:xpath()
               acc.action = "remove"
            else
               local common_xpath = xpath_lib.xpath_compare(old:xpath(), acc.xpath, module_name)
               if (common_xpath == old:xpath() and snabb.print_value(old) == nil and delete_all) then
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
               acc.xpath = xpath_lib.xpath_compare(new:xpath(), acc.xpath, module_name)
            end
         end
      end
      collectgarbage()
   end
   local ok,res=pcall(sysrepo_call)
	if not ok then
	   print(res)
	end

   if acc.action == "remove" then
      action:delete(acc.xpath, sess)
   elseif acc.action == "set" then
      action:set(acc.xpath, sess)
   end

   collectgarbage()
   local action_failed = action:run()
   if action_failed then
      return tonumber(sr.SR_ERR_INTERNAL)
   end

   return tonumber(sr.SR_ERR_OK)
end

-- Function to be called for operational data
local function dp_get_items_cb(xpath, val_holder, _)
	--TODO
	--implement xpath
	print(xpath)
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

   local function oper_snabb_to_sysrepo()
      local oper_list = {}
      local parsed_data = yang.parse(snabb_state, nil)
      map_to_oper(parsed_data, "", oper_list)

      local vals = val_holder:allocate(#oper_list)

      for i, oper in ipairs(oper_list) do
         vals:val(i-1):set(oper[1], tonumber(oper[2]), sr.SR_UINT64_T)
      end
      collectgarbage()
   end
   local ok,res=pcall(oper_snabb_to_sysrepo)
	if not ok then
		print(res)
	end

   collectgarbage()
   return tonumber(sr.SR_ERR_OK)
end

-- Main client function.
local function main()
   if (params[1] == nil and params[2] == nil) then
      print("Please enter first parameter, the yang model and the ID for second")
      return
   end
   YANG_MODEL = params[1]
   ID = params[2]

   action = snabb.new_ctx(YANG_MODEL, ID)
   if action == nil then
	   print("can not find yang model in snabb")
	   os.exit(0)
	end

   -- load snabb startup data
   load_snabb_data(action)

   local conn = sr.Connection("application")
   local sess = sr.Session(conn, sr.SR_DS_RUNNING, sr.SR_SESS_DEFAULT)
   local subscribe = sr.Subscribe(sess)

   local wrap = sr.Callback_lua(module_change_cb)
   subscribe:module_change_subscribe(YANG_MODEL, wrap)

   print("========== STARTUP CONFIG APPLIED AS RUNNING ==========")

   local wrap_oper = sr.Callback_lua(dp_get_items_cb)
   subscribe:dp_get_items_subscribe("/"..YANG_MODEL..":softwire-state", wrap_oper)

   print("========== SUBSCRIBE TO OPERATIONAL DATA ==========")
   -- infinite loop
   sr.global_loop()

   print("Application exit requested, exiting.")
   collectgarbage()
   os.exit(0)
end
local ok,res=pcall(main)
if not ok then
	print(res)
end
