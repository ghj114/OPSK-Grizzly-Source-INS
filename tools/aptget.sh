#!/usr/bin/env bash

source settings
source functions

apt-get update
apt-get upgrade

# 0. setup source.list and install -y general packages
apt-get install -y bridge-utils pep8 pylint python-pip screen unzip wget psmisc git 
apt-get install -y lsof openssh-server openssl vim-nox locate python-virtualenv 
apt-get install -y python-unittest2 iputils-ping wget curl tcpdump euca2ools tar python-netaddr
apt-get install -y python-cmd2 # dist:precise

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

# 6. install -y quantumclient and quantum
apt-get install -y ebtables iptables iputils-ping iputils-arping 
apt-get install -y sudo python-boto python-iso8601 python-paste python-routes python-suds python-netaddr python-pastedeploy python-greenlet
apt-get install -y python-kombu python-eventlet python-sqlalchemy python-mysqldb python-pyudev python-qpid # dist:precise
apt-get install -y dnsmasq-base dnsmasq-utils # for dhcp_release only available in dist:oneiric,precise,quantal
apt-get install -y sqlite3 vlan

# 7. install -y nova-api nova-scheduler
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

apt-get install -y python-dateutil # nova-api
apt-get install -y python-numpy # novnc
