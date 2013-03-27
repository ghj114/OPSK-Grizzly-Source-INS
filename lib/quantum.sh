#!/bin/bash

TOP_DIR=$(pwd)
set -ex
source $TOP_DIR/settings
source $TOP_DIR/functions

# Set up default directories
QUANTUM_DIR=$DEST_DIR/quantum
QUANTUM_AUTH_CACHE_DIR=${QUANTUM_AUTH_CACHE_DIR:-/var/cache/quantum}

QUANTUM_CONF_DIR=/etc/quantum
QUANTUM_CONF=$QUANTUM_CONF_DIR/quantum.conf
#QUANTUM_LOG=${QUANTUM_LOG:-/var/log/quantum}
QUANTUM_LOG=$DATA_DIR/log/quantum
export QUANTUM_TEST_CONFIG_FILE=${QUANTUM_TEST_CONFIG_FILE:-"$QUANTUM_CONF_DIR/debug.ini"}

Q_PLUGIN=${Q_PLUGIN:-openvswitch}
Q_PORT=${Q_PORT:-9696}
Q_HOST=${Q_HOST:-$HOST_IP}
Q_ADMIN_USERNAME=${Q_ADMIN_USERNAME:-quantum}
Q_AUTH_STRATEGY=${Q_AUTH_STRATEGY:-keystone}
Q_USE_NAMESPACE=${Q_USE_NAMESPACE:-False}
Q_USE_ROOTWRAP=${Q_USE_ROOTWRAP:-True}
Q_META_DATA_IP=${Q_META_DATA_IP:-$HOST_IP}
Q_ALLOW_OVERLAPPING_IP=${Q_ALLOW_OVERLAPPING_IP:-True}
Q_USE_DEBUG_COMMAND=${Q_USE_DEBUG_COMMAND:-False}
Q_ROUTER_NAME=${Q_ROUTER_NAME:-router1}
Q_USE_SECGROUP=True

QUANTUM_ROOTWRAP=/usr/local/bin/nova-rootwrap
Q_RR_CONF_FILE=$QUANTUM_CONF_DIR/rootwrap.conf
#Q_RR_COMMAND="sudo $QUANTUM_ROOTWRAP $Q_RR_CONF_FILE"
Q_RR_COMMAND="sudo"


ENABLE_TENANT_TUNNELS=${ENABLE_TENANT_TUNNELS:-True}
TENANT_TUNNEL_RANGES=${TENANT_TUNNEL_RANGE:-1:1000}
ENABLE_TENANT_VLANS=${ENABLE_TENANT_VLANS:-False}
TENANT_VLAN_RANGE=${TENANT_VLAN_RANGE:-}
PHYSICAL_NETWORK=${PHYSICAL_NETWORK:-}
OVS_PHYSICAL_BRIDGE=${OVS_PHYSICAL_BRIDGE:-}
OVS_ENABLE_TUNNELING=${OVS_ENABLE_TUNNELING:-$ENABLE_TENANT_TUNNELS}

