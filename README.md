[![](https://images.microbadger.com/badges/image/rawmind/k8s-kafka.svg)](https://microbadger.com/images/rawmind/k8s-kafka "Get your own image badge on microbadger.com")

k8s-kafka
==============

This image is the kafka dynamic conf for rancher. It comes from [rawmind/k8s-tools][k8s-tools].

## Build

```
docker build -t rawmind/k8s-kafka:<version> .
```

## Versions

- `0.11.0.0` [(Dockerfile)](https://github.com/rawmind0/k8s-kafka/blob/0.11.0.0/README.md)
- `0.10.2.0-1` [(Dockerfile)](https://github.com/rawmind0/k8s-kafka/blob/0.10.2.0-1/README.md)
- `0.10.0.0-5` [(Dockerfile)](https://github.com/rawmind0/k8s-kafka/blob/0.10.0.0-5/README.md)


## Usage

This image has to be run as a complement of [rawmind/alpine-kafka][alpine-kafka], and it configures /opt/tools volume. It scans from k8s etcd, for a zookeeper services endpoints and generates /opt/kafka/config/server.properties dynamicly.

/opt/tools/scripts/kafka-service.sh scripts, generates and set a broker id for every node. It also checks a minimal kafka quorum before to reboot the kafka node on scale the rc.


[alpine-kafka]: https://github.com/rawmind0/alpine-kafka
[k8s-tools]: https://github.com/rawmind0/rancher-tools