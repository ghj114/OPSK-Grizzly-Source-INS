#!/bin/bash

TOP_DIR=$(pwd)
set -ex
source $TOP_DIR/settings
source $TOP_DIR/functions

# Set up default directories
NOVA_DIR=${NOVA_DIR:-$DEST/nova}
NOVA_BIN_DIR=$NOVA_DIR/bin
NOVA_STATE_PATH=${NOVA_STATE_PATH:=$DATA_DIR/nova}
# INSTANCES_PATH is the previous name for this
NOVA_INSTANCES_PATH=${NOVA_INSTANCES_PATH:=${INSTANCES_PATH:=$NOVA_STATE_PATH/instances}}
NOVA_AUTH_CACHE_DIR=${NOVA_AUTH_CACHE_DIR:-/var/cache/nova}
NOVA_LOG=$DATA_DIR/log/nova

NOVA_CONF_DIR=/etc/nova
NOVA_CONF=$NOVA_CONF_DIR/nova.conf
NOVA_API_PASTE_INI=${NOVA_API_PASTE_INI:-$NOVA_CONF_DIR/api-paste.ini}

# Public facing bits
NOVA_SERVICE_HOST=${NOVA_SERVICE_HOST:-$SERVICE_HOST}
NOVA_SERVICE_PORT=${NOVA_SERVICE_PORT:-8774}
NOVA_ROOTWRAP=/usr/local/bin/nova-rootwrap




