#!/usr/bin/env bash

mkdir -p configs
tools/gh-dl-config.sh "edgelesssys/emojivoto" web configs/web.json
tools/gh-dl-config.sh "edgelesssys/emojivoto" emoji configs/emoji-svc.json
tools/gh-dl-config.sh "edgelesssys/emojivoto" voting configs/voting-svc.json
tools/create_manifest.py -c configs -m tools/manifest_template.json -o tools/manifest.json
tools/gh-dl-config.sh "edgelesssys/coordinator" latest mesh.config
echo "[+] Done! You can find the manifest in tools/manifest.json"
