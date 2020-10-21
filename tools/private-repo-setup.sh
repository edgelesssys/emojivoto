#!/bin/bash

kubectl create ns emojivoto
kubectl -n emojivoto create secret generic regcred \
--from-file=.dockerconfigjson=$HOME/.docker/config.json \
--type=kubernetes.io/dockerconfigjson