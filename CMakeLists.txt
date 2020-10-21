# Copyright (c) Edgeless Systems GmbH.
# Licensed under the MIT License.

cmake_minimum_required(VERSION 3.11)

project(emojivoto)
add_subdirectory(emojivoto-voting-svc)
add_subdirectory(emojivoto-emoji-svc)
add_subdirectory(emojivoto-web)
