#!/usr/bin/env bash

docker buildx build --target release_emoji_svc --tag ghcr.io/edgelesssys/emojivoto-emoji-svc:v1 .
docker buildx build --target release_voting_svc --tag ghcr.io/edgelesssys/emojivoto-voting-svc:v1 .
docker buildx build --target release_web --tag ghcr.io/edgelesssys/emojivoto-web:v1 .