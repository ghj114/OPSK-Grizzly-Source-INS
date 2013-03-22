#!/bin/bash

TOP_DIR=$(pwd)
set -ex
source $TOP_DIR/settings
source $TOP_DIR/functions

# Set up default directories
GLANCE_CACHE_DIR=${GLANCE_CACHE_DIR:=$DATA_DIR/glance/cache}
GLANCE_IMAGE_DIR=${GLANCE_IMAGE_DIR:=$DATA_DIR/glance/images}
GLANCE_AUTH_CACHE_DIR=${GLANCE_AUTH_CACHE_DIR:-/var/cache/glance}

GLANCE_CONF_DIR=${GLANCE_CONF_DIR:-/etc/glance}
GLANCE_REGISTRY_CONF=$GLANCE_CONF_DIR/glance-registry.conf
GLANCE_API_CONF=$GLANCE_CONF_DIR/glance-api.conf
GLANCE_REGISTRY_PASTE_INI=$GLANCE_CONF_DIR/glance-registry-paste.ini
GLANCE_API_PASTE_INI=$GLANCE_CONF_DIR/glance-api-paste.ini
GLANCE_CACHE_CONF=$GLANCE_CONF_DIR/glance-cache.conf
GLANCE_POLICY_JSON=$GLANCE_CONF_DIR/policy.json
GLANCE_BIN_DIR=$GLANCE_DIR/bin