# _quantum_setup_rootwrap() - configure Quantum's rootwrap
function _quantum_setup_rootwrap() {
    if [[ "$Q_USE_ROOTWRAP" == "False" ]]; then
        return
    fi
    # Deploy new rootwrap filters files (owned by root).
    # Wipe any existing rootwrap.d files first
    Q_CONF_ROOTWRAP_D=$QUANTUM_CONF_DIR/rootwrap.d
    if [[ -d $Q_CONF_ROOTWRAP_D ]]; then
        sudo rm -rf $Q_CONF_ROOTWRAP_D
    fi
    # Deploy filters to $QUANTUM_CONF_DIR/rootwrap.d
    mkdir -p -m 755 $Q_CONF_ROOTWRAP_D
    cp -pr $QUANTUM_DIR/etc/quantum/rootwrap.d/* $Q_CONF_ROOTWRAP_D/
    sudo chown -R root:root $Q_CONF_ROOTWRAP_D
    sudo chmod 644 $Q_CONF_ROOTWRAP_D/*
    # Set up rootwrap.conf, pointing to $QUANTUM_CONF_DIR/rootwrap.d
    # location moved in newer versions, prefer new location
    if test -r $QUANTUM_DIR/etc/quantum/rootwrap.conf; then
      sudo cp -p $QUANTUM_DIR/etc/quantum/rootwrap.conf $Q_RR_CONF_FILE
    else
      sudo cp -p $QUANTUM_DIR/etc/rootwrap.conf $Q_RR_CONF_FILE
    fi
    sudo sed -e "s:^filters_path=.*$:filters_path=$Q_CONF_ROOTWRAP_D:" -i $Q_RR_CONF_FILE
    sudo chown root:root $Q_RR_CONF_FILE
    sudo chmod 0644 $Q_RR_CONF_FILE
    # Specify rootwrap.conf as first parameter to quantum-rootwrap
    ROOTWRAP_SUDOER_CMD="$QUANTUM_ROOTWRAP $Q_RR_CONF_FILE *"

    # Update the root_helper
    iniset $QUANTUM_CONF AGENT root_helper "$Q_RR_COMMAND"
}


# _configure_quantum_common()
# Set common config for all quantum server and agents.
# This MUST be called before other _configure_quantum_* functions.
function _configure_quantum_common() {
    # Put config files in ``QUANTUM_CONF_DIR`` for everyone to find
    if [[ ! -d $QUANTUM_CONF_DIR ]]; then
        sudo mkdir -p $QUANTUM_CONF_DIR
    fi

    cp $QUANTUM_DIR/etc/quantum.conf $QUANTUM_CONF

    # set plugin-specific variables Q_PLUGIN_CONF_PATH, Q_PLUGIN_CONF_FILENAME, Q_DB_NAME, Q_PLUGIN_CLASS
    #quantum_plugin_configure_common
    Q_PLUGIN_CONF_PATH=etc/quantum/plugins/openvswitch
    Q_PLUGIN_CONF_FILENAME=ovs_quantum_plugin.ini
    Q_DB_NAME="quantum"
    Q_PLUGIN_CLASS="quantum.plugins.openvswitch.ovs_quantum_plugin.OVSQuantumPluginV2"

    # If needed, move config file from ``$QUANTUM_DIR/etc/quantum`` to ``QUANTUM_CONF_DIR``
    mkdir -p /$Q_PLUGIN_CONF_PATH
    Q_PLUGIN_CONF_FILE=$Q_PLUGIN_CONF_PATH/$Q_PLUGIN_CONF_FILENAME
    cp $QUANTUM_DIR/$Q_PLUGIN_CONF_FILE /$Q_PLUGIN_CONF_FILE

    iniset /$Q_PLUGIN_CONF_FILE DATABASE sql_connection mysql://quantum:$MYSQL_SERVICE_PASS@$MYSQL_HOST/$Q_DB_NAME
    iniset $QUANTUM_CONF DEFAULT state_path $DATA_DIR/quantum
    #LOG_FORMAT="%(asctime)s %(levelname)8s [%(name)s] %(message)s %(funcName)s %(pathname)s:%(lineno)d"
    #iniset $QUANTUM_CONF DEFAULT log_format $LOG_FORMAT
    _quantum_setup_rootwrap
}


function quantum_plugin_configure_service() {
    if [[ "$ENABLE_TENANT_TUNNELS" = "True" ]]; then
        iniset /$Q_PLUGIN_CONF_FILE OVS tenant_network_type gre
        iniset /$Q_PLUGIN_CONF_FILE OVS tunnel_id_ranges $TENANT_TUNNEL_RANGES
    fi

    # Enable tunnel networks if selected
    if [[ $OVS_ENABLE_TUNNELING = "True" ]]; then
        iniset /$Q_PLUGIN_CONF_FILE OVS enable_tunneling True
    fi
}

# Configures keystone integration for quantum service and agents
function _quantum_setup_keystone() {
    local conf_file=$1
    local section=$2
    local use_auth_url=$3
    if [[ -n $use_auth_url ]]; then
        iniset $conf_file $section auth_url "$KEYSTONE_SERVICE_PROTOCOL://$KEYSTONE_AUTH_HOST:$KEYSTONE_AUTH_PORT/v2.0"
    else
        iniset $conf_file $section auth_host $KEYSTONE_IP
        iniset $conf_file $section auth_port $KEYSTONE_AUTH_PORT
        iniset $conf_file $section auth_protocol $KEYSTONE_AUTH_PROTOCOL
    fi
    iniset $conf_file $section admin_tenant_name $SERVICE_TENANT_NAME
    iniset $conf_file $section admin_user $Q_ADMIN_USERNAME
    iniset $conf_file $section admin_password $SERVICE_PASSWORD
    iniset $conf_file $section signing_dir $QUANTUM_AUTH_CACHE_DIR
    # Create cache dir
    sudo mkdir -p $QUANTUM_AUTH_CACHE_DIR
    #sudo chown $STACK_USER $QUANTUM_AUTH_CACHE_DIR
    rm -f $QUANTUM_AUTH_CACHE_DIR/*
}

# _configure_quantum_service() - Set config files for quantum service
# It is called when q-svc is enabled.
function _configure_quantum_service() {
    Q_API_PASTE_FILE=$QUANTUM_CONF_DIR/api-paste.ini
    Q_POLICY_FILE=$QUANTUM_CONF_DIR/policy.json
    cp $QUANTUM_DIR/etc/api-paste.ini $Q_API_PASTE_FILE
    cp $QUANTUM_DIR/etc/policy.json $Q_POLICY_FILE

    mysql -h$MYSQL_HOST -uroot -p$MYSQL_ROOT_PASS -e 'DROP DATABASE IF EXISTS quantum;'
    mysql -h$MYSQL_HOST -uroot -p$MYSQL_ROOT_PASS -e 'CREATE DATABASE quantum CHARACTER SET utf8;'
    echo "GRANT ALL ON quantum.* TO 'quantum'@'%' IDENTIFIED BY '$MYSQL_SERVICE_PASS'; FLUSH PRIVILEGES;" | mysql -h$MYSQL_HOST -uroot -p$MYSQL_ROOT_PASS

    # Update either configuration file with plugin
    iniset $QUANTUM_CONF DEFAULT core_plugin $Q_PLUGIN_CLASS

    if [[ $Q_SERVICE_PLUGIN_CLASSES != '' ]]; then
        iniset $QUANTUM_CONF DEFAULT service_plugins $Q_SERVICE_PLUGIN_CLASSES
    fi

    iniset $QUANTUM_CONF DEFAULT verbose False 
    iniset $QUANTUM_CONF DEFAULT debug True
    iniset $QUANTUM_CONF DEFAULT policy_file $Q_POLICY_FILE
    iniset $QUANTUM_CONF DEFAULT allow_overlapping_ips $Q_ALLOW_OVERLAPPING_IP

    iniset $QUANTUM_CONF DEFAULT auth_strategy $Q_AUTH_STRATEGY
    iniset $QUANTUM_CONF DEFAULT api_paste_config $Q_API_PASTE_FILE 
    _quantum_setup_keystone $QUANTUM_CONF keystone_authtoken

    # Comment out keystone authtoken configuration in api-paste.ini
    # It is required to avoid any breakage in Quantum where the sample
    # api-paste.ini has authtoken configurations.
    #_quantum_commentout_keystone_authtoken $Q_API_PASTE_FILE filter:authtoken
    #inicomment $Q_API_PASTE_FILE filter:authtoken auth_host
    #inicomment $Q_API_PASTE_FILE filter:authtoken auth_port
    #inicomment $Q_API_PASTE_FILE filter:authtoken auth_protocol
    #inicomment $Q_API_PASTE_FILE filter:authtoken auth_url

    #inicomment $Q_API_PASTE_FILE filter:authtoken admin_tenant_name
    #inicomment $Q_API_PASTE_FILE filter:authtoken admin_user
    #inicomment $Q_API_PASTE_FILE filter:authtoken admin_password
    #inicomment $Q_API_PASTE_FILE filter:authtoken signing_dir
    
    # Configure plugin
    quantum_plugin_configure_service
}

function _quantum_ovs_base_setup_bridge() {
    local bridge=$1
    quantum-ovs-cleanup
    sudo ovs-vsctl --no-wait -- --may-exist add-br $bridge
    sudo ovs-vsctl --no-wait br-set-external-id $bridge bridge-id $bridge
}

function _quantum_ovs_base_configure_firewall_driver() {
    if [[ "$Q_USE_SECGROUP" == "True" ]]; then
        iniset /$Q_PLUGIN_CONF_FILE SECURITYGROUP firewall_driver quantum.agent.linux.iptables_firewall.OVSHybridIptablesFirewallDriver
    else
        iniset /$Q_PLUGIN_CONF_FILE SECURITYGROUP firewall_driver quantum.agent.firewall.NoopFirewallDriver
    fi
}

function quantum_plugin_configure_plugin_agent() {
    # Setup integration bridge
    OVS_BRIDGE=${OVS_BRIDGE:-br-int}
    _quantum_ovs_base_setup_bridge $OVS_BRIDGE
    _quantum_ovs_base_configure_firewall_driver

    # Setup agent for tunneling
    if [[ "$OVS_ENABLE_TUNNELING" = "True" ]]; then
        # Verify tunnels are supported
        # REVISIT - also check kernel module support for GRE and patch ports
        OVS_VERSION=`ovs-vsctl --version | head -n 1 | awk '{print $4;}'`
        if [ $OVS_VERSION \< "1.4" ] && ! is_service_enabled q-svc ; then
            die $LINENO "You are running OVS version $OVS_VERSION. OVS 1.4+ is required for tunneling between multiple hosts."
        fi
        iniset /$Q_PLUGIN_CONF_FILE OVS enable_tunneling True
        iniset /$Q_PLUGIN_CONF_FILE OVS local_ip $MYDATA_IP
    fi
    AGENT_BINARY="$QUANTUM_DIR/bin/quantum-openvswitch-agent"
}

# _configure_quantum_plugin_agent() - Set config files for quantum plugin agent
# It is called when q-agt is enabled.
function _configure_quantum_plugin_agent() {
    # Specify the default root helper prior to agent configuration to
    # ensure that an agent's configuration can override the default
    iniset /$Q_PLUGIN_CONF_FILE AGENT root_helper "$Q_RR_COMMAND"

    # Configure agent for plugin
    quantum_plugin_configure_plugin_agent
}


function _configure_quantum_dhcp_agent() {
    AGENT_DHCP_BINARY="$QUANTUM_DIR/bin/quantum-dhcp-agent"
    Q_DHCP_CONF_FILE=$QUANTUM_CONF_DIR/dhcp_agent.ini

    cp $QUANTUM_DIR/etc/dhcp_agent.ini $Q_DHCP_CONF_FILE

    iniset $Q_DHCP_CONF_FILE DEFAULT verbose False
    iniset $Q_DHCP_CONF_FILE DEFAULT debug True
    iniset $Q_DHCP_CONF_FILE DEFAULT use_namespaces $Q_USE_NAMESPACE
    iniset $Q_DHCP_CONF_FILE DEFAULT root_helper "$Q_RR_COMMAND"

    _quantum_setup_keystone $Q_DHCP_CONF_FILE DEFAULT set_auth_url
    #_quantum_setup_interface_driver $Q_DHCP_CONF_FILE
    iniset $Q_DHCP_CONF_FILE DEFAULT interface_driver quantum.agent.linux.interface.OVSInterfaceDriver

    #quantum_plugin_configure_dhcp_agent
    iniset $Q_DHCP_CONF_FILE DEFAULT dhcp_agent_manager quantum.agent.dhcp_agent.DhcpAgentWithStateReport
}

function _configure_quantum_l3_agent() {
    Q_L3_ENABLED=True
    # for l3-agent, only use per tenant router if we have namespaces
    Q_L3_ROUTER_PER_TENANT=$Q_USE_NAMESPACE
    AGENT_L3_BINARY="$QUANTUM_DIR/bin/quantum-l3-agent"
    PUBLIC_BRIDGE=${PUBLIC_BRIDGE:-br-ex}
    Q_L3_CONF_FILE=$QUANTUM_CONF_DIR/l3_agent.ini

    cp $QUANTUM_DIR/etc/l3_agent.ini $Q_L3_CONF_FILE

    iniset $Q_L3_CONF_FILE DEFAULT verbose False
    iniset $Q_L3_CONF_FILE DEFAULT debug True
    iniset $Q_L3_CONF_FILE DEFAULT use_namespaces $Q_USE_NAMESPACE
    iniset $Q_L3_CONF_FILE DEFAULT root_helper "$Q_RR_COMMAND"

    _quantum_setup_keystone $Q_L3_CONF_FILE DEFAULT set_auth_url
    #_quantum_setup_interface_driver $Q_L3_CONF_FILE
    iniset $Q_L3_CONF_FILE DEFAULT interface_driver quantum.agent.linux.interface.OVSInterfaceDriver

    #quantum_plugin_configure_l3_agent
    iniset $Q_L3_CONF_FILE DEFAULT external_network_bridge $PUBLIC_BRIDGE
    quantum-ovs-cleanup
    sudo ovs-vsctl --no-wait -- --may-exist add-br $PUBLIC_BRIDGE
    # ensure no IP is configured on the public bridge
    sudo ip addr flush dev $PUBLIC_BRIDGE
    iniset $Q_L3_CONF_FILE DEFAULT l3_agent_manager quantum.agent.l3_agent.L3NATAgentWithStateReport
}

# configure_quantum()
# Set common config for all quantum server and agents.
function configure_quantum() {
    _configure_quantum_common
    #iniset_rpc_backend quantum $QUANTUM_CONF DEFAULT
    iniset $QUANTUM_CONF DEFAULT rabbit_host $RABBITMQ_IP

    # goes before q-svc to init Q_SERVICE_PLUGIN_CLASSES
    #if is_service_enabled q-lbaas; then
    #    _configure_quantum_lbaas
    #fi
    if [[ $QUANTUM_SERVER = "True" ]]; then
        _configure_quantum_service
    fi
    if [[ $QUANTUM_AGENT = "True" ]]; then
        _configure_quantum_plugin_agent
    fi
    if [[ $QUANTUM_DHCP = "True" ]]; then
        _configure_quantum_dhcp_agent
    fi
    if [[ $QUANTUM_L3 = "True" ]]; then
        _configure_quantum_l3_agent
    fi
    #if is_service_enabled q-meta; then
    #    _configure_quantum_metadata_agent
    #fi

    #_configure_quantum_debug_command
}

# init_quantum() - Initialize databases, etc.
function init_quantum() {
    :
}

# Start running processes, including screen
function start_quantum_service_and_check() {
    # Start the Quantum service
    #screen_it q-svc "cd $QUANTUM_DIR && python $QUANTUM_DIR/bin/quantum-server --config-file $QUANTUM_CONF --config-file /$Q_PLUGIN_CONF_FILE"
    if [[ ! -d $QUANTUM_LOG ]]; then
        sudo mkdir -p $QUANTUM_LOG
    fi
    cd $QUANTUM_DIR && (python $QUANTUM_DIR/bin/quantum-server --config-file $QUANTUM_CONF --config-file /$Q_PLUGIN_CONF_FILE --log-file $QUANTUM_LOG/q-server.log &)
    echo "Waiting for Quantum to start..."
    sleep 5
}

function create_quantum_initial_network() {
    export SERVICE_TOKEN=$SERVICE_TOKEN
    export SERVICE_ENDPOINT=$SERVICE_ENDPOINT 
    #export SERVICE_TOKEN=CentRin
    #export SERVICE_ENDPOINT=http://192.168.0.7:35357/v2.0/
    TENANT_ID=$(keystone tenant-list | grep " admin " | get_field 1)

    # Create a small network
    # Since quantum command is executed in admin context at this point,
    # ``--tenant_id`` needs to be specified.
    NET_ID=$(quantum net-create --tenant_id $TENANT_ID "$PRIVATE_NETWORK_NAME" | grep ' id ' | get_field 2)
    SUBNET_ID=$(quantum subnet-create --tenant_id $TENANT_ID --ip_version 4 --gateway $NETWORK_GATEWAY $NET_ID $FIXED_RANGE | grep ' id ' | get_field 2)

    if [[ "$Q_L3_ENABLED" == "True" ]]; then
        # Create a router, and add the private subnet as one of its interfaces
        if [[ "$Q_L3_ROUTER_PER_TENANT" == "True" ]]; then
            # create a tenant-owned router.
            ROUTER_ID=$(quantum router-create --tenant_id $TENANT_ID $Q_ROUTER_NAME | grep ' id ' | get_field 2)
        else
            # Plugin only supports creating a single router, which should be admin owned.
            ROUTER_ID=$(quantum router-create $Q_ROUTER_NAME | grep ' id ' | get_field 2)
        fi
        quantum router-interface-add $ROUTER_ID $SUBNET_ID
        # Create an external network, and a subnet. Configure the external network as router gw
        EXT_NET_ID=$(quantum net-create "$PUBLIC_NETWORK_NAME" -- --router:external=True | grep ' id ' | get_field 2)
        EXT_GW_IP=$(quantum subnet-create --ip_version 4 ${Q_FLOATING_ALLOCATION_POOL:+--allocation-pool $Q_FLOATING_ALLOCATION_POOL} $EXT_NET_ID $FLOATING_RANGE -- --enable_dhcp=False | grep 'gateway_ip' | get_field 2)
        quantum router-gateway-set $ROUTER_ID $EXT_NET_ID

        if [[ "$QUANTUM_L3" == "True" ]]; then
            # logic is specific to using the l3-agent for l3
            if [[ "$Q_USE_NAMESPACE" = "True" ]]; then
                CIDR_LEN=${FLOATING_RANGE#*/}
                sudo ip addr add $EXT_GW_IP/$CIDR_LEN dev $PUBLIC_BRIDGE
                sudo ip link set $PUBLIC_BRIDGE up
                ROUTER_GW_IP=`quantum port-list -c fixed_ips -c device_owner | grep router_gateway | awk -F '"' '{ print $8; }'`
                sudo route add -net $FIXED_RANGE gw $ROUTER_GW_IP
            fi
            if [[ "$Q_USE_NAMESPACE" == "False" ]]; then
                # Explicitly set router id in l3 agent configuration
                iniset $Q_L3_CONF_FILE DEFAULT router_id $ROUTER_ID
            fi
        fi
   fi
}

