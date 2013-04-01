#!/usr/bin/env bash

TOP_DIR=$(pwd)
set -ex
source $TOP_DIR/settings
source $TOP_DIR/functions

setup_develop $KEYSTONECLIENT_DIR 
setup_develop $GLANCECLIENT_DIR 
setup_develop $CINDERCLIENT_DIR 
setup_develop $QUANTUMCLIENT_DIR 
setup_develop $NOVACLIENT_DIR 

if [[ $CONTROLLER_NODE = "True" ]]; then
    setup_develop $KEYSTONE_DIR 
    setup_develop $GLANCE_DIR 
    setup_develop $CINDER_DIR 
    setup_develop $NOVA_DIR 
    setup_develop $QUANTUM_DIR 
    #setup_develop $NOVNC_DIR 
    setup_develop $HORIZON_DIR 
fi
if [[ $NETWORK_NODE = "True" ]]; then
    setup_develop $QUANTUM_DIR 
fi
if [[ $COMPUTE_NODE = "True" ]]; then
    setup_develop $NOVA_DIR 
    setup_develop $QUANTUM_DIR 
fi
