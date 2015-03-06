-- This program provisions a complete endpoint for one or more L2 VPNs
-- that share a common uplink port to the backbone network.
--
-- Each VPN provides essentially a multi-point L2 VPN over IPv6,
-- a.k.a. Virtual Private LAN Service (VPLS). A point-to-point VPN,
-- a.k.a. Virtual Private Wire Service (VPWS) is provided as a
-- degenerate case of a VPLS with exactly two endpoints (i.e. a single
-- pseudowire).  The general framework is described in RFC4664.
--
-- A VPN endpoint is defined by the following elements.
--
--   A physical uplink interface defined by
--      driver module
--      driver configuration
--      local IPv6 address
--      local MAC address
--      optional MAC address of neighbor
--      optional selection of dynamic ND for neighbor
--      IPv6 address of the next-hop for a virtual default route
--   A set of VPLS instances defined by
--      VC ID
--      optional descriptive text
--      an IPv6 address (local endpoint of all associated pseudowires)
--      bridge type (either "flooding" or "learning", defaults to "flooding")
--      MTU
--      optional default tunnel configuration
--      optional default control-channel configuration
--      a set of attachment circuits defined by
--         driver module
--         driver configuration
--         interface name
--      a set of pseudowires defined by
--         IPv6 address of the remote endpoint
--         optional tunnel configuration
--         optional control-channel configuration
--
-- The module constructs a network of apps from such a specification
-- as follows.
--
-- The uplink interface is either connected to an instance of
-- apps.ipv6.nd_light, apps.ipv6.ns_responder or directly to
-- apps.ipv6.dispatch, depending on the desired level of dynamic IPv6
-- neighbor discovery.  If the MAC address of the neighbor is not
-- configured, dynamic ND is enabled for both sides using the nd_light
-- app.  If the MAC address of the neighbor is configured, no local ND
-- takes places.  In this case, an additional flag (called
-- "neighbor_nd") is examined.  If it is set, ND for the neighbor is
-- enabled through the ns_responder app.  If the flag is not set, it
-- is assumed that the remote side uses a static neighbor cache and
-- neither side performs dynamic ND.  In this case, the uplink
-- interface is directly attached to the IPv6 dispatch app.
--
-- The dispatch app provides the demultiplexing of incoming packets
-- based on the source and destination IPv6 addresses, which uniquely
-- identify a single pseudowire within one of the VPLS instances.
--
-- An instance of apps.bridge.learning or apps.bridge.flooding is
-- created for every VPLS, depending on the selected bridge type.  The
-- bridge connects all pseudowires and attachment circuits of the
-- VPLS.  The pseudowires are assigned to a split horizon group,
-- i.e. packets arriving on any of those links are only forwarded to
-- the attachment circuits and not to any of the other pseudowires
-- (this is a consequence of the full-mesh topology of the pseudowires
-- of a VPLS).
--
-- Every pseudowire can have its own tunnel configuration or it can
-- inherit a default configuration for the entire VPLS instance.
--
-- Finally, all pseudowires of all VPLS instances are connected to the
-- dispatcher on the uplink side.
--
-- If a VPLS consists of a single PW and a single AC, the resulting
-- two-port bridge is optimized away by creating a direct link between
-- the two.  The VPLS thus turns into a VPWS.

module(...,package.seeall)
local app = require("core.app")
local c_config = require("core.config")
local nd = require("apps.ipv6.nd_light").nd_light
local dispatch = require("apps.ipv6.dispatch").dispatch
local pseudowire = require("apps.vpn.pseudowire").pseudowire
local ethernet = require("lib.protocol.ethernet")
local ipv6 = require("lib.protocol.ipv6")

-- config = {
--   uplink = {
--     driver = <driver>,
--     config = <driver-config>,
--     address = <ipv6-address>,
--     mac = <mac-address>,
--     [ neighbor_mac = <neighbor_mac>, [ neighbor_nd = true | false ], ]
--     next_hop = <ipv6-address>
--   },
--   vpls = {
--     <vpls1> = {
--       vc_id = <vc_id>,
--       [ description = <description> ,]
--       address = <ipv6-address>,
--       bridge = {
--         type = "flooding"|"learning",
--         [ config = <bridge-config> ]
--       },
--       mtu = <mtu>,
--       [ tunnel = <tunnel-config>, ]
--       [ cc = <cc-config>, ]
--       ac = {
--         <ac1> = {
--           driver = <driver>,
--           config = <driver-config>,
--           interface = <interface>
--         },
--         <ac2> = ...
--       },
--       pw = {
--         <pw1> = {
--            address = <ipv6-address>,
--            [ tunnel = <tunnel-config> ],
--            [ cc = <cc-config> ]
--         },
--         <pw2> = ...
--       },
--     },
--     <vpls2> = ...
--   }
-- }