# configure_nova() - Set config files, create data dirs, etc
function configure_nova() {
    # Put config files in ``/etc/nova`` for everyone to find
    if [[ ! -d $NOVA_CONF_DIR ]]; then
        sudo mkdir -p $NOVA_CONF_DIR
    fi
    #sudo chown $STACK_USER $NOVA_CONF_DIR

    cp -p $NOVA_DIR/etc/nova/policy.json $NOVA_CONF_DIR

    #configure_nova_rootwrap
    if [[ -d $NOVA_CONF_DIR/rootwrap.d ]]; then
        sudo rm -rf $NOVA_CONF_DIR/rootwrap.d
    fi
    sudo mkdir -m 755 $NOVA_CONF_DIR/rootwrap.d
    sudo cp $NOVA_DIR/etc/nova/rootwrap.d/*.filters $NOVA_CONF_DIR/rootwrap.d
    sudo chown -R root:root $NOVA_CONF_DIR/rootwrap.d
    sudo chmod 644 $NOVA_CONF_DIR/rootwrap.d/*
    sudo cp $NOVA_DIR/etc/nova/rootwrap.conf $NOVA_CONF_DIR/
    sudo sed -e "s:^filters_path=.*$:filters_path=$NOVA_CONF_DIR/rootwrap.d:" -i $NOVA_CONF_DIR/rootwrap.conf
    sudo chown root:root $NOVA_CONF_DIR/rootwrap.conf
    sudo chmod 0644 $NOVA_CONF_DIR/rootwrap.conf
    ROOTWRAP_SUDOER_CMD="$NOVA_ROOTWRAP $NOVA_CONF_DIR/rootwrap.conf *"

    # Remove legacy paste config if present
    rm -f $NOVA_DIR/bin/nova-api-paste.ini
    # Get the sample configuration file in place
    cp $NOVA_DIR/etc/nova/api-paste.ini $NOVA_CONF_DIR

    iniset $NOVA_API_PASTE_INI filter:authtoken auth_host $KEYSTONE_IP
    iniset $NOVA_API_PASTE_INI filter:authtoken admin_tenant_name $SERVICE_TENANT_NAME
    iniset $NOVA_API_PASTE_INI filter:authtoken admin_user nova
    iniset $NOVA_API_PASTE_INI filter:authtoken admin_password $SERVICE_PASSWORD
    iniset $NOVA_API_PASTE_INI filter:authtoken signing_dir $NOVA_AUTH_CACHE_DIR

    if [ "$COMPUTE_NODE" == "True" ]; then
        # Force IP forwarding on, just on case
        sudo sysctl -w net.ipv4.ip_forward=1

        # Attempt to load modules: network block device - used to manage qcow images
        sudo modprobe nbd || true

        # Check for kvm (hardware based virtualization).  If unable to initialize
        # kvm, we drop back to the slower emulation mode (qemu).  Note: many systems
        # come with hardware virtualization disabled in BIOS.
        if [[ "$LIBVIRT_TYPE" == "kvm" ]]; then
            sudo modprobe kvm || true
            if [ ! -e /dev/kvm ]; then
                echo "WARNING: Switching to QEMU"
                LIBVIRT_TYPE=qemu
                if which selinuxenabled 2>&1 > /dev/null && selinuxenabled; then
                    # https://bugzilla.redhat.com/show_bug.cgi?id=753589
                    sudo setsebool virt_use_execmem on
                fi
            fi
        fi
        # The user that nova runs as needs to be member of **libvirtd** group otherwise
        # nova-compute will be unable to use libvirt.
        #if ! getent group libvirtd >/dev/null; then
        #    sudo groupadd libvirtd
        #fi
        #add_user_to_group $STACK_USER libvirtd

        # libvirt detects various settings on startup, as we potentially changed
        # the system configuration (modules, filesystems), we need to restart
        # libvirt to detect those changes.

        LIBVIRT_DAEMON=libvirt-bin
        sed -i '/#listen_tls/s/#listen_tls/listen_tls/; /#listen_tcp/s/#listen_tcp/listen_tcp/; /#auth_tcp/s/#auth_tcp/auth_tcp/; /auth_tcp/s/sasl/none/'  /etc/libvirt/libvirtd.conf
        sed -i '/env libvirtd_opts/s/-d/-d -l/' /etc/init/libvirt-bin.conf
        sed -i '/libvirtd_opts/s/-d/-d -l/' /etc/default/libvirt-bin
        service $LIBVIRT_DAEMON restart
        virsh net-destroy default
        virsh net-undefine default


        # Instance Storage
        # ----------------
        # Nova stores each instance in its own directory.
        mkdir -p $NOVA_INSTANCES_PATH
    fi
}


# create_nova_conf() - Create a new nova.conf file
function create_nova_conf() {
    # Remove legacy ``nova.conf``
    rm -f $NOVA_DIR/bin/nova.conf

    # (Re)create ``nova.conf``
    rm -f $NOVA_CONF
    echo "[DEFAULT]" >>$NOVA_CONF
    iniset $NOVA_CONF DEFAULT verbose "True"
    iniset $NOVA_CONF DEFAULT debug "True"
    iniset $NOVA_CONF DEFAULT auth_strategy "keystone"
    iniset $NOVA_CONF DEFAULT allow_resize_to_same_host "True"
    iniset $NOVA_CONF DEFAULT api_paste_config "$NOVA_API_PASTE_INI"
    iniset $NOVA_CONF DEFAULT rootwrap_config "$NOVA_CONF_DIR/rootwrap.conf"
    #iniset $NOVA_CONF DEFAULT compute_scheduler_driver "$SCHEDULER"
    iniset $NOVA_CONF DEFAULT dhcpbridge_flagfile "$NOVA_CONF"
    iniset $NOVA_CONF DEFAULT force_dhcp_release "True"
    iniset $NOVA_CONF DEFAULT fixed_range ""
    iniset $NOVA_CONF DEFAULT default_floating_pool "$PUBLIC_NETWORK_NAME"
    #iniset $NOVA_CONF DEFAULT s3_host "$SERVICE_HOST"
    #iniset $NOVA_CONF DEFAULT s3_port "$S3_SERVICE_PORT"
    iniset $NOVA_CONF DEFAULT osapi_compute_extension "nova.api.openstack.compute.contrib.standard_extensions"
    iniset $NOVA_CONF DEFAULT my_ip "$MYPRI_IP"
    iniset $NOVA_CONF DEFAULT sql_connection mysql://nova:$MYSQL_SERVICE_PASS@$MYSQL_HOST/nova
    iniset $NOVA_CONF DEFAULT libvirt_type "$LIBVIRT_TYPE"
    iniset $NOVA_CONF DEFAULT libvirt_cpu_mode "none"
    iniset $NOVA_CONF DEFAULT instance_name_template "${INSTANCE_NAME_PREFIX}%08x"
    iniset $NOVA_CONF DEFAULT enabled_apis "$NOVA_ENABLED_APIS"
    iniset $NOVA_CONF DEFAULT volume_api_class "nova.volume.cinder.API"
    if [ -n "$NOVA_STATE_PATH" ]; then
        iniset $NOVA_CONF DEFAULT state_path "$NOVA_STATE_PATH"
        iniset $NOVA_CONF DEFAULT lock_path "$NOVA_STATE_PATH"
    fi
    if [ -n "$NOVA_INSTANCES_PATH" ]; then
        iniset $NOVA_CONF DEFAULT instances_path "$NOVA_INSTANCES_PATH"
    fi
    if [ "$MULTI_HOST" != "False" ]; then
        iniset $NOVA_CONF DEFAULT multi_host "True"
        iniset $NOVA_CONF DEFAULT send_arp_for_ha "True"
    fi
    iniset $NOVA_CONF DEFAULT api_rate_limit "True"
    # Show user_name and project_name instead of user_id and project_id
    iniset $NOVA_CONF DEFAULT logging_context_format_string "%(asctime)s.%(msecs)03d %(levelname)s %(name)s [%(request_id)s %(user_name)s %(project_name)s] %(instance)s%(message)s"

    VNCSERVER_LISTEN=${VNCSERVER_LISTEN=0.0.0.0}
    VNCSERVER_PROXYCLIENT_ADDRESS=$CONTROLLER_IP
    iniset $NOVA_CONF DEFAULT vnc_enabled true
    iniset $NOVA_CONF DEFAULT vncserver_listen "$VNCSERVER_LISTEN"
    iniset $NOVA_CONF DEFAULT vncserver_proxyclient_address "$VNCSERVER_PROXYCLIENT_ADDRESS"

    if [ "$COMPUTE_NODE" == "True" ]; then
        NOVNCPROXY_URL=${NOVNCPROXY_URL:-"http://$CONTROLLER_IP:6080/vnc_auto.html"}
        iniset $NOVA_CONF DEFAULT novncproxy_base_url "$NOVNCPROXY_URL"
    fi
    
    #iniset $NOVA_CONF DEFAULT ec2_dmz_host "$EC2_DMZ_HOST"
    #iniset_rpc_backend nova $NOVA_CONF DEFAULT
    iniset $NOVA_CONF DEFAULT rabbit_host $RABBITMQ_IP
    iniset $NOVA_CONF DEFAULT glance_api_servers "$GLANCE_HOSTPORT"

    iniset $NOVA_CONF DEFAULT compute_driver "libvirt.LibvirtDriver"
    LIBVIRT_FIREWALL_DRIVER=${LIBVIRT_FIREWALL_DRIVER:-"nova.virt.libvirt.firewall.IptablesFirewallDriver"}
    iniset $NOVA_CONF DEFAULT firewall_driver "$LIBVIRT_FIREWALL_DRIVER"
}

function create_nova_conf_quantum() {
    iniset $NOVA_CONF DEFAULT network_api_class "nova.network.quantumv2.api.API"
    iniset $NOVA_CONF DEFAULT quantum_admin_username "quantum"
    iniset $NOVA_CONF DEFAULT quantum_admin_password "$SERVICE_PASSWORD"
    iniset $NOVA_CONF DEFAULT quantum_admin_auth_url "$KEYSTONE_AUTH_PROTOCOL://$KEYSTONE_IP:$KEYSTONE_AUTH_PORT/v2.0"
    iniset $NOVA_CONF DEFAULT quantum_auth_strategy "keystone"
    iniset $NOVA_CONF DEFAULT quantum_admin_tenant_name "$SERVICE_TENANT_NAME"
    iniset $NOVA_CONF DEFAULT quantum_url "http://$CONTROLLER:9696"

    iniset $NOVA_CONF DEFAULT libvirt_vif_driver "nova.virt.libvirt.vif.LibvirtHybridOVSBridgeDriver"
    iniset $NOVA_CONF DEFAULT linuxnet_interface_driver "nova.network.linux_net.LinuxOVSInterfaceDriver"
}

# init_nova() - Initialize databases, etc.
function init_nova() {
    mysql -h$MYSQL_HOST -uroot -p$MYSQL_ROOT_PASS -e 'DROP DATABASE IF EXISTS nova;'
    mysql -h$MYSQL_HOST -uroot -p$MYSQL_ROOT_PASS -e 'CREATE DATABASE nova CHARACTER SET latin1;'
    echo "GRANT ALL ON nova.* TO 'nova'@'%' IDENTIFIED BY '$MYSQL_SERVICE_PASS'; FLUSH PRIVILEGES;" | mysql -h$MYSQL_HOST -uroot -p$MYSQL_ROOT_PASS
    $NOVA_BIN_DIR/nova-manage db sync

    #create_nova_cache_dir
    sudo mkdir -p $NOVA_AUTH_CACHE_DIR
    rm -f $NOVA_AUTH_CACHE_DIR/*
    #create_nova_keys_dir
    sudo mkdir -p ${NOVA_STATE_PATH}/keys
}

# start_nova() - Start running processes, including screen
function start_nova() {
    # The group **libvirtd** is added to the current user in this script.
    # Use 'sg' to execute nova-compute as a member of the **libvirtd** group.
    # ``screen_it`` checks ``is_service_enabled``, it is not needed here
    # Start up the quantum agents if enabled
    if [[ ! -d $NOVA_LOG ]]; then
        sudo mkdir -p $NOVA_LOG
    fi
    if [ "$CONTROLLER_NODE" == "True" ]; then
        cd $NOVA_DIR && ($NOVA_BIN_DIR/nova-api --log-file $NOVA_LOG/nova-api.log &)
        cd $NOVA_DIR && ($NOVA_BIN_DIR/nova-conductor --log-file $NOVA_LOG/nova-conductor.log &)
        cd $NOVA_DIR && ($NOVA_BIN_DIR/nova-cert --log-file $NOVA_LOG/nova-cert.log &)
        cd $NOVA_DIR && ($NOVA_BIN_DIR/nova-scheduler --log-file $NOVA_LOG/nova-scheduler.log &)
        cd $NOVA_DIR && ($NOVA_BIN_DIR/nova-novncproxy --config-file $NOVA_CONF --web $NOVNC_DIR &)
        cd $NOVA_DIR && ($NOVA_BIN_DIR/nova-consoleauth --log-file $NOVA_LOG/nova-consoleauth.log &)
    else
        cd $NOVA_DIR && ($NOVA_BIN_DIR/nova-compute --log-file $NOVA_LOG/nova-compute.log &)
    fi

}

configure_nova
create_nova_conf
create_nova_conf_quantum
if [ "$CONTROLLER_NODE" == "True" ]; then
    init_nova
fi
start_nova

echo "nova-controller install over!"
sleep 5


#apt-get install -y ntp
#sed -i 's/server ntp.ubuntu.com/server ntp.ubuntu.com\nserver 127.127.1.0\nfudge 127.127.1.0 stratum 10/g' /etc/ntp.conf
#service ntp restart

#nova-compute-kvm vlan bridge-utils nova-network 
#apt-get install -y python-mysqldb mysql-client curl
#apt-get install -y nova-api nova-scheduler nova-common nova-cert nova-console 
#apt-get install -y novnc nova-novncproxy nova-consoleauth websockify
#apt-get install -y nova-volume

#if [ $MULTI_HOST = 'False' ]; then apt-get install -y nova-network;/etc/init.d/networking restart; fi

#mysql -h192.168.1.100 -uroot -proot -e 'DROP DATABASE IF EXISTS nova;'
#mysql -h192.168.1.100 -uroot -proot -e 'CREATE DATABASE nova;'
#echo "GRANT ALL ON nova.* TO 'nova'@'%' IDENTIFIED BY 'service'; FLUSH PRIVILEGES;" | mysql -h192.168.1.100 -uroot -proot



