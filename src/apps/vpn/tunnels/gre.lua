local gre = require("lib.protocol.gre")

local tunnel = subClass(nil)
tunnel.proto = 47
tunnel.class = gre

function tunnel:new (conf, use_cc)
   local o = tunnel:superClass().new(self)
   o.conf = conf
   -- 0x6558 is the protocol number assigned to "Transparent Ethernet Bridging"
   o.header = gre:new({ protocol = 0x6558,
			checksum = conf.checksum,
			key = conf.key })
   if conf.key ~= nil then
      -- Set key as inbound and outbound "VC Label" in MIB
      o.OutboundVcLabel = conf.key
      o.InboundVcLabel = conf.key
   end
   if use_cc then
      assert(conf.key == nil or conf.key ~= 0xFFFFFFFE,
	     "Key 0xFFFFFFFE is reserved for the control channel")
      o.cc_header = gre:new({ protocol = 0x6558,
			      checksum = nil,
			      key = 0xFFFFFFFE })
   end
   return o
end

function tunnel:encapsulate (datagram)
   if self.header:checksum() then
      self.header:checksum(datagram:payload())
   end
end

-- Return values status, code
-- status 
--   true
--     proper VPN packet, code irrelevant
--   false
--     code
--       0 decap error -> increase error counter
--       1 control-channel packet
function tunnel:decapsulate (datagram)
   local code = 0
   local gre = datagram:parse()
   if gre then
      if not gre:checksum_check(datagram:payload()) then
	 print("Bad GRE checksum")
      else
	 local key = gre:key()
	 if ((self.conf.key and key and key == self.conf.key) or
	  not (self.conf.key or key)) then
	    datagram:pop(1)
	    return true
	 else
	    if key == 0xFFFFFFFE then
	       code = 1
	    else
	       print("GRE key mismatch: local "
		     ..(self.conf.key or 'none')
		  ..", remote "..(gre:key() or 'none'))
	    end
	 end
      end
   end
   return false, code
end

return tunnel
