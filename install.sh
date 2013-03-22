# Controller NODE:

TOP_DIR=$(cd $(dirname "$0") && pwd)

tools/aptget.sh
tools/loaddown.sh 
tools/setup.sh

# 1. install mysql:
lib/mysql.sh

# 2. install rabbit-server:
apt-get install -y rabbitmq-server
echo "rabbitmq install over!";sleep 1

# 3. install keystone
lib/keystone.sh

# 4. install glanceclient and glance
install_glanceclient
install_glance
configure_glanceclient
configure_glance

# 5. install cinderclient and cinder
install_cinderclient
install_cinder
configure_cinderclient
configure_cinder

# 6. install quantumclient and quantum
install_quantum_agent_packages # if is_service_enabled q-agt
install_quantumclient
install_quantum
install_quantum_third_party
setup_quantumclient
setup_quantum

# 7. install nova-api nova-scheduler
install_novaclient
install_nova
git_clone $NOVNC_REPO $NOVNC_DIR $NOVNC_BRANCH
configure_novaclient
cleanup_nova
configure_nova

                 

# 8. install horizon
install_horizon
configure_horizon

