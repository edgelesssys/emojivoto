#!/usr/bin/env bash

echo "[+] Building emoji-svc" && pushd emojivoto-emoji-svc && mkdir -p build && cd build && cmake .. &&  make && popd
echo "[+] Building voting-svc" && pushd emojivoto-voting-svc && mkdir -p build && cd build && cmake .. &&  make && popd
echo "[+] Building web-svc" &&  pushd emojivoto-web && mkdir -p build && cd build && cmake .. &&  make && popd