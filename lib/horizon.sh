#!/bin/bash


TOP_DIR=$(pwd)
set -ex
source $TOP_DIR/settings
source $TOP_DIR/functions

# Set up default directories
HORIZON_DIR=$DEST_DIR/horizon

# Allow overriding the default Apache user and group, default to
# current user and his default group.
#APACHE_USER=${APACHE_USER:-$USER}
#APACHE_GROUP=${APACHE_GROUP:-$(id -gn $APACHE_USER)}
APACHE_USER=daemon
APACHE_GROUP=daemon

#function install_horizon() {
    # Apache installation, because we mark it NOPRIME
    # Install apache2, which is NOPRIME'd
    #install_package apache2 libapache2-mod-wsgi

    # NOTE(sdague) quantal changed the name of the node binary
    #if [[ ! -e "/usr/bin/node" ]]; then
    #    install_package nodejs-legacy
    #fi
#}


# init_horizon() - Initialize databases, etc.
function init_horizon() {
    # Remove stale session database.
    rm -f $HORIZON_DIR/openstack_dashboard/local/dashboard_openstack.sqlite3

    # ``local_settings.py`` is used to override horizon default settings.
    local_settings=$HORIZON_DIR/openstack_dashboard/local/local_settings.py
    cp $TOP_DIR/files/horizon_settings.py $local_settings

    # enable loadbalancer dashboard in case service is enabled
    #if is_service_enabled q-lbaas; then
    #    _horizon_config_set $local_settings OPENSTACK_QUANTUM_NETWORK enable_lb True
    #fi

    # Initialize the horizon database (it stores sessions and notices shown to
    # users).  The user system is external (keystone).
    cd $HORIZON_DIR
    python manage.py syncdb --noinput
    cd $TOP_DIR

    # Create an empty directory that apache uses as docroot
    sudo mkdir -p $HORIZON_DIR/.blackhole


    APACHE_NAME=apache2
    APACHE_CONF=sites-available/horizon
    # Clean up the old config name
    sudo rm -f /etc/apache2/sites-enabled/000-default
    # Be a good citizen and use the distro tools here
    sudo touch /etc/$APACHE_NAME/$APACHE_CONF
    sudo a2ensite horizon
    # WSGI isn't enabled by default, enable it
    sudo a2enmod wsgi

    # Configure apache to run horizon
    sudo sh -c "sed -e \"
        s,%USER%,$APACHE_USER,g;
        s,%GROUP%,$APACHE_GROUP,g;
        s,%HORIZON_DIR%,$HORIZON_DIR,g;
        s,%APACHE_NAME%,$APACHE_NAME,g;
        s,%DEST%,$DEST_DIR,g;
    \" files/apache-horizon.template >/etc/$APACHE_NAME/$APACHE_CONF"

}

init_horizon
service apache2 restart
echo "dashboard install over!"
sleep 1




# Settings
#set -e
#. settings
#
#apt-get install -y memcached libapache2-mod-wsgi openstack-dashboard
#
#service apache2 restart
#
#echo "dashboard install over!"
#sleep 1
#apt-get install -y openstackx
#apt-get install -y libapache2-mod-wsgi
#apt-get install -y openstack-dashboard

# Dashboard Setup

#mysql -h $MYSQL_HOST -u root -p$MYSQL_ROOT_PASS -e 'DROP DATABASE IF EXISTS horizon;'
#mysql -h $MYSQL_HOST -u root -p$MYSQL_ROOT_PASS -e 'CREATE DATABASE horizon;'
#echo "GRANT ALL ON horizon.* TO 'horizon'@'%' IDENTIFIED BY '$MYSQL_HORIZON_PASS'; FLUSH PRIVILEGES;" | mysql -h $MYSQL_HOST -u root -p$MYSQL_ROOT_PASS

#sed -e "s,999888777666,$SERVICE_TOKEN,g" local_settings.py.tmpl > local_settings.py
#sed -e "s,%MYSQL_HOST%,$MYSQL_HOST,g" -i local_settings.py
#sed -e "s,%MYSQL_HORIZON_PASS%,$MYSQL_HORIZON_PASS,g" -i local_settings.py
#sed -e "s,%KEYSTONE_IP%,$KEYSTONE_IP,g" -i local_settings.py
#
#cp local_settings.py /etc/openstack-dashboard/local_settings.py
#/usr/share/openstack-dashboard/dashboard/manage.py syncdb
