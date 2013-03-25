#!/bin/bash

TOP_DIR=$(pwd)
set -ex
source $TOP_DIR/settings
source $TOP_DIR/functions

# Set up default directories
QUANTUM_DIR=$DEST/quantum
QUANTUM_AUTH_CACHE_DIR=${QUANTUM_AUTH_CACHE_DIR:-/var/cache/quantum}

QUANTUM_CONF_DIR=/etc/quantum
QUANTUM_CONF=$QUANTUM_CONF_DIR/quantum.conf
export QUANTUM_TEST_CONFIG_FILE=${QUANTUM_TEST_CONFIG_FILE:-"$QUANTUM_CONF_DIR/debug.ini"}

Q_PLUGIN=${Q_PLUGIN:-openvswitch}
Q_PORT=${Q_PORT:-9696}
Q_HOST=${Q_HOST:-$HOST_IP}
Q_ADMIN_USERNAME=${Q_ADMIN_USERNAME:-quantum}
Q_AUTH_STRATEGY=${Q_AUTH_STRATEGY:-keystone}
Q_USE_NAMESPACE=${Q_USE_NAMESPACE:-True}
Q_USE_ROOTWRAP=${Q_USE_ROOTWRAP:-True}
Q_META_DATA_IP=${Q_META_DATA_IP:-$HOST_IP}
Q_ALLOW_OVERLAPPING_IP=${Q_ALLOW_OVERLAPPING_IP:-True}
Q_USE_DEBUG_COMMAND=${Q_USE_DEBUG_COMMAND:-False}
Q_ROUTER_NAME=${Q_ROUTER_NAME:-router1}

QUANTUM_ROOTWRAP=/usr/local/bin/nova-rootwrap
Q_RR_CONF_FILE=$QUANTUM_CONF_DIR/rootwrap.conf
Q_RR_COMMAND="sudo $QUANTUM_ROOTWRAP $Q_RR_CONF_FILE"


ENABLE_TENANT_TUNNELS=${ENABLE_TENANT_TUNNELS:-False}
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
    #sudo chown $STACK_USER $QUANTUM_CONF_DIR

    cp $QUANTUM_DIR/etc/quantum.conf $QUANTUM_CONF

    # set plugin-specific variables
    # Q_PLUGIN_CONF_PATH, Q_PLUGIN_CONF_FILENAME, Q_DB_NAME, Q_PLUGIN_CLASS
    #quantum_plugin_configure_common
    Q_PLUGIN_CONF_PATH=etc/quantum/plugins/openvswitch
    Q_PLUGIN_CONF_FILENAME=ovs_quantum_plugin.ini
    Q_DB_NAME="ovs_quantum"
    Q_PLUGIN_CLASS="quantum.plugins.openvswitch.ovs_quantum_plugin.OVSQuantumPluginV2"

    if [[ $Q_PLUGIN_CONF_PATH == '' || $Q_PLUGIN_CONF_FILENAME == '' || $Q_PLUGIN_CLASS == '' ]]; then
        die $LINENO "Quantum plugin not set.. exiting"
    fi

    # If needed, move config file from ``$QUANTUM_DIR/etc/quantum`` to ``QUANTUM_CONF_DIR``
    mkdir -p /$Q_PLUGIN_CONF_PATH
    Q_PLUGIN_CONF_FILE=$Q_PLUGIN_CONF_PATH/$Q_PLUGIN_CONF_FILENAME
    cp $QUANTUM_DIR/$Q_PLUGIN_CONF_FILE /$Q_PLUGIN_CONF_FILE

    iniset /$Q_PLUGIN_CONF_FILE DATABASE sql_connection mysql://quantum:$MYSQL_SERVICE_PASS@$MYSQL_HOST/$Q_DB_NAME
    iniset $QUANTUM_CONF DEFAULT state_path $DATA_DIR/quantum

    _quantum_setup_rootwrap
}

