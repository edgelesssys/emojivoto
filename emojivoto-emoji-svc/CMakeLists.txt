cmake_minimum_required(VERSION 3.11)

project(emojivoto_emoji_svc)
find_package(OpenEnclave CONFIG REQUIRED)

if (NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Debug)
endif ()

add_custom_target(emoji-svc-servicelib
  ertgo build -buildmode=c-archive
  -o servicelib.a
  ${CMAKE_CURRENT_SOURCE_DIR}/cmd)

# Enclave
add_executable(emoji-svc-enclaved enclave/main.c)
set_target_properties(emoji-svc-enclaved PROPERTIES OUTPUT_NAME "enclave")
add_dependencies(emoji-svc-enclaved emoji-svc-servicelib)

target_link_libraries(emoji-svc-enclaved
  openenclave::oeenclave
  openenclave::ertmeshentry
  ${CMAKE_CURRENT_BINARY_DIR}/servicelib.a)

# Generate key
add_custom_command(
  OUTPUT private.pem public.pem
  COMMAND openssl genrsa -out private.pem -3 3072
  COMMAND openssl rsa -in private.pem -pubout -out public.pem)

# Sign enclave
add_custom_command(
OUTPUT enclave.signed
 DEPENDS emoji-svc-enclaved enclave/enclave.conf private.pem
 COMMAND openenclave::oesign sign -e $<TARGET_FILE:emoji-svc-enclaved> -c
         ${CMAKE_CURRENT_SOURCE_DIR}/enclave/enclave.conf -k private.pem)
add_custom_target(emoji-svc-sign ALL DEPENDS enclave.signed)

# Create config for remote attestation
add_custom_command(
  OUTPUT config.json
  DEPENDS enclave.signed
  COMMAND openenclave::oesign eradump -e ${CMAKE_CURRENT_BINARY_DIR}/enclave.signed > ${CMAKE_CURRENT_BINARY_DIR}/config.json)
add_custom_target(emoji-svc-config ALL DEPENDS config.json)
