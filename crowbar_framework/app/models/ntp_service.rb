#
# Copyright 2011-2013, Dell
# Copyright 2013-2014, SUSE LINUX Products GmbH
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

class NtpService < ServiceObject
  def initialize(thelogger)
    super(thelogger)
    @bc_name = "ntp"
  end

  class << self
    def role_constraints
      {
        "ntp-server" => {
          "unique" => true,
          "count" => -1,
          "admin" => true,
          "exclude_platform" => {
            "windows" => "/.*/"
          }
        },
        "ntp-client" => {
          "unique" => true,
          "count" => -1,
          "admin" => true
        }
      }
    end
  end

  def validate_proposal_after_save proposal
    validate_at_least_n_for_role proposal, "ntp-server", 1

    super
  end

  def proposal_create_bootstrap(params)
    params["deployment"][@bc_name]["elements"]["ntp-server"] = [Node.admin_node.name]
    super(params)
  end

  def transition(inst, name, state)
    @logger.debug("NTP transition: entering: #{name} for #{state}")

    node = Node.find_by_name(name)
    if node.allocated? && !node.role?("ntp-server")
      db = Proposal.where(barclamp: @bc_name, name: inst).first
      role = RoleObject.find_role_by_name "#{@bc_name}-config-#{inst}"

      unless add_role_to_instance_and_node(@bc_name, inst, name, db, role, "ntp-client")
        msg = "Failed to add ntp-client role to #{name}!"
        @logger.error(msg)
        return [400, msg]
      end
    end

    @logger.debug("NTP transition: leaving: #{name} for #{state}")
    [200, { name: name }]
  end

  def apply_role_pre_chef_call(old_role, role, all_nodes)
    @logger.debug("NTP apply_role_pre_chef_call: entering #{all_nodes.inspect}")

    save_config_to_databag(old_role, role)

    @logger.debug("NTP apply_role_pre_chef_call: leaving")
  end

  def save_config_to_databag(old_role, role)
    if role.nil?
      config = nil
    else
      server_nodes_names = role.override_attributes["ntp"]["elements"]["ntp-server"]
      server_nodes = server_nodes_names.map { |n| Node.find_by_name(n) }

      addresses = server_nodes.map do |n|
        admin_net = n.get_network_by_type("admin")
        # admin_net may be nil in the bootstrap case, because admin server only
        # gets its IP on hardware-installing, which is after this is first
        # called
        admin_net["address"] unless admin_net.nil?
      end
      addresses.sort!.compact!

      config = { servers: addresses }
    end

    instance = Crowbar::DataBagConfig.instance_from_role(old_role, role)
    Crowbar::DataBagConfig.save("core", instance, @bc_name, config)
  end
end
