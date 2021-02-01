cmake_minimum_required(VERSION 3.11)

project(emojivoto_web)
find_package(OpenEnclave CONFIG REQUIRED)

if (NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Debug)
endif ()

# Generate key
add_custom_command(
  OUTPUT private.pem public.pem
  COMMAND openssl genrsa -out private.pem -3 3072
  COMMAND openssl rsa -in private.pem -pubout -out public.pem)

# Build & Sign enclave
add_custom_command(
  OUTPUT emoji-web
  DEPENDS enclave/enclave.json private.pem
  COMMAND ego-go build -o emoji-web ${CMAKE_CURRENT_SOURCE_DIR}/cmd
  COMMAND ego sign ${CMAKE_CURRENT_SOURCE_DIR}/enclave/enclave.json
)
add_custom_target(emoji-web-sign ALL)

# Create config for remote attestation
add_custom_command(
  OUTPUT config.json
  DEPENDS emoji-web
  COMMAND openenclave::oesign eradump -e ${CMAKE_CURRENT_BINARY_DIR}/emoji-web > ${CMAKE_CURRENT_BINARY_DIR}/config.json)
add_custom_target(emoji-web-config ALL DEPENDS config.json)

add_custom_command(TARGET emoji-web-sign
  PRE_BUILD
  COMMAND cd ${CMAKE_CURRENT_SOURCE_DIR}/webapp && yarn install && yarn webpack
  COMMAND mkdir -p ${CMAKE_CURRENT_BINARY_DIR}/web && cp ${CMAKE_CURRENT_SOURCE_DIR}/web/favicon.ico ${CMAKE_CURRENT_BINARY_DIR}/web
  COMMAND cp -a ${CMAKE_CURRENT_SOURCE_DIR}/webapp/dist ${CMAKE_CURRENT_BINARY_DIR})

add_custom_target(vote-bot ALL
  GOOS=linux ertgo build -o ${CMAKE_CURRENT_BINARY_DIR}/emojivoto-vote-bot
  ${CMAKE_CURRENT_SOURCE_DIR}/cmd/vote-bot/main.go
)
