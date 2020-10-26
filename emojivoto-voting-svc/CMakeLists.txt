# Copyright (c) Edgeless Systems GmbH.
# Licensed under the MIT License.

cmake_minimum_required(VERSION 3.11)

project(emojivoto_voting_svc)
find_package(OpenEnclave CONFIG REQUIRED)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_EXTENSIONS OFF)

if (NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Debug)
endif ()

add_custom_target(voting-svc-servicelib
  ertgo build -buildmode=c-archive
  -o libservice.a
  ${CMAKE_CURRENT_SOURCE_DIR}/cmd/main.go
  ${CMAKE_CURRENT_SOURCE_DIR}/cmd/server.go)

# Enclave
add_executable(voting-svc-enclaved enclave/main.c)
set_target_properties(voting-svc-enclaved PROPERTIES OUTPUT_NAME "enclave")
target_include_directories(voting-svc-enclaved PRIVATE ${CMAKE_CURRENT_BINARY_DIR})
add_dependencies(voting-svc-enclaved voting-svc-servicelib)

target_link_libraries(voting-svc-enclaved
  openenclave::ertmeshentry
  openenclave::oeenclave
  openenclave::oehostepoll
  openenclave::oehostfs
  openenclave::oehostsock
  ${CMAKE_CURRENT_BINARY_DIR}/libservice.a
  openenclave::ertlibc
  openenclave::oecustomfs)

# Generate key
add_custom_command(
  OUTPUT private.pem public.pem
  COMMAND openssl genrsa -out private.pem -3 3072
  COMMAND openssl rsa -in private.pem -pubout -out public.pem)

# Sign enclave
add_custom_command(
  OUTPUT enclave.signed
  DEPENDS voting-svc-enclaved enclave/enclave.conf private.pem
  COMMAND openenclave::oesign sign -e $<TARGET_FILE:voting-svc-enclaved> -c
          ${CMAKE_CURRENT_SOURCE_DIR}/enclave/enclave.conf -k private.pem)
add_custom_target(voting-svc-sign ALL DEPENDS enclave.signed)

# Create config for remote attestation
add_custom_command(
  OUTPUT config.json
  DEPENDS enclave.signed
  COMMAND ${PROJECT_SOURCE_DIR}/../tools/create_config.py -e ${CMAKE_CURRENT_BINARY_DIR}/enclave.signed -o ${CMAKE_CURRENT_BINARY_DIR}/config.json)
add_custom_target(voting-svc-config ALL DEPENDS config.json)
