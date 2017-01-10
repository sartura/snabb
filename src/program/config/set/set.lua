-- Use of this source code is governed by the Apache 2.0 license; see COPYING.
module(..., package.seeall)

local common = require("program.config.common")

function run(args)
   args = common.parse_command_line(
      args, { command='set', with_path=true, with_value=true })
   local response = common.call_leader(
      args.instance_id, 'set-config',
      { schema = args.schema_name, revision = args.revision_date,
        path = args.path,
        config = common.serialize_config(
           args.value, args.schema_name, args.path) })
   -- The reply is empty.
   common.print_and_exit(response)
end
