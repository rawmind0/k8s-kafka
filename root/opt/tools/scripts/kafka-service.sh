#!/usr/bin/env bash

CONF_NODE_IP=${CONF_NODE_IP:-$(fping -A etcd.kubernetes. | grep alive | cut -d" " -f1)}
MONIT_SERVICE_NAME=kafka-service
CONF_HOME=${CONF_HOME:-"${SERVICE_VOLUME}/confd"}
CONF_LOG=${CONF_LOG:-"${CONF_HOME}/log/confd.log"}
export CONF_URL="http://${CONF_NODE_IP}:2379/v2/keys/registry"
export JQ_BIN=${JQ_BIN:-${SERVICE_VOLUME}"/scripts/jq -r"}
export KUBE_TOKEN=$(</var/run/secrets/kubernetes.io/serviceaccount/token)
export KUBE_LABEL_ID="/metadata/labels/kafkaid"
export LABEL_ID=".metadata.labels.kafkaid"
export POD_NAME=${POD_NAME:-$HOSTNAME}
export POD_NAMESPACE=${POD_NAMESPACE:-"default"}
export RC_NAME=${RC_NAME:-$(echo $HOSTNAME | cut -d"-" -f1)}
export RC_LOCK_NAME=${RC_LOCK_NAME:-${RC_NAME}"_KAFKALOCK"}

function log {
        echo `date` $ME - $@ >> ${CONF_LOG} 2>&1
}

function myId {
    curl -Ss ${CONF_URL}/pods/${POD_NAMESPACE}/${HOSTNAME} | ${JQ_BIN} .node.value | ${JQ_BIN} ${LABEL_ID}
}

function putId {
    id=$(newId)
    new_id=$(cat <<EOF
[
 {
 "op": "add", "path": "${KUBE_LABEL_ID}", "value": "${id}"
 }
]
EOF
)
    resp=$(curl -Ss --insecure --header "Authorization: Bearer $KUBE_TOKEN" --request PATCH --data "$new_id" -H "Content-Type:application/json-patch+json" https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_PORT_443_TCP_PORT/api/v1/namespaces/${POD_NAMESPACE}/pods/${HOSTNAME})
    rc=$(echo $resp | ${JQ_BIN} .kind)

    if [ "X$rc" == "XStatus" ]; then
        id=$resp
    fi

    echo $id
}

function getLock {
    log "[ Getting ${RC_LOCK_NAME} ... ]" 
    resp=$(curl -Ss ${CONF_URL}/controllers/${POD_NAMESPACE}/${RC_LOCK_NAME}?prevExist=false -XPUT -d value=${HOSTNAME} -d ttl=30)
    error=$(echo $resp | ${JQ_BIN} .errorCode)
    counter=0
    max=12
    step=5

    while [ "X$error" != "Xnull" ] && [ $counter -lt $max ]; do
        log "[ Waiting to get ${RC_LOCK_NAME} ... ] "
        sleep $step
        resp=$(curl -Ss ${CONF_URL}/controllers/${POD_NAMESPACE}/${RC_LOCK_NAME}?prevExist=false -XPUT -d value=${HOSTNAME} -d ttl=30)
        error=$(echo $resp | ${JQ_BIN} .errorCode)
        log "errorCode: $error - message: $(echo $resp | ${JQ_BIN} .message) - cause: $(echo $resp | ${JQ_BIN} .cause) "
        counter=$(expr $counter + 1)
    done

    if [ "X$error" != "Xnull" ]; then
        log "[ Error getting ${RC_LOCK_NAME} ] - Timeout"
        exit 1
    fi
}

function releaseLock {
    log "[ Releasing ${RC_LOCK_NAME} ... ]"
    resp=$(curl -Ss ${CONF_URL}/controllers/${POD_NAMESPACE}/${RC_LOCK_NAME}?prevValue=${HOSTNAME} -XDELETE)
    error=$(echo $resp | ${JQ_BIN} .errorCode)

    if [ "X$error" != "Xnull" ]; then
        log "[ Error releasing ${RC_LOCK_NAME} ... ]"
        log "errorCode: $error - message: $(echo $resp | ${JQ_BIN} .message) - cause: $(echo $resp | ${JQ_BIN} .cause) "
    fi
}

