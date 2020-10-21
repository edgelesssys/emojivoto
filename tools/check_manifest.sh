#!/usr/bin/env bash

if [[ $# -lt 1 ]]
then
    echo "Usage $0 <manifest.json>"
    exit 1
fi

REMOTE_SIGNATURE=$(curl --silent --cacert mesh.crt "https://$EDG_COORDINATOR_SVC/manifest" | jq '.ManifestSignature' --raw-output)
LOCAL_SIGNATURE=$(sha256sum "$1" | awk '{ print $1 }')
[[ "$REMOTE_SIGNATURE" == "$LOCAL_SIGNATURE" ]] && echo "[+] Success. Manifest signature valid." || echo "[-] Error. Manifest signature invalid."