# Start running processes, including screen
function start_quantum_agents() {
    # Start up the quantum agents if enabled
    if [[ ! -d $QUANTUM_LOG ]]; then
        sudo mkdir -p $QUANTUM_LOG
    fi
    cd $QUANTUM_DIR && (python $AGENT_BINARY --config-file $QUANTUM_CONF --config-file /$Q_PLUGIN_CONF_FILE --log-file $QUANTUM_LOG/q-agent.log &)
    cd $QUANTUM_DIR && (python $AGENT_DHCP_BINARY --config-file $QUANTUM_CONF --config-file=$Q_DHCP_CONF_FILE --log-file $QUANTUM_LOG/q-dhcp-agent.log &)
    cd $QUANTUM_DIR && (python $AGENT_L3_BINARY --config-file $QUANTUM_CONF --config-file=$Q_L3_CONF_FILE --log-file $QUANTUM_LOG/q-l3-agent.log &)
    #screen_it q-meta "cd $QUANTUM_DIR && python $AGENT_META_BINARY --config-file $QUANTUM_CONF --config-file=$Q_META_CONF_FILE"
    #screen_it q-lbaas "cd $QUANTUM_DIR && python $AGENT_LBAAS_BINARY --config-file $QUANTUM_CONF --config-file=$LBAAS_AGENT_CONF_FILENAME"
}

configure_quantum
init_quantum
if [[ $QUANTUM_SERVER = "True" ]]; then
    start_quantum_service_and_check
fi
if [[ $QUANTUM_NETWORK_NODE = "True" ]]; then
    create_quantum_initial_network
    #setup_quantum_debug
    start_quantum_agents
fi

echo "quantum is installed over!"
sleep 1
