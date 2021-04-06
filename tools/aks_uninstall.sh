#!/usr/bin/env bash

okStatus="\e[92m\u221A\e[0m"
warnStatus="\e[93m\u203C\e[0m"
failStatus="\e[91m\u00D7\e[0m"

helm uninstall -n emojivoto emojivoto
kubectl delete ns emojivoto
helm uninstall -n marblerun marblerun-coordinator
kubectl delete ns marblerun
helm uninstall -n kube-system nginx-ingress
linkerd install --ignore-cluster | kubectl delete -f -
