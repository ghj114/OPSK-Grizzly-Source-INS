#!/bin/bash

TOP_DIR=$(pwd)
set -ex
source $TOP_DIR/settings
source $TOP_DIR/functions

# set up default driver
CINDER_DRIVER=${CINDER_DRIVER:-default}

# set up default directories
CINDER_DIR=${CINDER_DIR:-$DEST/cinder}
CINDER_BIN_DIR=$CINDER_DIR/bin
CINDER_STATE_PATH=${CINDER_STATE_PATH:=$DATA_DIR/cinder}
CINDER_AUTH_CACHE_DIR=${CINDER_AUTH_CACHE_DIR:-/var/cache/cinder}

CINDER_CONF_DIR=/etc/cinder
CINDER_CONF=$CINDER_CONF_DIR/cinder.conf
CINDER_API_PASTE_INI=$CINDER_CONF_DIR/api-paste.ini

# Public facing bits
CINDER_SERVICE_HOST=${CINDER_SERVICE_HOST:-$CINDER_IP}
CINDER_SERVICE_PORT=${CINDER_SERVICE_PORT:-8776}
CINDER_MULTI_LVM_BACKEND=False

VOLUME_GROUP=${VOLUME_GROUP:-cinder-volumes}
VOLUME_GROUP2=${VOLUME_GROUP2:-cinder-volumes2}
VOLUME_NAME_PREFIX=${VOLUME_NAME_PREFIX:-volume-}
CINDER_SECURE_DELETE=True

