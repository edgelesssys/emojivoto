#!/usr/bin/env bash

if [ $# -lt 2 ];
then
    echo "Usage: $0 <az resource group> <az cluster name>"
    exit 1
fi

RESOURCEGROUP=$1
CLUSTERNAME=$2

okStatus="\e[92m\u221A\e[0m"
warnStatus="\e[93m\u203C\e[0m"
failStatus="\e[91m\u00D7\e[0m"

helm uninstall -n emojivoto emojivoto
kubectl delete ns emojivoto
helm uninstall -n marblerun marblerun-coordinator
kubectl delete ns marblerun
helm uninstall -n kube-system nginx-ingress
linkerd install --ignore-cluster | kubectl delete -f -

read -p "Do you want to delete the cluster? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]
then
    # delete cluster
    echo "Deleting cluster..."
    az aks delete --resource-group "$RESOURCEGROUP" --name "$CLUSTERNAME"
    echo -e "[$okStatus] Done"
fi