#!/usr/bin/env bash

TOP_DIR=$(pwd)
set -ex
source $TOP_DIR/settings
source $TOP_DIR/functions

#echo 'deb http://ubuntu-cloud.archive.canonical.com/ubuntu precise-updates/grizzly main' > /etc/apt/sources.list.d/grizzly.list
# apt-get install ubuntu-cloud-keyring

apt-get update
apt-get upgrade

# 0. install -y general packages

apt-get install -y bridge-utils pep8 pylint python-pip screen unzip wget psmisc git 
apt-get install -y lsof openssh-server openssl vim-nox locate python-virtualenv 
apt-get install -y python-unittest2 iputils-ping wget curl tcpdump euca2ools tar python-netaddr
apt-get install -y python-cmd2 # dist:precise

if [[ $CONTROLLER_NODE = "True" ]]; then
# 2. install -y rabbit-server:
    apt-get install -y rabbitmq-server

# 3. install -y keystoneclient and keystone
    apt-get install -y python-setuptools python-dev python-lxml python-pastescript python-pastedeploy python-paste sqlite3
    apt-get install -y python-pysqlite2 python-sqlalchemy python-mysqldb python-webob python-greenlet python-routes libldap2-dev libsasl2-dev python-bcrypt

# 4. install -y glanceclient and glance
    apt-get install -y gcc libxml2-dev python-dev python-eventlet python-routes python-greenlet python-argparse # dist:oneiric
    apt-get install -y python-sqlalchemy python-wsgiref python-pastedeploy python-xattr python-iso8601

# 5. install -y cinderclient and cinder
    apt-get install -y tgt lvm2


# 7. install -y nova
    apt-get install -y dnsmasq-base dnsmasq-utils # for dhcp_release only available in dist:oneiric,precise,quantal
    apt-get install -y kpartx parted arping # only available in dist:natty
    apt-get install -y iputils-arping # only available in dist:oneiric
    apt-get install -y python-xattr # needed for glance which is needed for nova --- this shouldn't be here
    apt-get install -y python-lxml # needed for glance which is needed for nova --- this shouldn't be here
    apt-get install -y gawk iptables ebtables sqlite3 sudo kvm libvirt-bin # NOPRIME
    apt-get install -y libjs-jquery-tablesorter # Needed for coverage html reports
    apt-get install -y vlan curl genisoimage # required for config_drive
    apt-get install -y socat # used by ajaxterm
    apt-get install -y python-mox python-paste python-migrate python-gflags python-greenlet python-libvirt python-libxml2 python-routes python-netaddr
    apt-get install -y python-numpy # used by websockify for spice console
    apt-get install -y python-pastedeploy python-eventlet python-cheetah python-carrot python-tempita python-sqlalchemy python-suds python-lockfile python-m2crypto
    apt-get install -y python-boto python-kombu python-feedparser python-iso8601 python-qpid # dist:precise

    apt-get install -y python-dateutil # nova-api
    apt-get install -y python-numpy # novnc


# 8. install -y horizon
    apt-get install -y apache2  # NOPRIME
    apt-get install -y libapache2-mod-wsgi  # NOPRIME
    apt-get install -y python-beautifulsoup python-dateutil python-paste python-pastedeploy python-anyjson python-routes python-xattr python-sqlalchemy
    apt-get install -y python-webob python-kombu pylint pep8 python-eventlet python-nose python-sphinx python-mox python-kombu python-coverage python-cherrypy3 # why?
    apt-get install -y python-migrate nodejs nodejs-legacy # dist:quantal
    apt-get install -y python-netaddr
    apt-get install -y nodejs
fi


if [[ $COMPUTE_NODE = "True" ]]; then
    apt-get install -y lvm2 open-iscsi open-iscsi-utils genisoimage sysfsutils sg3-utils # nova-compute
    apt-get install python-dev libssl-dev python-pip git-core libxml2-dev libxslt-dev
    apt-get install libmysqld-dev
    apt-get install -y gawk iptables ebtables sqlite3 sudo kvm libvirt-bin # NOPRIME
    apt-get install -y python-mox python-paste python-migrate python-gflags python-greenlet python-libvirt python-libxml2 python-routes python-netaddr
fi


if [[ $NETWORK_NODE = "True" ]]; then
    apt-get install -y openvswitch-switch openvswitch-datapath-dkms
# 6. install -y quantumclient and quantum
    apt-get install -y ebtables iptables iputils-ping iputils-arping 
    apt-get install -y sudo python-boto python-iso8601 python-paste python-routes python-suds python-netaddr python-pastedeploy python-greenlet
    apt-get install -y python-kombu python-eventlet python-sqlalchemy python-mysqldb python-pyudev python-qpid # dist:precise
    apt-get install -y dnsmasq-base dnsmasq-utils # for dhcp_release only available in dist:oneiric,precise,quantal
    apt-get install -y sqlite3 vlan
fi