# configure_glance() - Set config files, create data dirs, etc
function configure_glance() {
    if [[ ! -d $GLANCE_CONF_DIR ]]; then
        sudo mkdir -p $GLANCE_CONF_DIR
    fi
    #sudo chown $STACK_USER $GLANCE_CONF_DIR

    # Copy over our glance configurations and update them
    cp $GLANCE_DIR/etc/glance-registry.conf $GLANCE_REGISTRY_CONF
    iniset $GLANCE_REGISTRY_CONF DEFAULT debug True
    inicomment $GLANCE_REGISTRY_CONF DEFAULT log_file
    iniset $GLANCE_REGISTRY_CONF DEFAULT sql_connection mysql://glance:$MYSQL_SERVICE_PASS@$MYSQL_HOST/glance
    #iniset $GLANCE_REGISTRY_CONF DEFAULT use_syslog $SYSLOG
    iniset $GLANCE_REGISTRY_CONF paste_deploy flavor keystone
    iniset $GLANCE_REGISTRY_CONF keystone_authtoken auth_host $KEYSTONE_IP
    #iniset $GLANCE_REGISTRY_CONF keystone_authtoken auth_port $KEYSTONE_AUTH_PORT
    #iniset $GLANCE_REGISTRY_CONF keystone_authtoken auth_protocol $KEYSTONE_AUTH_PROTOCOL
    #iniset $GLANCE_REGISTRY_CONF keystone_authtoken auth_uri $KEYSTONE_SERVICE_PROTOCOL://$KEYSTONE_SERVICE_HOST:$KEYSTONE_SERVICE_PORT/
    iniset $GLANCE_REGISTRY_CONF keystone_authtoken admin_tenant_name $SERVICE_TENANT_NAME
    iniset $GLANCE_REGISTRY_CONF keystone_authtoken admin_user glance
    iniset $GLANCE_REGISTRY_CONF keystone_authtoken admin_password $SERVICE_PASSWORD
    iniset $GLANCE_REGISTRY_CONF keystone_authtoken signing_dir $GLANCE_AUTH_CACHE_DIR/registry

    cp $GLANCE_DIR/etc/glance-api.conf $GLANCE_API_CONF
    iniset $GLANCE_API_CONF DEFAULT debug True
    inicomment $GLANCE_API_CONF DEFAULT log_file
    iniset $GLANCE_API_CONF DEFAULT sql_connection mysql://glance:$MYSQL_SERVICE_PASS@$MYSQL_HOST/glance
    #iniset $GLANCE_API_CONF DEFAULT use_syslog $SYSLOG
    iniset $GLANCE_API_CONF DEFAULT filesystem_store_datadir $GLANCE_IMAGE_DIR/
    iniset $GLANCE_API_CONF DEFAULT image_cache_dir $GLANCE_CACHE_DIR/
    iniset $GLANCE_API_CONF paste_deploy flavor keystone+cachemanagement
    iniset $GLANCE_API_CONF keystone_authtoken auth_host $KEYSTONE_IP
    #iniset $GLANCE_API_CONF keystone_authtoken auth_port $KEYSTONE_AUTH_PORT
    #iniset $GLANCE_API_CONF keystone_authtoken auth_protocol $KEYSTONE_AUTH_PROTOCOL
    #iniset $GLANCE_API_CONF keystone_authtoken auth_uri $KEYSTONE_SERVICE_PROTOCOL://$KEYSTONE_SERVICE_HOST:$KEYSTONE_SERVICE_PORT/
    iniset $GLANCE_API_CONF keystone_authtoken admin_tenant_name $SERVICE_TENANT_NAME
    iniset $GLANCE_API_CONF keystone_authtoken admin_user glance
    iniset $GLANCE_API_CONF keystone_authtoken admin_password $SERVICE_PASSWORD
    iniset $GLANCE_API_CONF DEFAULT notifier_strategy rabbit
    #iniset_rpc_backend glance $GLANCE_API_CONF DEFAULT
    iniset $GLANCE_API_CONF DEFAULT rabbit_host $RABBITMQ_IP
    iniset $GLANCE_API_CONF keystone_authtoken signing_dir $GLANCE_AUTH_CACHE_DIR/api

    cp -p $GLANCE_DIR/etc/glance-registry-paste.ini $GLANCE_REGISTRY_PASTE_INI

    cp -p $GLANCE_DIR/etc/glance-api-paste.ini $GLANCE_API_PASTE_INI

    cp $GLANCE_DIR/etc/glance-cache.conf $GLANCE_CACHE_CONF
    iniset $GLANCE_CACHE_CONF DEFAULT debug True
    inicomment $GLANCE_CACHE_CONF DEFAULT log_file
    iniset $GLANCE_CACHE_CONF DEFAULT use_syslog $SYSLOG
    iniset $GLANCE_CACHE_CONF DEFAULT filesystem_store_datadir $GLANCE_IMAGE_DIR/
    iniset $GLANCE_CACHE_CONF DEFAULT image_cache_dir $GLANCE_CACHE_DIR/
    iniuncomment $GLANCE_CACHE_CONF DEFAULT auth_url
    iniset $GLANCE_CACHE_CONF DEFAULT auth_url http://$KEYSTONE_IP:35357/v2.0
    iniuncomment $GLANCE_CACHE_CONF DEFAULT auth_tenant_name
    iniset $GLANCE_CACHE_CONF DEFAULT admin_tenant_name $SERVICE_TENANT_NAME
    iniuncomment $GLANCE_CACHE_CONF DEFAULT auth_user
    iniset $GLANCE_CACHE_CONF DEFAULT admin_user glance
    iniuncomment $GLANCE_CACHE_CONF DEFAULT auth_password
    iniset $GLANCE_CACHE_CONF DEFAULT admin_password $SERVICE_PASSWORD

    cp -p $GLANCE_DIR/etc/policy.json $GLANCE_POLICY_JSON
}

