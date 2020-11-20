cmake_minimum_required(VERSION 3.11)

project(emojivoto_web)
find_package(OpenEnclave CONFIG REQUIRED)

if (NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Debug)
endif ()

add_custom_target(emoji-web-servicelib
  ertgo build -buildmode=c-archive
  -o libservice.a
  ${CMAKE_CURRENT_SOURCE_DIR}/cmd)

add_custom_command(TARGET emoji-web-servicelib
  PRE_BUILD
  COMMAND cd ${CMAKE_CURRENT_SOURCE_DIR}/webapp && yarn install && yarn webpack
  COMMAND mkdir -p ${CMAKE_CURRENT_BINARY_DIR}/web && cp ${CMAKE_CURRENT_SOURCE_DIR}/web/favicon.ico ${CMAKE_CURRENT_BINARY_DIR}/web
  COMMAND cp -a ${CMAKE_CURRENT_SOURCE_DIR}/webapp/dist ${CMAKE_CURRENT_BINARY_DIR})

add_custom_target(vote-bot ALL
  GOOS=linux ertgo build -o ${CMAKE_CURRENT_BINARY_DIR}/emojivoto-vote-bot
  ${CMAKE_CURRENT_SOURCE_DIR}/cmd/vote-bot/main.go
)

# Enclave
add_executable(emoji-web-enclaved enclave/main.c)
set_target_properties(emoji-web-enclaved PROPERTIES OUTPUT_NAME "enclave")
add_dependencies(emoji-web-enclaved emoji-web-servicelib)

target_link_libraries(emoji-web-enclaved
  openenclave::oeenclave
  openenclave::ertmeshentry
  ${CMAKE_CURRENT_BINARY_DIR}/libservice.a)

# Generate key
add_custom_command(
  OUTPUT private.pem public.pem
  COMMAND openssl genrsa -out private.pem -3 3072
  COMMAND openssl rsa -in private.pem -pubout -out public.pem)

# Sign enclave
add_custom_command(
  OUTPUT enclave.signed
  DEPENDS emoji-web-enclaved enclave/enclave.conf private.pem
  COMMAND openenclave::oesign sign -e $<TARGET_FILE:emoji-web-enclaved> -c
          ${CMAKE_CURRENT_SOURCE_DIR}/enclave/enclave.conf -k private.pem)
add_custom_target(emoji-web-sign ALL DEPENDS enclave.signed)

# Create config for remote attestation
add_custom_command(
  OUTPUT config.json
  DEPENDS enclave.signed
  COMMAND openenclave::oesign eradump -e ${CMAKE_CURRENT_BINARY_DIR}/enclave.signed > ${CMAKE_CURRENT_BINARY_DIR}/config.json)
add_custom_target(emoji-web-config ALL DEPENDS config.json)