# Configures keystone integration for quantum service and agents
function _quantum_setup_keystone() {
    local conf_file=$1
    local section=$2
    local use_auth_url=$3
    if [[ -n $use_auth_url ]]; then
        iniset $conf_file $section auth_url "$KEYSTONE_SERVICE_PROTOCOL://$KEYSTONE_AUTH_HOST:$KEYSTONE_AUTH_PORT/v2.0"
    else
        iniset $conf_file $section auth_host $KEYSTONE_SERVICE_HOST
        iniset $conf_file $section auth_port $KEYSTONE_AUTH_PORT
        iniset $conf_file $section auth_protocol $KEYSTONE_SERVICE_PROTOCOL
    fi
    iniset $conf_file $section admin_tenant_name $SERVICE_TENANT_NAME
    iniset $conf_file $section admin_user $Q_ADMIN_USERNAME
    iniset $conf_file $section admin_password $SERVICE_PASSWORD
    iniset $conf_file $section signing_dir $QUANTUM_AUTH_CACHE_DIR
    # Create cache dir
    sudo mkdir -p $QUANTUM_AUTH_CACHE_DIR
    sudo chown $STACK_USER $QUANTUM_AUTH_CACHE_DIR
    rm -f $QUANTUM_AUTH_CACHE_DIR/*
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
    if is_service_enabled q-svc; then
        #_configure_quantum_service
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

        iniset $QUANTUM_CONF DEFAULT verbose True
        iniset $QUANTUM_CONF DEFAULT debug True
        iniset $QUANTUM_CONF DEFAULT policy_file $Q_POLICY_FILE
        iniset $QUANTUM_CONF DEFAULT allow_overlapping_ips $Q_ALLOW_OVERLAPPING_IP

        iniset $QUANTUM_CONF DEFAULT auth_strategy $Q_AUTH_STRATEGY
        _quantum_setup_keystone $QUANTUM_CONF keystone_authtoken
        # Comment out keystone authtoken configuration in api-paste.ini
        # It is required to avoid any breakage in Quantum where the sample
        # api-paste.ini has authtoken configurations.
        _quantum_commentout_keystone_authtoken $Q_API_PASTE_FILE filter:authtoken

        # Configure plugin
        quantum_plugin_configure_service
    fi
    if is_service_enabled q-agt; then
        _configure_quantum_plugin_agent
    fi
    if is_service_enabled q-dhcp; then
        _configure_quantum_dhcp_agent
    fi
    if is_service_enabled q-l3; then
        _configure_quantum_l3_agent
    fi
    #if is_service_enabled q-meta; then
    #    _configure_quantum_metadata_agent
    #fi

    _configure_quantum_debug_command
}








set -ex
#set -n
source settings

#apt-get update
#apt-get upgrade

apt-get install -y ntp
sed -i 's/server ntp.ubuntu.com/server ntp.ubuntu.com\nserver 127.127.1.0\nfudge 127.127.1.0 stratum 10/g' /etc/ntp.conf
service ntp restart

#nova-compute-kvm vlan bridge-utils nova-network 
apt-get install -y python-mysqldb mysql-client curl
apt-get install -y nova-api nova-scheduler nova-common nova-cert nova-console 
apt-get install -y novnc nova-novncproxy nova-consoleauth websockify
#apt-get install -y nova-volume

if [ $MULTI_HOST = 'False' ]; then apt-get install -y nova-network;/etc/init.d/networking restart; fi

mysql -h$MYSQL_HOST -uroot -p$MYSQL_ROOT_PASS -e 'DROP DATABASE IF EXISTS nova;'
mysql -h$MYSQL_HOST -uroot -p$MYSQL_ROOT_PASS -e 'CREATE DATABASE nova;'
echo "GRANT ALL ON nova.* TO 'nova'@'%' IDENTIFIED BY '$MYSQL_SERVICE_PASS'; FLUSH PRIVILEGES;" | mysql -h$MYSQL_HOST -uroot -p$MYSQL_ROOT_PASS
#mysql -h192.168.1.100 -uroot -proot -e 'DROP DATABASE IF EXISTS nova;'
#mysql -h192.168.1.100 -uroot -proot -e 'CREATE DATABASE nova;'
#echo "GRANT ALL ON nova.* TO 'nova'@'%' IDENTIFIED BY 'service'; FLUSH PRIVILEGES;" | mysql -h192.168.1.100 -uroot -proot

# api-paste.ini.tmpl
sed -e "s,%KEYSTONE_IP%,$KEYSTONE_IP,g" ./conf/nova/api-paste.ini.tmpl > ./conf/nova/api-paste.ini
sed -e "s,%SERVICE_TENANT_NAME%,$SERVICE_TENANT_NAME,g" -e "s,%SERVICE_PASSWORD%,$SERVICE_PASSWORD,g" -i ./conf/nova/api-paste.ini
# nova.conf.tmpl
sed -e "s,%MYSQL_HOST%,$MYSQL_HOST,g" -e "s,%MYSQL_NOVA_PASS%,$MYSQL_SERVICE_PASS,g"  ./conf/nova/nova.conf.tmpl > ./conf/nova/nova.conf
sed -e "s,%CONTROLLER_IP%,$CONTROLLER_IP,g" -e "s,%CONTROLLER_IP_PUB%,$CONTROLLER_IP_PUB,g" -i ./conf/nova/nova.conf
sed -e "s,%KEYSTONE_IP%,$KEYSTONE_IP,g" -e "s,%RABBITMQ_IP%,$RABBITMQ_IP,g"  -i ./conf/nova/nova.conf
sed -e "s,%GLANCE_IP%,$GLANCE_IP,g"  -e "s,%COMPUTE_IP%,$COMPUTE_IP,g" -i ./conf/nova/nova.conf


#if [ $NETWORK_TYPE = 'VLAN' ];then
#    sed -e "s,%NETWORK_TYPE%,nova.network.manager.VlanManager,g" -i ./conf/nova/nova.conf
#elif [ $NETWORK_TYPE = 'FLATDHCP' ];then
#    sed -e "s,%NETWORK_TYPE%,nova.network.manager.FlatDHCPManager,g" -i ./conf/nova/nova.conf
#else
#    echo "ERROR:network type is not expecting"; exit -1;
#fi

cp ./conf/nova/nova.conf ./conf/nova/api-paste.ini /etc/nova/
rm -f ./conf/nova/nova.conf ./conf/nova/api-paste.ini
#chown nova:nova /etc/nova/nova.conf /etc/nova/api-paste.ini
chown -R nova. /etc/nova
chmod 644 /etc/nova/nova.conf

service nova-api restart
nova-manage db sync

for a in nova-api nova-scheduler nova-cert nova-consoleauth; do service "$a" restart; done 

mysql -h$MYSQL_HOST -uroot -p$MYSQL_ROOT_PASS -e 'DROP DATABASE IF EXISTS quantum;'
mysql -h$MYSQL_HOST -uroot -p$MYSQL_ROOT_PASS -e 'CREATE DATABASE quantum;'
echo "GRANT ALL ON quantum.* TO 'quantum'@'%' IDENTIFIED BY '$MYSQL_SERVICE_PASS'; FLUSH PRIVILEGES;" | mysql -h$MYSQL_HOST -uroot -p$MYSQL_ROOT_PASS

apt-get install -y quantum-server

# api-paste.ini.tmpl
sed -e "s,%KEYSTONE_IP%,$KEYSTONE_IP,g"  ./conf/quantum/api-paste.ini.tmpl > ./conf/quantum/api-paste.ini
sed -e "s,%SERVICE_TENANT_NAME%,$SERVICE_TENANT_NAME,g" -e "s,%SERVICE_PASSWORD%,$SERVICE_PASSWORD,g" -i ./conf/quantum/api-paste.ini

# quantum.conf.tmpl
sed -e "s,%RABBITMQ_IP%,$RABBITMQ_IP,g" ./conf/quantum/quantum.conf.tmpl > ./conf/quantum/quantum.conf

if [[ "$NETWORK_TYPE" = "gre" ]]; then
    sed -e "s,%QUANTUM_IP%,$QUANTUM_IP,g" ./conf/quantum-plugins-openvswitch/ovs_quantum_plugin.ini.gre.tmpl > ./conf/quantum-plugins-openvswitch/ovs_quantum_plugin.ini
    sed -e "s,%MYSQL_HOST%,$MYSQL_HOST,g" -e "s,%MYSQL_QUANTUM_PASS%,$MYSQL_SERVICE_PASS,g" -i ./conf/quantum-plugins-openvswitch/ovs_quantum_plugin.ini
elif [[ "$NETWORK_TYPE" = "vlan" ]]; then
    sed -e "s,%MYSQL_HOST%,$MYSQL_HOST,g" ./conf/quantum-plugins-openvswitch/ovs_quantum_plugin.ini.vlan.tmpl > ./conf/quantum-plugins-openvswitch/ovs_quantum_plugin.ini
    sed -e "s,%MYSQL_QUANTUM_PASS%,$MYSQL_SERVICE_PASS,g" ./conf/quantum-plugins-openvswitch/ovs_quantum_plugin.ini
else
    echo "<network_type> must be 'gre' or 'vlan'."
    exit 1
fi
cp ./conf/quantum/api-paste.ini ./conf/quantum/quantum.conf /etc/quantum/
cp ./conf/quantum-plugins-openvswitch/ovs_quantum_plugin.ini /etc/quantum/plugins/openvswitch
rm -f ./conf/quantum/api-paste.ini ./conf/quantum/quantum.conf
rm -f ./conf/quantum-plugins-openvswitch/ovs_quantum_plugin.ini 
#chown nova:nova /etc/nova/nova.conf /etc/nova/api-paste.ini
chown -R quantum. /etc/quantum
chmod 644 /etc/quantum/quantum.conf

service quantum-server restart

echo "nova-controller install over!"
sleep 1