# configure_cinder() - Set config files, create data dirs, etc
function configure_cinder() {
    if [[ ! -d $CINDER_CONF_DIR ]]; then
        sudo mkdir -p $CINDER_CONF_DIR
    fi
    #sudo chown $STACK_USER $CINDER_CONF_DIR

    cp -p $CINDER_DIR/etc/cinder/policy.json $CINDER_CONF_DIR

    # Set the paths of certain binaries
    #CINDER_ROOTWRAP=$(get_rootwrap_location cinder)
    CINDER_ROOTWRAP=/usr/local/bin/cinder-rootwrap

    # If Cinder ships the new rootwrap filters files, deploy them
    # (owned by root) and add a parameter to $CINDER_ROOTWRAP
    ROOTWRAP_CINDER_SUDOER_CMD="$CINDER_ROOTWRAP"
    if [[ -d $CINDER_DIR/etc/cinder/rootwrap.d ]]; then
        # Wipe any existing rootwrap.d files first
        if [[ -d $CINDER_CONF_DIR/rootwrap.d ]]; then
            sudo rm -rf $CINDER_CONF_DIR/rootwrap.d
        fi
        # Deploy filters to /etc/cinder/rootwrap.d
        sudo mkdir -m 755 $CINDER_CONF_DIR/rootwrap.d
        sudo cp $CINDER_DIR/etc/cinder/rootwrap.d/*.filters $CINDER_CONF_DIR/rootwrap.d
        sudo chown -R root:root $CINDER_CONF_DIR/rootwrap.d
        sudo chmod 644 $CINDER_CONF_DIR/rootwrap.d/*
        # Set up rootwrap.conf, pointing to /etc/cinder/rootwrap.d
        sudo cp $CINDER_DIR/etc/cinder/rootwrap.conf $CINDER_CONF_DIR/
        sudo sed -e "s:^filters_path=.*$:filters_path=$CINDER_CONF_DIR/rootwrap.d:" -i $CINDER_CONF_DIR/rootwrap.conf
        sudo chown root:root $CINDER_CONF_DIR/rootwrap.conf
        sudo chmod 0644 $CINDER_CONF_DIR/rootwrap.conf
        # Specify rootwrap.conf as first parameter to cinder-rootwrap
        CINDER_ROOTWRAP="$CINDER_ROOTWRAP $CINDER_CONF_DIR/rootwrap.conf"
        ROOTWRAP_CINDER_SUDOER_CMD="$CINDER_ROOTWRAP *"
    fi

    #TEMPFILE=`mktemp`
    #echo "$USER ALL=(root) NOPASSWD: $ROOTWRAP_CINDER_SUDOER_CMD" >$TEMPFILE
    #chmod 0440 $TEMPFILE
    #sudo chown root:root $TEMPFILE
    #sudo mv $TEMPFILE /etc/sudoers.d/cinder-rootwrap

    cp $CINDER_DIR/etc/cinder/api-paste.ini $CINDER_API_PASTE_INI
    iniset $CINDER_API_PASTE_INI filter:authtoken auth_host $KEYSTONE_IP
    iniset $CINDER_API_PASTE_INI filter:authtoken auth_port $KEYSTONE_AUTH_PORT
    iniset $CINDER_API_PASTE_INI filter:authtoken auth_protocol $KEYSTONE_AUTH_PROTOCOL
    iniset $CINDER_API_PASTE_INI filter:authtoken admin_tenant_name $SERVICE_TENANT_NAME
    iniset $CINDER_API_PASTE_INI filter:authtoken admin_user cinder
    iniset $CINDER_API_PASTE_INI filter:authtoken admin_password $SERVICE_PASSWORD
    iniset $CINDER_API_PASTE_INI filter:authtoken signing_dir $CINDER_AUTH_CACHE_DIR

    cp $CINDER_DIR/etc/cinder/cinder.conf.sample $CINDER_CONF
    iniset $CINDER_CONF DEFAULT auth_strategy keystone
    iniset $CINDER_CONF DEFAULT debug True
    iniset $CINDER_CONF DEFAULT verbose True
    if [ "$CINDER_MULTI_LVM_BACKEND" = "True" ]; then
        iniset $CINDER_CONF DEFAULT enabled_backends lvmdriver-1,lvmdriver-2
        iniset $CINDER_CONF lvmdriver-1 volume_group $VOLUME_GROUP
        iniset $CINDER_CONF lvmdriver-1 volume_driver cinder.volume.drivers.lvm.LVMISCSIDriver
        iniset $CINDER_CONF lvmdriver-1 volume_backend_name LVM_iSCSI
        iniset $CINDER_CONF lvmdriver-2 volume_group $VOLUME_GROUP2
        iniset $CINDER_CONF lvmdriver-2 volume_driver cinder.volume.drivers.lvm.LVMISCSIDriver
        iniset $CINDER_CONF lvmdriver-2 volume_backend_name LVM_iSCSI
    else
        iniset $CINDER_CONF DEFAULT volume_group $VOLUME_GROUP
        iniset $CINDER_CONF DEFAULT volume_name_template ${VOLUME_NAME_PREFIX}%s
    fi
    iniset $CINDER_CONF DEFAULT iscsi_helper tgtadm
    iniset $CINDER_CONF DEFAULT sql_connection mysql://cinder:$MYSQL_SERVICE_PASS@$MYSQL_HOST/cinder
    iniset $CINDER_CONF DEFAULT api_paste_config $CINDER_API_PASTE_INI
    iniset $CINDER_CONF DEFAULT rootwrap_config "$CINDER_CONF_DIR/rootwrap.conf"
    iniset $CINDER_CONF DEFAULT osapi_volume_extension cinder.api.contrib.standard_extensions
    iniset $CINDER_CONF DEFAULT state_path $CINDER_STATE_PATH
    #iniset_rpc_backend cinder $CINDER_CONF DEFAULT
    iniset $GLANCE_API_CONF DEFAULT rabbit_host $RABBITMQ_IP

    if [[ "$CINDER_SECURE_DELETE" == "False" ]]; then
        iniset $CINDER_CONF DEFAULT secure_delete False
        iniset $CINDER_CONF DEFAULT volume_clear none
    fi
}

# init_cinder() - Initialize database and volume group
function init_cinder() {

    mysql -h$MYSQL_HOST -uroot -p$MYSQL_ROOT_PASS -e 'DROP DATABASE IF EXISTS cinder;'
    mysql -h$MYSQL_HOST -uroot -p$MYSQL_ROOT_PASS -e 'CREATE DATABASE cinder CHARACTER SET utf8;'
    echo "GRANT ALL ON cinder.* TO 'cinder'@'%' IDENTIFIED BY '$MYSQL_SERVICE_PASS'; FLUSH PRIVILEGES;" | mysql -h$MYSQL_HOST -uroot -p$MYSQL_ROOT_PASS
    $CINDER_BIN_DIR/cinder-manage db sync

    #create_cinder_volume_group
    #pvcreate ${CINDER_VOLUME} # CINDER_VOLUME = '/dev/sda6'
    #vgcreate cinder-volumes ${CINDER_VOLUME}

    #if is_service_enabled c-vol; then
    #    if sudo vgs $VOLUME_GROUP; then
    #        # Remove iscsi targets
    #        sudo tgtadm --op show --mode target | grep $VOLUME_NAME_PREFIX | grep Target | cut -f3 -d ' ' | sudo xargs -n1 tgt-admin --delete || true
    #        # Start with a clean volume group
    #        _clean_volume_group $VOLUME_GROUP $VOLUME_NAME_PREFIX
    #        if [ "$CINDER_MULTI_LVM_BACKEND" = "True" ]; then
    #            _clean_volume_group $VOLUME_GROUP2 $VOLUME_NAME_PREFIX
    #        fi
    #    fi
    #fi

    #create_cinder_cache_dir
    # Create cache dir
    sudo mkdir -p $CINDER_AUTH_CACHE_DIR
    #sudo chown $STACK_USER $CINDER_AUTH_CACHE_DIR
    rm -f $CINDER_AUTH_CACHE_DIR/*
}

# start_cinder() - Start running processes, including screen
function start_cinder() {
    if [[ ! -d /etc/tgt/conf.d/ ]]; then
        sudo mkdir -p /etc/tgt/conf.d
        echo "include /etc/tgt/conf.d/*.conf" | sudo tee -a /etc/tgt/targets.conf
    fi
    if [[ ! -f /etc/tgt/conf.d/cinder.conf ]]; then
        echo "include $CINDER_STATE_PATH/volumes/*" | sudo tee /etc/tgt/conf.d/cinder.conf
    fi
    sudo stop tgt || true
    sudo start tgt

    cd $CINDER_DIR && ($CINDER_BIN_DIR/glance-registry --config-file=$GLANCE_CONF_DIR/glance-registry.conf &)
    cd $CINDER_DIR && ($CINDER_BIN_DIR/glance-api --config-file=$GLANCE_CONF_DIR/glance-api.conf &)

    cd $CINDER_DIR && ($CINDER_BIN_DIR/cinder-api --config-file $CINDER_CONF &)
    cd $CINDER_DIR && ($CINDER_BIN_DIR/cinder-volume --config-file $CINDER_CONF &)
    cd $CINDER_DIR && ($CINDER_BIN_DIR/cinder-scheduler --config-file $CINDER_CONF &)
    cd $CINDER_DIR && ($CINDER_BIN_DIR/cinder-backup --config-file $CINDER_CONF &)

    echo "Waiting for cinder to start..."
    sleep 10

}

configure_cinder
init_cinder
start_cinder


#apt-get update
#apt-get upgrade

#apt-get install -y python-mysqldb mysql-client curl
#apt-get install -y python-keystone python-keystoneclient
#apt-get install -y cinder-api cinder-scheduler cinder-volume iscsitarget open-iscsi iscsitarget-dkms

#sed -i 's/false/true/g' /etc/default/iscsitarget
#service iscsitarget start
#service open-iscsi start

# cinder Setup
#mysql -h192.168.1.100 -uroot -proot -e 'DROP DATABASE IF EXISTS cinder;'
#mysql -h192.168.1.100 -uroot -proot -e 'CREATE DATABASE cinder;'
#echo "GRANT ALL ON cinder.* TO 'cinder'@'%' IDENTIFIED BY 'service'; FLUSH PRIVILEGES;" | mysql -h192.168.1.100 -uroot -proot

# using file instead
# dd if=/dev/zero of=/opt/cinder-volumes.img bs=1M seek=5120 count=0
# losetup -f /opt/cinder-volumes.img
# losetup -a
# vgcreate cinder-volumes /dev/loop0

# restart processes
#service cinder-volume restart
#service cinder-api restart

#echo "cinder install over!"
#sleep 1

