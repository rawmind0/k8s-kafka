#!/usr/bin/env bash

function log {
        echo `date` $ME - $@ >> ${CONF_LOG} 2>&1
}

function checkNetwork {
    log "[ Checking container ip... ]"
    a="`ip a s dev eth0 &> /dev/null; echo $?`"
    while  [ $a -eq 1 ];
    do
        a="`ip a s dev eth0 &> /dev/null; echo $?`" 
        sleep 1
    done

    log "[ Checking container connectivity... ]"
    b="`fping -c 1 kubernetes. &> /dev/null; echo $?`"
    while [ $b -eq 1 ]; 
    do
        b="`fping -c 1 kubernetes. &> /dev/null; echo $?`"
        sleep 1 
    done
}

function serviceBootstrap {
    log "[ Bootstraping ${SERVICE_NAME} template... ]"

    ${SERVICE_VOLUME}/scripts/kafka-service.sh bootstrap
}

function serviceTemplate {
    log "[ Checking ${CONF_NAME} template... ]"
    ${CONF_HOME}/bin/gen.conf.tmpl.sh
}

function serviceStart {
    checkNetwork
    serviceBootstrap
    serviceTemplate
    log "[ Starting ${CONF_NAME}... ]"
    /usr/bin/nohup ${CONF_INTERVAL} > ${CONF_HOME}/log/confd.log 2>&1 &
}

function serviceStop {
    log "[ Stoping ${CONF_NAME}... ]"
    /usr/bin/killall confd
}

function serviceRestart {
    log "[ Restarting ${CONF_NAME}... ]"
    serviceStop 
    serviceStart
    /opt/monit/bin/monit reload
}

CONF_NAME=confd
export CONF_HOME=${CONF_HOME:-"${SERVICE_VOLUME}/confd"}
export CONF_LOG=${CONF_LOG:-"${CONF_HOME}/log/confd.log"}
CONF_BIN=${CONF_BIN:-"${CONF_HOME}/bin/confd"}
CONF_BACKEND=${CONF_BACKEND:-"etcd"}
CONF_PREFIX=${CONF_PREFIX:-"/registry"}
export CONF_NODE_NAME=${CONF_NODE_NAME:-"etcd.kubernetes."}
export CONF_NODE_IP=$(fping -A ${CONF_NODE_NAME} | grep alive | cut -d" " -f1)
CONF_NODE=${CONF_NODE:-"${CONF_NODE_IP}:2379"}
CONF_INTERVAL=${CONF_INTERVAL:-"-watch"}
CONF_PARAMS=${CONF_PARAMS:-"-confdir /opt/tools/confd/etc -backend ${CONF_BACKEND} -prefix ${CONF_PREFIX} -node ${CONF_NODE}"}
CONF_INTERVAL="${CONF_BIN} ${CONF_INTERVAL} ${CONF_PARAMS}"

case "$1" in
        "start")
            serviceStart >> ${CONF_LOG} 2>&1
        ;;
        "stop")
            serviceStop >> ${CONF_LOG} 2>&1
        ;;
        "restart")
            serviceRestart >> ${CONF_LOG} 2>&1
        ;;
        *) echo "Usage: $0 restart|start|stop"
        ;;

esac
