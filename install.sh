# Controller NODE:

# 0. setup source.list and install general packages
apt-get install bridge-utils pep8 pylint python-pip screen unzip wget psmisc git 
apt-get install lsof openssh-server openssl vim-nox locate python-virtualenv 
apt-get install python-unittest2 iputils-ping wget curl tcpdump euca2ools tar python-netaddr
apt-get install python-cmd2 # dist:precise

# 1. install mysql:
lib/mysql.sh

# 2. install rabbit-server:
apt-get install -y rabbitmq-server
echo "rabbitmq install over!";sleep 1

tools/loaddown.sh 

tools/setup.sh

# 3. install keystoneclient and keystone
apt-get install python-setuptools python-dev python-lxml python-pastescript python-pastedeploy python-paste sqlite3
apt-get install python-pysqlite2 python-sqlalchemy python-mysqldb python-webob python-greenlet python-routes libldap2-dev libsasl2-dev python-bcrypt

#install_keystoneclient
install_keystone
configure_keystoneclient
configure_novaclient

# 4. install glanceclient and glance
apt-get install gcc libxml2-dev python-dev python-eventlet python-routes python-greenlet python-argparse # dist:oneiric
apt-get install python-sqlalchemy python-wsgiref python-pastedeploy python-xattr python-iso8601
install_glanceclient
install_glance
configure_glanceclient
configure_glance

# 5. install cinderclient and cinder
apt-get install tgt lvm2
install_cinderclient
install_cinder
configure_cinderclient
configure_cinder

# 6. install quantumclient and quantum
apt-get install btables iptables iputils-ping iputils-arping 
apt-get install sudo python-boto python-iso8601 python-paste python-routes python-suds python-netaddr python-pastedeploy python-greenlet
apt-get install python-kombu python-eventlet python-sqlalchemy python-mysqldb python-pyudev python-qpid # dist:precise
apt-get install dnsmasq-base dnsmasq-utils # for dhcp_release only available in dist:oneiric,precise,quantal
apt-get install sqlite3 vlan

install_quantum_agent_packages # if is_service_enabled q-agt
install_quantumclient
install_quantum
install_quantum_third_party
setup_quantumclient
setup_quantum

# 7. install nova-api nova-scheduler
apt-get install dnsmasq-base dnsmasq-utils # for dhcp_release only available in dist:oneiric,precise,quantal
apt-get install kpartx parted arping # only available in dist:natty
apt-get install iputils-arping # only available in dist:oneiric
apt-get install python-xattr # needed for glance which is needed for nova --- this shouldn't be here
apt-get install python-lxml # needed for glance which is needed for nova --- this shouldn't be here
apt-get install gawk iptables ebtables sqlite3 sudo kvm libvirt-bin # NOPRIME
apt-get install libjs-jquery-tablesorter # Needed for coverage html reports
apt-get install vlan curl genisoimage # required for config_drive
apt-get install socat # used by ajaxterm
apt-get install python-mox python-paste python-migrate python-gflags python-greenlet python-libvirt python-libxml2 python-routes python-netaddr
apt-get install python-numpy # used by websockify for spice console
apt-get install python-pastedeploy python-eventlet python-cheetah python-carrot python-tempita python-sqlalchemy python-suds python-lockfile python-m2crypto

apt-get install python-dateutil # nova-api
apt-get install python-numpy # novnc

install_novaclient
install_nova
git_clone $NOVNC_REPO $NOVNC_DIR $NOVNC_BRANCH
configure_novaclient
cleanup_nova
configure_nova

                 

# 8. install horizon
install_horizon
configure_horizon

