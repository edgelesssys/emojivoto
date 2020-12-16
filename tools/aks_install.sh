#!/usr/bin/env bash

if ! command -v az &> /dev/null
then
    echo "Azure CLI could not be found"
    echo "See Installation Guide @ https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit
fi


if [ $# -lt 5 ];
then
    echo "Usage: $0 <az subscriptionID> <az resource group> <az cluster name> <az cluster #nodes> <domain>"
    exit 1
fi

SUBSCRIPTIONID=$1
RESOURCEGROUP=$2
CLUSTERNAME=$3
NODES=$4
DOMAIN=$5

UNIQUE_SUFFIX="$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 16 | head -n 1)"
MARBLERUN_DNSNAME="marblerun-$UNIQUE_SUFFIX"
EMOJIVOTO_DNSNAME="emojivoto-$UNIQUE_SUFFIX"

okStatus="\e[92m\u221A\e[0m"
warnStatus="\e[93m\u203C\e[0m"
failStatus="\e[91m\u00D7\e[0m"

# exit if command fails
set -e

#
# 1. Azure
#

# set azure account
echo "[*] Setting Azure subscription..."
az account set --subscription "$SUBSCRIPTIONID" > /dev/null

read -p "Do you want to create the cluster \"$CLUSTERNAME\"? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]
then
    # create cluster
    echo "Creating cluster..."
    az aks create \
        --resource-group "$RESOURCEGROUP" \
        --name "$CLUSTERNAME" \
        --node-vm-size Standard_DC2s_v2 \
        --node-count "$NODES" \
        --enable-addon confcom \
        --network-plugin azure \
        --vm-set-type VirtualMachineScaleSets \
        --aks-custom-headers usegen2vm=true > /dev/null
    echo -e "[$okStatus] Done"
fi

# get cluster credentials
echo "[*] Getting aks credentials"
az aks get-credentials --resource-group "$RESOURCEGROUP" --name "$CLUSTERNAME"
echo -e "[$okStatus] Done"


#
# 2. linkerd
#

# Check if linkerd should be deployed
read -p "Do you want to deploy with linkerd? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]
then
    if ! command -v linkerd &> /dev/null
    then
        echo "linkerd CLI could not be found"
        echo "See Installation Guide @ https://linkerd.io/2/getting-started/"
        exit
    fi
    LINKERD=true

    linkerd_execute() {
        eval $@ >/dev/null 2>/tmp/linkerd_output
        if [ $? -eq 0 ]; then
            echo -e "[$okStatus] '$@' succeeded"
        else
            echo -e "[$failStatus] '$@' failed"
            echo -en "\e[91m"
            cat /tmp/linkerd_output
            echo -en "\e[0m"
            exit
        fi
    }

    linkerd_execute "linkerd check --pre"
    linkerd_execute "linkerd install | kubectl apply -f -"
    linkerd_execute "linkerd check"

fi

#
# 3. Deploy Marblerun+DNS and Ingress-Controller+DNS
#

# install ingress controller
echo "[*] Installing nginx-ingress-controller..."
helm install --namespace kube-system --set rbac.create=true --set controller.stats.enabled=true --set controller.extraArgs.enable-ssl-passthrough=""  --set controller.replicaCount=2 --set controller.nodeSelector."beta\.kubernetes\.io/os"=linux  --set defaultBackend.nodeSelector."beta\.kubernetes\.io/os"=linux nginx-ingress ingress-nginx/ingress-nginx > /dev/null
echo -e "[$okStatus] Done"

# install coordinator
echo "[*] Installing marblerun-coordinator..."
kubectl create ns marblerun > /dev/null
if [ "$LINKERD" = true ]
then
    kubectl annotate ns marblerun linkerd.io/inject=enabled > /dev/null
fi
helm install marblerun-coordinator edgeless/marblerun-coordinator -n marblerun --set coordinator.hostname="$MARBLERUN_DNSNAME.$DOMAIN" > /dev/null
echo -e "[$okStatus] Done"


# set dns for coordinator
echo "[*] Setting DNS for the marblerun-coordinator"
IP=""
echo -n "[*] Waiting for LoadBalancer to assign a public IP..."
until [[ $IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]];
do
    IP=$(kubectl -n marblerun get svc coordinator-client-api -o jsonpath="{.status.loadBalancer.ingress[0].ip}")
    echo -n "."
    sleep 3
done
PUBLICIPID=$(az network public-ip list --query "[?ipAddress!=null]|[?contains(ipAddress, '$IP')].[id]" --output tsv)
az network public-ip update --ids $PUBLICIPID --dns-name "$MARBLERUN_DNSNAME" > /dev/null
MARBLERUN=""
until [[ $MARBLERUN == "$MARBLERUN_DNSNAME."* ]]
do
    MARBLERUN="$(az network public-ip show --ids $PUBLICIPID --query "[dnsSettings.fqdn]" --output tsv):25555"
    echo -n "."
    sleep 3
done
echo ""
echo -e "[$okStatus] Done"


# set dns for ingress controller
echo "[*] Setting DNS for the ingress"
IP=""
echo -n "[*] Waiting for LoadBalancer to assign a public IP..."
until [[ $IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]];
do
    IP=$(kubectl -n kube-system get svc nginx-ingress-ingress-nginx-controller -o jsonpath="{.status.loadBalancer.ingress[0].ip}")
    echo -n "."
    sleep 3
done
PUBLICIPID=$(az network public-ip list --query "[?ipAddress!=null]|[?contains(ipAddress, '$IP')].[id]" --output tsv)
az network public-ip update --ids $PUBLICIPID --dns-name "$EMOJIVOTO_DNSNAME" > /dev/null
EMOJIVOTO=""
until [[ $EMOJIVOTO == "$EMOJIVOTO_DNSNAME."* ]]
do
    EMOJIVOTO="$(az network public-ip show --ids $PUBLICIPID --query "[dnsSettings.fqdn]" --output tsv)"
    echo -n "."
    sleep 3
done
echo ""
echo -e "[$okStatus] Done"


#
# 4. Deploy emojivoto
#

# set manifest
echo "[*] Setting the manifest"
rm -f coordinator-era.json
wget -q https://github.com/edgelesssys/marblerun/releases/latest/download/coordinator-era.json
era -c coordinator-era.json -h $MARBLERUN -o marblerun.crt > /dev/null
manifest=$(cat "tools/manifest.json" | sed "s/localhost/$EMOJIVOTO/g")
curl --fail --silent --show-error --cacert marblerun.crt --data-binary "$manifest" https://$MARBLERUN/manifest
echo -e "[$okStatus] Done"

# install emojivoto
echo "[*] Installing emojivoto"
kubectl create ns emojivoto > /dev/null
if [ "$LINKERD" = true ]
then
    kubectl annotate ns emojivoto linkerd.io/inject=enabled > /dev/null
fi
helm install emojivoto ./kubernetes \
    -f ./kubernetes/sgx_values.yaml \
    -n emojivoto > /dev/null
echo -e "[$okStatus] Done"

# waiting for emojivoto to come up
echo -n "[*] Waiting for emojivoto to be ready..."
WEBSTATE=""
until [[ $WEBSTATE == "Running" ]]
do
    WEBSTATE=$(kubectl -n emojivoto get pod web-0 -o jsonpath="{.status.phase}")
    echo -n "."
    sleep 3
done
echo ""
echo -e "[$okStatus] Done"

# set ingress for emojivoto
echo "[*] Setting ingress route for emojivoto"
template=$(cat "tools/emojivoto_ingress.yaml.template" | sed "s/{{DOMAIN}}/$EMOJIVOTO/g")
echo "$template" | kubectl -n emojivoto apply -f - > /dev/null
echo -e "[$okStatus] Done"

#
# 5. Finish
#

echo -e "[$okStatus] All done and ready to roll!🚀"
echo -e "[$okStatus] Install ./marblerun.crt in the Trusted-Root-CA store of your browser"
echo -e "[$okStatus] Visit https://$EMOJIVOTO"

if [ "$LINKERD" = true ]
then
    echo -e "[$okStatus] Run 'linkerd dashboard' for access to the linkerd dashboard"
fi
