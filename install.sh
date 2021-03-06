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

# 6. install NETWORK NODE: quantumclient and quantum
lib/quantum.sh

# 7. install nova-api nova-scheduler
lib/nova.sh
lib/quantum.sh

# 8. install horizon
lib/horizon.sh

# 9. install nova-compute.sh
lib/nova.sh
lib/quantum.sh