# init_glance() - Initialize databases, etc.
function init_glance() {
    # Delete existing images
    rm -rf $GLANCE_IMAGE_DIR
    mkdir -p $GLANCE_IMAGE_DIR

    # Delete existing cache
    rm -rf $GLANCE_CACHE_DIR
    mkdir -p $GLANCE_CACHE_DIR

    # Create cache dir
    #create_glance_cache_dir
    sudo mkdir -p $GLANCE_AUTH_CACHE_DIR/api
    #sudo chown $STACK_USER $GLANCE_AUTH_CACHE_DIR/api
    rm -f $GLANCE_AUTH_CACHE_DIR/api/*
    sudo mkdir -p $GLANCE_AUTH_CACHE_DIR/registry
    #sudo chown $STACK_USER $GLANCE_AUTH_CACHE_DIR/registry
    rm -f $GLANCE_AUTH_CACHE_DIR/registry/*

    # (Re)create glance database
    #recreate_database glance utf8
    mysql -h$MYSQL_HOST -uroot -p$MYSQL_ROOT_PASS -e 'DROP DATABASE IF EXISTS glance;'
    mysql -h$MYSQL_HOST -uroot -p$MYSQL_ROOT_PASS -e 'CREATE DATABASE glance CHARACTER SET utf8;'
    echo "GRANT ALL ON glance.* TO 'glance'@'%' IDENTIFIED BY '$MYSQL_SERVICE_PASS'; FLUSH PRIVILEGES;" | mysql -h $MYSQL_HOST -uroot -p$MYSQL_ROOT_PASS

    # Migrate glance database
    $GLANCE_BIN_DIR/glance-manage db_sync
}

# start_glance() - Start running processes, including screen
function start_glance() {
    cd $GLANCE_DIR && ($GLANCE_BIN_DIR/glance-registry --config-file=$GLANCE_CONF_DIR/glance-registry.conf &)
    cd $GLANCE_DIR && ($GLANCE_BIN_DIR/glance-api --config-file=$GLANCE_CONF_DIR/glance-api.conf &)
    echo "Waiting for g-api ($GLANCE_HOSTPORT) to start..."
    sleep 10
}

configure_glance
init_glance
start_glance
exit 0

#apt-get update
#apt-get upgrade
apt-get install -y python-mysqldb mysql-client curl
apt-get install -y python-prettytable
apt-get install -y python-keystone python-keystoneclient
apt-get install -y glance glance-api glance-common glance-registry python-glance python-glanceclient
rm -f /var/lib/glance/glance.sqlite

# Glance Setup
mysql -h$MYSQL_HOST -uroot -p$MYSQL_ROOT_PASS -e 'DROP DATABASE IF EXISTS glance;'
mysql -h$MYSQL_HOST -uroot -p$MYSQL_ROOT_PASS -e 'CREATE DATABASE glance CHARACTER SET utf8;'
echo "GRANT ALL ON glance.* TO 'glance'@'%' IDENTIFIED BY '$MYSQL_SERVICE_PASS'; FLUSH PRIVILEGES;" | mysql -h $MYSQL_HOST -uroot -p$MYSQL_ROOT_PASS

# glance-api.conf.tmpl
sed -e "s,%MYSQL_HOST%,$MYSQL_HOST,g" -e "s,%MYSQL_GLANCE_PASS%,$MYSQL_SERVICE_PASS,g" ./conf/glance/glance-api.conf.tmpl > ./conf/glance/glance-api.conf
sed -e "s,%KEYSTONE_IP%,$KEYSTONE_IP,g" -e "s,%SERVICE_TENANT_NAME%,$SERVICE_TENANT_NAME,g" -e "s,%SERVICE_PASSWORD%,$SERVICE_PASSWORD,g" -i ./conf/glance/glance-api.conf

# glance-registry.conf.tmpl
sed -e "s,%MYSQL_HOST%,$MYSQL_HOST,g" -e "s,%MYSQL_GLANCE_PASS%,$MYSQL_SERVICE_PASS,g" ./conf/glance/glance-registry.conf.tmpl > ./conf/glance/glance-registry.conf
sed -e "s,%KEYSTONE_IP%,$KEYSTONE_IP,g" -e "s,%SERVICE_TENANT_NAME%,$SERVICE_TENANT_NAME,g" -e "s,%SERVICE_PASSWORD%,$SERVICE_PASSWORD,g" -i ./conf/glance/glance-registry.conf

cp ./conf/glance/glance-api.conf ./conf/glance/glance-registry.conf /etc/glance/
rm -f ./conf/glance/glance-api.conf ./conf/glance/glance-registry.conf 

chown glance:glance /etc/glance/glance-api.conf
chown glance:glance /etc/glance/glance-registry.conf

service glance-api restart
service glance-registry restart

#glance-manage version_control 0
glance-manage db_sync

#service glance-api restart
#service glance-registry restart

#./glance-upload-ttylinux.sh
#./glance-upload-oneiric.sh
#./glance-upload-loader.sh
#./glance-upload-lucid-loader.sh

echo "glance install over!"
sleep 1