local bridge_types = { flooding = true, learning = true }

local function ether_pton (addr)
   if type(addr) == "string" then
      return ethernet:pton(addr)
   else
      return addr
   end
end

local function ipv6_pton (addr)
   if type(addr) == "string" then
      return ipv6:pton(addr)
   else
      return addr
   end
end

function run (args)
   if #args ~= 1 then main.exit(1) end
   local file = table.remove(args, 1)
   local conf_f = assert(loadfile(file))
   local config = conf_f()

   local c = c_config.new()

   local uplink = config.uplink
   assert(uplink and uplink.driver and uplink.config
	  and uplink.address and uplink.mac, "missing uplink configuarion")
   uplink.address = ipv6_pton(uplink.address)
   uplink.mac = ether_pton(uplink.mac)
   c_config.app(c, "uplink", uplink.driver, uplink.config)
   local pw_eth_config = nil
   if uplink.neighbor_mac then
      uplink.neighbor_mac = ether_pton(uplink.neighbor_mac)
      -- Use static Ethernet header on uplink
      print("Using static Ethernet header on uplink (source "..
	    ethernet:ntop(uplink.mac)..", destination "..
	 ethernet:ntop(uplink.neighbor_mac)..")")
      pw_eth_config = { src = uplink.mac, dst = uplink.neighbor_mac }
      if uplink.neighbor_nd then
	 print("Enabling nd for uplink neighbor")
	 nd = require("apps.ipv6.ns_responder").ns_responder
	 c_config.app(c, "nd", nd, { local_ip  = uplink.address,
				     local_mac = uplink.mac })
      else
	 nd = nil
      end
   else
      assert(uplink.next_hop, "Missing next-hop")
      uplink.next_hop = ipv6_pton(uplink.next_hop)
      c_config.app(c, "nd", nd, { local_ip  = uplink.address,
				  local_mac = uplink.mac,
				  next_hop = uplink.next_hop })
   end
   if nd then
      c_config.link(c, "uplink.tx -> nd.south")
      c_config.link(c, "nd.south -> uplink.rx")
   end

   local dispatch_config = {}
   local dispatch_pws = {}
   assert(config.vpls, "Missing vpls configuration")
   for vpls, vpls_config in pairs(config.vpls) do
      print("Creating VPLS instance "..vpls
	    .." ("..(vpls_config.description or "<no description>")..")") 
      assert(vpls_config.mtu, "Missing MTU")
      assert(vpls_config.vc_id, "Missing VC ID")
      local bridge_config = { ports = {},
			      split_horizon_groups = { pw = {} } }
      if (vpls_config.bridge) then
	 local bridge = vpls_config.bridge
	 if bridge.type then
	    assert(bridge_types[bridge.type],
		   "invalid bridge type: "..bridge.type)
	 else
	    bridge.type = "flooding"
	 end
	 bridge_config.config = bridge.config
      end
      assert(vpls_config.address, "Missing address")
      vpls_config.address = ipv6_pton(vpls_config.address)
      assert(vpls_config.ac, "Missing ac configuration")
      assert(vpls_config.pw, "Missing pseudowire configuration")

      local pws = {}
      local acs = {}
      local tunnel_config = vpls_config.tunnel

      print("\tCreating attachment circuits")
      for ac, ac_config in pairs(vpls_config.ac) do
	 assert(ac_config.driver and ac_config.config and ac_config.interface,
		"incomplete configuration for AC "..ac)
	 local ac_name = vpls.."_ac_"..ac
	 print("\t\t"..ac_name)
	 ac_config.config.mtu = vpls_config.mtu
	 c_config.app(c, ac_name, ac_config.driver, ac_config.config)
	 table.insert(bridge_config.ports, ac_name)
	 table.insert(acs, { name = ac_name, config = ac_config })
      end

      print("\tCreating pseudowire instances")
      for pw, pw_config in pairs(vpls_config.pw) do
	 assert(tunnel_config or pw_config.tunnel,
		"Missing tunnel configuration for pseudowire "..pw
		   .." and no default specified")
	 assert(pw_config.address,
		"Missing remote address configuration for pseudowire "..pw)
	 pw_config.address = ipv6_pton(pw_config.address)
	 local pw = vpls..'_pw_'..pw
	 print("\t\t"..pw)
	 c_config.app(c, pw, pseudowire,
		      { name = pw,
			vc_id = vpls_config.vc_id,
			mtu = vpls_config.mtu,
			description = vpls_config.description,
			-- For a p2p VPN, pass the name of the AC
			-- interface so the PW module can set up the
			-- proper service-specific MIB
			interface = (#acs == 1 and acs[1].config.interface) or '',
			ethernet = pw_eth_config,
			transport = { type = 'ipv6',
				      src = vpls_config.address,
				      dst = pw_config.address },
			tunnel = pw_config.tunnel or tunnel_config,
			cc = pw_config.cc or vpls_config.cc or nil
		     })
	 table.insert(pws, pw)
	 table.insert(dispatch_pws, pw)
	 table.insert(bridge_config.split_horizon_groups.pw, pw)
	 dispatch_config[pw] = { source      = pw_config.address,
				 destination = vpls_config.address }
      end

      if #pws == 1 and #acs == 1 then
	 -- Optimize a two-port bridge as a direct attachment of the
	 -- PW and AC
	 print("\tShort-Circuit "..pws[1].." <-> "..acs[1].name)
	 c_config.link(c, pws[1]..".ac -> "..acs[1].name..".rx")
	 c_config.link(c, acs[1].name..".tx -> "..pws[1]..".ac")
      else
	 local vpls_bridge = vpls.."_bridge"
	 print("\tCreating bridge "..vpls_bridge)
	 c_config.app(c, vpls_bridge,
		      require("apps.bridge."..vpls_config.bridge.type).bridge,
		      bridge_config)
	 for _, pw in ipairs(pws) do
	    c_config.link(c, pw..".ac -> "..vpls_bridge.."."..pw)
	    c_config.link(c, vpls_bridge.."."..pw.." -> "..pw..".ac")
	 end
	 for _, ac in ipairs(acs) do
	    c_config.link(c, vpls_bridge.."."..ac.name.." -> "..ac.name..".rx")
	    c_config.link(c, ac.name..".tx -> "..vpls_bridge.."."..ac.name)
	 end
      end
   end

   c_config.app(c, "dispatch", dispatch, dispatch_config)
   for _, pw in ipairs(dispatch_pws) do
      c_config.link(c, "dispatch."..pw.." -> "..pw..".uplink")
      c_config.link(c, pw..".uplink -> dispatch."..pw)
   end
   if nd then
      c_config.link(c, "nd.north -> dispatch.south")
      c_config.link(c, "dispatch.south -> nd.north")
   else
      c_config.link(c, "uplink.tx -> dispatch.south")
      c_config.link(c, "dispatch.south -> uplink.rx")
   end
   app.configure(c)

   --require("jit.opt").start('sizemcode=64','maxmcode=2048','loopunroll=20','maxsnap=8000', 'maxrecord=8000')
   --require("jit.opt").start('loopunroll=20','maxsnap=8000', 'maxrecord=8000')
   
   -- defaults: sizemcode=32, maxmcode=512, maxsnap=500
   require("jit.opt").start('sizemcode=64', 'maxmcode=1024')
   
   -- local profiler = timer.new("profiler",
   -- 			   function (t)
   -- 			      require("jit.p").stop()
   -- 			      app.report()
   -- 			      require("jit.p").start('5vlm1')
   -- 			   end, 1e9 * 60, 'repeating')
   -- timer.activate(profiler)
   
   require("jit.p").start('10vlm1')
   require("jit.dump").start('+rs', 'dump')
   jit.on()
   app.main({duration = 320}) --, report = {showapps = true} })
   --app.main({ no_timers = 1})
   require("jit.p").stop()
end
