#!/usr/bin/env bash

helm uninstall -n emojivoto emojivoto
kubectl delete ns emojivoto
helm uninstall -n marblerun marblerun
kubectl delete ns marblerun
if command -v linkerd &> /dev/null
then
    linkerd install --ignore-cluster | kubectl delete -f -
fi
