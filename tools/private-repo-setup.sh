#!/bin/bash

if [[ $# < 1 ]]
then
    echo "Usage: $0 <namespace>"
    exit 1
fi

kubectl create ns $1
kubectl -n $1 create secret generic regcred \
--from-file=.dockerconfigjson=$HOME/.docker/config.json \
--type=kubernetes.io/dockerconfigjson