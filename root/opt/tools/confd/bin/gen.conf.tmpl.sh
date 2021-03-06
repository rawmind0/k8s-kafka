#!/usr/bin/env bash

POD_NAME=${POD_NAME:-$HOSTNAME}
POD_NAMESPACE=${POD_NAMESPACE:-"default"}
RC_NAME=${RC_NAME:-$(echo $HOSTNAME | cut -d"-" -f1)}

KAFKA_HEAP_OPTS=${JVMFLAGS:-"-Xmx1G -Xms1G"}
KAFKA_ADVERTISE_PORT=${KAFKA_ADVERTISE_PORT:-"9092"}
KAFKA_DELETE_TOPICS=${KAFKA_DELETE_TOPICS:-"false"}
KAFKA_LISTENER=${KAFKA_LISTENER:-"PLAINTEXT://0.0.0.0:"${KAFKA_ADVERTISE_PORT}}
KAFKA_LOG_DIRS=${KAFKA_LOG_DIRS:-${SERVICE_HOME}"/logs"}
KAFKA_LOG_FILE=${KAFKA_LOG_FILE:-${KAFKA_LOG_DIRS}"/kafkaServer.out"}
KAFKA_LOG_RETENTION_HOURS=${KAFKA_LOG_RETENTION_HOURS:-"168"}
KAFKA_NUM_PARTITIONS=${KAFKA_NUM_PARTITIONS:-"1"}
KAFKA_ZK_SERVICE=${KAFKA_ZK_SERVICE:-"default/zookeeper"}
KAFKA_ZK_NAMESPACE=$( echo ${KAFKA_ZK_SERVICE} | cut -d"/" -f1 )
KAFKA_ZK_NAME=$( echo ${KAFKA_ZK_SERVICE} | cut -d"/" -f2 )
KAFKA_ZK_PORT=${KAFKA_ZK_PORT:-"2181"}
KAFKA_EXT_IP=${KAFKA_EXT_IP:-""}
LABEL_ID=".metadata.labels.kafkaid"

if [ "$ADVERTISE_PUB_IP" == "true" ]; then
    KAFKA_ADVERTISE_IP='{{$data.status.hostIP}}'
else
    KAFKA_ADVERTISE_IP='{{$data.status.podIP}}'
fi
KAFKA_ADVERTISE_LISTENER=${KAFKA_ADVERTISE_LISTENER:-"PLAINTEXT://"${KAFKA_ADVERTISE_IP}":"${KAFKA_ADVERTISE_PORT}}

cat << EOF > ${SERVICE_VOLUME}/confd/etc/conf.d/server.properties.toml
[template]
src = "server.properties.tmpl"
dest = "${SERVICE_HOME}/config/server.properties"
owner = "${SERVICE_USER}"
mode = "0644"
keys = [
  "/"
]

reload_cmd = "${SERVICE_HOME}/bin/kafka-service.sh restart"
EOF

cat << EOF > ${SERVICE_VOLUME}/confd/etc/templates/server.properties.tmpl
############################# Server Basics #############################
{{ \$data := json (getv "/pods/${POD_NAMESPACE}/${POD_NAME}") -}}
broker.id={{\$data${LABEL_ID}}}
############################# Socket Server Settings #############################
listeners=${KAFKA_LISTENER}
advertised.listeners=${KAFKA_ADVERTISE_LISTENER}
num.network.threads=3
num.io.threads=8
socket.send.buffer.bytes=102400
socket.receive.buffer.bytes=102400
socket.request.max.bytes=104857600
############################# Log Basics #############################
log.dirs=${KAFKA_LOG_DIRS}
num.partitions=${KAFKA_NUM_PARTITIONS}
num.recovery.threads.per.data.dir=1
delete.topic.enable=${KAFKA_DELETE_TOPICS}
############################# Log Flush Policy #############################
#log.flush.interval.messages=10000
#log.flush.interval.ms=1000
############################# Log Retention Policy #############################
log.retention.hours=${KAFKA_LOG_RETENTION_HOURS}
#log.retention.bytes=1073741824
log.segment.bytes=1073741824
log.retention.check.interval.ms=300000
log.cleaner.enable=true
############################# Connect Policy #############################
{{ \$data := json (getv "/services/endpoints/${KAFKA_ZK_NAMESPACE}/${KAFKA_ZK_NAME}") -}}
zookeeper.connect={{- range \$i, \$subset := \$data.subsets -}}
  {{- range \$j, \$address := \$subset.addresses -}}
    {{- if \$j -}}
      ,
    {{- end -}}
    {{\$address.ip}}
    {{- range \$subset.ports -}}
      {{- if eq .name "zk-client" -}}
        :{{.port}}
      {{- end -}}
    {{- end -}}
{{- end -}}
{{end}}
zookeeper.connection.timeout.ms=6000
EOF