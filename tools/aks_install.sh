#!/usr/bin/env bash
if [ $# -lt 2 ];
then
    echo "Usage: $0 <azure resourceGroup> <azure clusterName>"
    exit 1
fi

RESOURCEGROUP=$1
CLUSTERNAME=$2

UNIQUE_SUFFIX="$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 16 | head -n 1)"
MARBLERUN_DNSNAME="marblerun-$UNIQUE_SUFFIX"
EMOJIVOTO_DNSNAME="emojivoto-$UNIQUE_SUFFIX"

okStatus="\e[92m\u221A\e[0m"
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
    echo "[$failStatus] MarbleRun CLI could not be found"
    echo "See Installation Guide @ https://marblerun.sh/docs/getting-started/cli"
    exit
fi

if ! command -v helm &> /dev/null
then
    echo "[$failStatus] helm could not be found"
    echo "See Installation Guide https://helm.sh/docs/intro/install/"
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


# Get cluster info
REGION=$(az aks show --resource-group "$RESOURCEGROUP" --name "$CLUSTERNAME" --query location)
temp="${REGION%\"}"
REGION="${temp#\"}"
DOMAIN="$REGION.cloudapp.azure.com"
az aks get-credentials --resource-group "$RESOURCEGROUP" --name "$CLUSTERNAME"

#
# 1. linkerd
#

# Check if linkerd should be deployed
if [ "$LINKERD" = true ]
then
    linkerd_execute() {
        if ${@} >/dev/null 2>/tmp/linkerd_output
        then
            echo -e "[$okStatus] $* succeeded"
        else
            echo -e "[$failStatus] $* failed"
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
# 2. Deploy MarbleRun+DNS and Ingress-Controller+DNS
#

# install coordinator
echo "[*] Installing marblerun-coordinator..."
kubectl create ns marblerun > /dev/null
if [ "$LINKERD" = true ]
then
    kubectl annotate ns marblerun linkerd.io/inject=enabled > /dev/null
fi
helm repo add edgeless https://helm.edgeless.systems/stable > /dev/null
marblerun install --domain "$MARBLERUN_DNSNAME.$DOMAIN"
marblerun check
echo -e "[$okStatus] Done"


# set dns for coordinator
echo "[*] Setting DNS for the marblerun-coordinator"
kubectl apply -f - <<EOF
kind: Service
apiVersion: v1
metadata:
  name: marblerun-coordinator-loadbalancer
  namespace: marblerun
spec:
  type: LoadBalancer
  selector:
    edgeless.systems/control-plane-component: coordinator
    edgeless.systems/control-plane-ns: marblerun
  ports:
  - name: http
    port: 4433
    targetPort: 4433
EOF

IP=""
echo -n "[*] Waiting for LoadBalancer to assign a public IP..."
until [[ $IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]];
do
    IP=$(kubectl -n marblerun get svc marblerun-coordinator-loadbalancer -o jsonpath="{.status.loadBalancer.ingress[0].ip}")
    echo -n "."
    sleep 3
done
PUBLICIPID=$(az network public-ip list --query "[?ipAddress!=null]|[?contains(ipAddress, '$IP')].[id]" --output tsv)
az network public-ip update --ids "$PUBLICIPID" --dns-name "$MARBLERUN_DNSNAME" > /dev/null
MARBLERUN=""
until [[ $MARBLERUN == "$MARBLERUN_DNSNAME."* ]]
do
    MARBLERUN="$(az network public-ip show --ids "$PUBLICIPID" --query "[dnsSettings.fqdn]" --output tsv):4433"
    echo -n "."
    sleep 3
done
echo ""
echo -e "[$okStatus] Done"

# set dns for emojivoto
echo "[*] Setting DNS for emojivoto"
kubectl create ns emojivoto > /dev/null
kubectl apply -f - <<EOF
kind: Service
apiVersion: v1
metadata:
  name: emojivoto-web-loadbalancer
  namespace: emojivoto
spec:
  type: LoadBalancer
  selector:
    app: web-svc
  ports:
  - name: http
    port: 443
    targetPort: 4433
EOF

IP=""
echo -n "[*] Waiting for LoadBalancer to assign a public IP..."
until [[ $IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]];
do
    IP=$(kubectl -n emojivoto get svc emojivoto-web-loadbalancer -o jsonpath="{.status.loadBalancer.ingress[0].ip}")
    echo -n "."
    sleep 3
done
PUBLICIPID=$(az network public-ip list --query "[?ipAddress!=null]|[?contains(ipAddress, '$IP')].[id]" --output tsv)
az network public-ip update --ids "$PUBLICIPID" --dns-name "$EMOJIVOTO_DNSNAME" > /dev/null
EMOJIVOTO=""
until [[ $EMOJIVOTO == "$EMOJIVOTO_DNSNAME."* ]]
do
    EMOJIVOTO="$(az network public-ip show --ids "$PUBLICIPID" --query "[dnsSettings.fqdn]" --output tsv)"
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
marblerun manifest set /tmp/manifest.json "$MARBLERUN"
echo -e "[$okStatus] Done"

# install emojivoto
echo "[*] Installing emojivoto"
if [ "$LINKERD" = true ]
then
    kubectl annotate ns emojivoto linkerd.io/inject=enabled > /dev/null
fi
helm install emojivoto ./kubernetes \
    -f ./kubernetes/sgx_values.yaml \
    -n emojivoto > /dev/null
echo -e "[$okStatus] Done"

# waiting for emojivoto to come up
echo "[*] Waiting for emojivoto to be ready..."
kubectl rollout status statefulset -n emojivoto emoji --timeout=120s
kubectl rollout status statefulset -n emojivoto web --timeout=120s
kubectl rollout status statefulset -n emojivoto voting --timeout=120s
echo -e "[$okStatus] Done"

#
# 4. Get certificate chain from the Coordinator
#

echo "[*] Getting certificate chain from the Coordinator"
marblerun manifest verify /tmp/manifest.json "$MARBLERUN" --coordinator-cert ./marblerun.crt
echo -e "[$okStatus] Done"

#
# 5. Finish
#

echo -e "[$okStatus] All done and ready to roll!🚀"
echo -e "\n\tInstall ./marblerun.crt in the Trusted-Root-CA store of your browser"
echo -e "\tVisit https://$EMOJIVOTO\n"

if [ "$LINKERD" = true ]
then
    echo -e "[$okStatus] Run 'linkerd dashboard' for access to the linkerd dashboard"
fi
