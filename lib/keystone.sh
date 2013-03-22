#!/bin/bash

# configure_keystone
# init_keystone
# start_keystone

TOP_DIR=$(pwd)
set -ex
source $TOP_DIR/settings
source $TOP_DIR/functions

# Set up default directories
KEYSTONE_CONF_DIR=${KEYSTONE_CONF_DIR:-/etc/keystone}
KEYSTONE_CONF=$KEYSTONE_CONF_DIR/keystone.conf
KEYSTONE_AUTH_CACHE_DIR=${KEYSTONE_AUTH_CACHE_DIR:-/var/cache/keystone}
#KEYSTONE_PASTE_INI=${KEYSTONE_PASTE_INI:-$KEYSTONE_CONF_DIR/keystone-paste.ini}

# configure_keystone() - Set config files, create data dirs, etc
function configure_keystone() {
    if [[ ! -d $KEYSTONE_CONF_DIR ]]; then
        sudo mkdir -p $KEYSTONE_CONF_DIR
    fi
    #sudo chown $STACK_USER $KEYSTONE_CONF_DIR

    if [[ "$KEYSTONE_CONF_DIR" != "$KEYSTONE_DIR/etc" ]]; then
        cp -p $KEYSTONE_DIR/etc/keystone.conf.sample $KEYSTONE_CONF
        cp -p $KEYSTONE_DIR/etc/policy.json $KEYSTONE_CONF_DIR
    fi

    # Rewrite stock ``keystone.conf``
    iniset $KEYSTONE_CONF DEFAULT admin_token "$SERVICE_TOKEN"
    iniset $KEYSTONE_CONF signing token_format UUID
    iniset $KEYSTONE_CONF sql connection "mysql://keystone:$MYSQL_SERVICE_PASS@$MYSQL_HOST/keystone"
    iniset $KEYSTONE_CONF ec2 driver "keystone.contrib.ec2.backends.sql.Ec2"
    iniset $KEYSTONE_CONF token driver keystone.token.backends.sql.Token
    iniset $KEYSTONE_CONF catalog driver keystone.catalog.backends.sql.Catalog
    #inicomment $KEYSTONE_CONF catalog template_file

    # Set up logging
    LOGGING_ROOT="devel"
    KEYSTONE_LOG_CONFIG="--log-config $KEYSTONE_CONF_DIR/logging.conf"
    cp $KEYSTONE_DIR/etc/logging.conf.sample $KEYSTONE_CONF_DIR/logging.conf
    iniset $KEYSTONE_CONF_DIR/logging.conf logger_root level "DEBUG"
    iniset $KEYSTONE_CONF_DIR/logging.conf logger_root handlers "devel,production"
}

# init_keystone() - Initialize databases, etc.
function init_keystone() {
    # (Re)create keystone database
    #recreate_database keystone utf8
    mysql -h$MYSQL_HOST -uroot -p$MYSQL_ROOT_PASS -e 'DROP DATABASE IF EXISTS keystone;'
    mysql -h$MYSQL_HOST -uroot -p$MYSQL_ROOT_PASS -e 'CREATE DATABASE keystone CHARACTER SET utf8;'
    echo "GRANT ALL ON keystone.* TO 'keystone'@'%' IDENTIFIED BY '$MYSQL_SERVICE_PASS';FLUSH PRIVILEGES;" | mysql -h$MYSQL_HOST -uroot -p$MYSQL_ROOT_PASS

    # Initialize keystone database
    $KEYSTONE_DIR/bin/keystone-manage db_sync
}

# start_keystone() - Start running processes, including screen
function start_keystone() {
    # Start Keystone in a screen window
    #screen_it key "cd $KEYSTONE_DIR && $KEYSTONE_DIR/bin/keystone-all --config-file $KEYSTONE_CONF $KEYSTONE_LOG_CONFIG -d --debug"
    cd $KEYSTONE_DIR && ($KEYSTONE_DIR/bin/keystone-all --config-file $KEYSTONE_CONF $KEYSTONE_LOG_CONFIG -d --debug &)
    echo "Waiting for keystone to start..."
    sleep 10
}

configure_keystone
init_keystone
start_keystone

chmod +x $TOP_DIR/lib/keystone_data.sh
$TOP_DIR/lib/keystone_data.sh

echo "keystone install over!"
sleep 1
