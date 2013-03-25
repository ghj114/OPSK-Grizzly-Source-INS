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
lib/glance.sh

# 5. install cinderclient and cinder
lib/cinder.sh

# 6. install quantumclient and quantum
install_quantum_agent_packages # if is_service_enabled q-agt
install_quantumclient
install_quantum
install_quantum_third_party
setup_quantumclient
setup_quantum

# 7. install nova-api nova-scheduler
lib/nova-controller.sh
lib/quantum-server.sh

# 8. install horizon
install_horizon
configure_horizon

