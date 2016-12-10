#!/usr/bin/env luajit
module(..., package.seeall)

-- Make sure running a snabb config get twice results in the
-- same values getting returned

local genyang = require("program.lwaftr.tests.propbased.genyang")
local S = require("syscall")
local run_pid
local current_cmd

function property()
   current_cmd = genyang.generate_yang(run_pid)
   local results  = (genyang.run_yang(current_cmd))
   local results2 = (genyang.run_yang(current_cmd))
   if string.match("Could not connect to config leader socket on Snabb instance",
                   results) or
      string.match("Could not connect to config leader socket on Snabb instance",
                   results2) then
      print("Launching snabb run failed, or we've crashed it!")
      return false
   end

   if results ~= results2 then
      print("Running the same config command twice produced different outputs")
      return false
   end
end

function print_extra_information()
   print("The command was:", current_cmd)
end

function handle_prop_args(prop_args)
   if #prop_args ~= 1 then
      print("Usage: snabb quickcheck prop_sameval PCI_ADDR")
      os.exit(1)
   end

   -- TODO: validate the address
   local pci_addr = prop_args[1]

   local pid = S.fork()
   if pid == 0 then
      local cmdline = {"snabb", "lwaftr", "run", "-D", "20", "--conf",
          "program/lwaftr/tests/data/icmp_on_fail.conf", "--reconfigurable", 
          "--on-a-stick", pci_addr}
      -- FIXME: preserve the environment
      S.execve(("/proc/%d/exe"):format(S.getpid()), cmdline, {})
   else
      run_pid = pid
      S.sleep(0.1)
   end
end

function cleanup()
   S.kill(run_pid, "TERM")
end