function newId {
    getLock

    for id in {1..255}; do
        for i in $(curl -Ss ${CONF_URL}/services/endpoints/${POD_NAMESPACE}/${RC_NAME} | ${JQ_BIN} .node.value | ${JQ_BIN} .subsets[0].addresses[].targetRef.name) ; do
            g=$(curl -Ss ${CONF_URL}/pods/${POD_NAMESPACE}/${i} | ${JQ_BIN} .node.value | ${JQ_BIN} ${LABEL_ID})
            if [ "X$id" == "X$g" ]; then
                rc="exists"
                break
            fi
        done
        if [ "X$rc" !=  "Xexists" ]; then
            break
        else
            rc="new"
        fi
    done

    releaseLock

    echo $id
}

function waitDeploy {
    log "[ Waiting replicas to be started ... ]"

    current_rep=$(curl -Ss ${CONF_URL}/controllers/${POD_NAMESPACE}/${RC_NAME} | ${JQ_BIN} .node.value | ${JQ_BIN} .status.replicas)
    wanted_rep=$(curl -Ss ${CONF_URL}/controllers/${POD_NAMESPACE}/${RC_NAME} | ${JQ_BIN} .node.value | ${JQ_BIN} .spec.replicas)

    while [ ${current_rep} -ne ${wanted_rep} ]; do
        log "${current_rep} of ${wanted_rep} started replicas....waiting..."
        sleep 3
    done
}

function waitIds {
    log "[ Waiting for all pods has zkid ... ]"

    wanted_rep=$(curl -Ss ${CONF_URL}/controllers/${POD_NAMESPACE}/${RC_NAME} | ${JQ_BIN} .node.value | ${JQ_BIN} .spec.replicas)

    while [ ${wanted_rep} -ne ${counter} ]; do
        counter=0
        for i in $(curl -Ss ${CONF_URL}/services/endpoints/${POD_NAMESPACE}/${RC_NAME} | ${JQ_BIN} .node.value | ${JQ_BIN} .subsets[0].addresses[].targetRef.name) ; do
            id=$(curl -Ss ${CONF_URL}/pods/${POD_NAMESPACE}/${i} | ${JQ_BIN} .node.value | ${JQ_BIN} ${LABEL_ID})
            if [ "$id" != "null"]; then
                counter=$(expr $counter + 1)
            fi
        done
        log "${counter} of ${wanted_rep} pods has id"
    done

}

function getLeader {
    node_leader="none"

    for i in $(curl -Ss ${CONF_URL}/services/endpoints/${POD_NAMESPACE}/${RC_NAME} | ${JQ_BIN} .node.value | ${JQ_BIN} .subsets[0].addresses[].ip)  
    do 
        node_role=$(echo stat | nc ${i}:2181 | grep -w Mode: | cut -d' ' -f2)
        if [ "${node_role}" == "leader" ]; then
            node_leader=${i}
            break
        fi
    done

    echo $node_leader
}

function nodeStatus {
    echo ruok | nc $HOSTNAME:2181
}

function nodeRestart {
    log "[ Restarting $MONIT_SERVICE_NAME ... ]"
    wanted_rep=$(curl -Ss ${CONF_URL}/controllers/${POD_NAMESPACE}/${RC_NAME} | ${JQ_BIN} .node.value | ${JQ_BIN} .spec.replicas)

    if [ "$(nodeStatus)" == "imok" ]; then
        leader=$(getLeader)

        if [ "$leader" != "none" ]; then
            synced_follow=$(echo mntr | nc ${leader}:2181 | grep -w zk_synced_followers | cut -f2)
         
            while [ ${synced_follow} -le 1 ]; do
                log "Only ${synced_follow} synced follower. Waiting ..."
                sleep 5
                synced_follow=$(echo mntr | nc ${leader}:2181 | grep -w zk_synced_followers | cut -f2)
            done
            log "${synced_follow} synced follower. Restarting ..."
        fi
    fi

    /opt/monit/bin/monit restart $MONIT_SERVICE_NAME
}

function bootstrapKafka {
    waitDeploy
    waitIds

    myid=$(myId)
    counter=0
    while [ "X$myid" == "Xnull" ] && [ $counter -lt 5 ]; do
        log "[ Getting new kafka id ... ] "
        myid=$(putId)
        counter=$(expr $counter + 1)
    done

    if [ "X$myid" == "Xnull" ]; then
        log "[ Error getting kafka id ] - Exiting "
        exit 1
    else
        echo $myid
    fi
}

case "$1" in
        "bootstrap")
            bootstrapKafka >> ${CONF_LOG} 2>&1
        ;;
        "restart")
            #nodeRestart >> ${CONF_LOG} 2>&1
            /opt/monit/bin/monit restart $MONIT_SERVICE_NAME
        ;;
        *) echo "Usage: $0 restart|bootstrap"
        ;;

esac

