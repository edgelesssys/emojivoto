#!/usr/bin/env bash
if [ $# -lt 1 ];
then
    echo "Usage: $0 <domain>"
    exit 1
fi


DOMAIN=$1

UNIQUE_SUFFIX="$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 16 | head -n 1)"
MARBLERUN_DNSNAME="marblerun-$UNIQUE_SUFFIX"
EMOJIVOTO_DNSNAME="emojivoto-$UNIQUE_SUFFIX"

okStatus="\e[92m\u221A\e[0m"
warnStatus="\e[93m\u203C\e[0m"
failStatus="\e[91m\u00D7\e[0m"

# exit if command fails
set -e



#
# 0. prerequisite
#
echo "[*] Checking prerequisite"

if ! command -v az &> /dev/null
then
    echo "[$failStatus] Azure CLI could not be found"
    echo "See Installation Guide @ https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    echo "See https://docs.microsoft.com/en-us/azure/confidential-computing/confidential-nodes-aks-get-started#installing-the-cli-pre-requisites"
    exit
fi

if ! command -v marblerun &> /dev/null
then
    echo "[$failStatus] Marblerun CLI could not be found"
    echo "See Installation Guide @ https://marblerun.sh/docs/getting-started/cli"
    exit
fi

if ! command -v era &> /dev/null
then
    echo "[$failStatus] era could not be found"
    echo "See Installation Guide https://github.com/edgelesssys/era#install"
    exit
fi

if ! command -v helm &> /dev/null
then
    echo "[$failStatus] helm could not be found"
    echo "See Installation Guide https://helm.sh/docs/intro/install/"
    exit
fi

if ! command -v curl &> /dev/null
then
    echo "[$failStatus] 'curl' could not be found"
    exit
fi

if ! command -v wget &> /dev/null
then
    echo "[$failStatus] 'wget' could not be found"
    exit
fi

# Check if linkerd should be deployed
read -p "Do you want to deploy with linkerd? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]
then
    if ! command -v linkerd &> /dev/null
    then
        echo "[$failStatus] linkerd CLI could not be found"
        echo "See Installation Guide @ https://linkerd.io/2/getting-started/"
        exit
    fi
    LINKERD=true
fi


#
# 1. linkerd
#

# Check if linkerd should be deployed
if [ "$LINKERD" = true ]
then
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
# 2. Deploy Marblerun+DNS and Ingress-Controller+DNS
#

# install ingress controller
echo "[*] Installing nginx-ingress-controller..."
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx > /dev/null
helm install --namespace kube-system --set rbac.create=true --set controller.stats.enabled=true --set controller.extraArgs.enable-ssl-passthrough=""  --set controller.replicaCount=2 --set controller.nodeSelector."beta\.kubernetes\.io/os"=linux  --set defaultBackend.nodeSelector."beta\.kubernetes\.io/os"=linux nginx-ingress ingress-nginx/ingress-nginx > /dev/null
echo -e "[$okStatus] Done"

# install coordinator
echo "[*] Installing marblerun-coordinator..."
kubectl create ns marblerun > /dev/null
if [ "$LINKERD" = true ]
then
    kubectl annotate ns marblerun linkerd.io/inject=enabled > /dev/null
fi
helm repo add edgeless https://helm.edgeless.systems/stable > /dev/null
marblerun install --domain "$MARBLERUN_DNSNAME.$DOMAIN"
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
# 3. Deploy emojivoto
#

# set manifest
echo "[*] Setting the manifest"
manifest=$(sed "s/localhost/$EMOJIVOTO/g" tools/manifest.json)
echo "$manifest" > /tmp/manifest.json
marblerun manifest set /tmp/manifest.json $MARBLERUN
echo -e "[$okStatus] Done"

# install emojivoto
echo "[*] Installing emojivoto"
kubectl create ns emojivoto > /dev/null
marblerun namespace add emojivoto
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
template=$(sed "s/{{DOMAIN}}/$EMOJIVOTO/g" tools/emojivoto_ingress.yaml.template)
echo "$template" | kubectl -n emojivoto apply -f - > /dev/null
echo -e "[$okStatus] Done"

#
# 4. Finish
#

echo -e "[$okStatus] All done and ready to roll!🚀"
echo -e "[$okStatus] Install ./marblerun.crt in the Trusted-Root-CA store of your browser"
echo -e "[$okStatus] Visit https://$EMOJIVOTO"

if [ "$LINKERD" = true ]
then
    echo -e "[$okStatus] Run 'linkerd dashboard' for access to the linkerd dashboard"
fi
