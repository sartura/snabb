local l2tpv3 = require("lib.protocol.keyed_ipv6_tunnel")

local tunnel = subClass(nil)
tunnel.proto = 115
tunnel.class = l2tpv3

function tunnel:new (conf, use_cc)
   local o = tunnel:superClass().new(self)
   o.conf = conf
   -- The spec for L2TPv3 over IPv6 recommends to set the session ID
   -- to 0xffffffff for the "static 1:1 mapping" scenario.
   conf.local_session = conf.local_session or 0xffffffff
   conf.remote_session = conf.remote_session or 0xffffffff
   conf.local_cookie_baked = l2tpv3:new_cookie(conf.local_cookie)
   conf.remote_cookie_baked = l2tpv3:new_cookie(conf.remote_cookie)
   o.header = l2tpv3:new({ session_id = conf.remote_session,
				cookie = conf.remote_cookie_baked })
   o.OutboundVcLabel = conf.local_session
   o.InboundVcLabel = conf.remote_session
   if use_cc then
      assert(conf.local_session ~= 0xFFFFFFFE and
	     conf.remote_session ~= 0xFFFFFFFE,
	  "Session ID 0xFFFFFFFE is reserved for the control channel")
      o.cc_header = l2tpv3:new({ session_id = 0xFFFFFFFE,
				      cookie = conf.remote_cookie_baked })
   end
   return o
end

function tunnel:encapsulate ()
end

function tunnel:decapsulate (datagram)
   local code = 0
   local l2tpv3 = datagram:parse()
   if l2tpv3 then
      local session_id = l2tpv3:session_id()
      if session_id == 0xFFFFFFFE then
	 code = 1
      elseif  session_id ~= self.conf.local_session then
	 print("session id mismatch: expected "
	       ..string.format("0x%08x", self.conf.local_session)
	    ..", received "..string.format("0x%08x", session_id))
      elseif l2tpv3:cookie() ~= self.conf.local_cookie_baked then
	 print("cookie mismatch, expected "
	       ..tostring(self.conf.local_cookie_baked)
	    ..", received "..tostring(l2tpv3:cookie()))
      else
	 datagram:pop(1)
	 return true
      end
   end
   return false, code
end

return tunnel
