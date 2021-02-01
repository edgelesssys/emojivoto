cmake_minimum_required(VERSION 3.11)

project(emojivoto_voting_svc)
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
  OUTPUT voting-svc
  DEPENDS enclave/enclave.json private.pem
  COMMAND ego-go build -o voting-svc ${CMAKE_CURRENT_SOURCE_DIR}/cmd
  COMMAND ego sign ${CMAKE_CURRENT_SOURCE_DIR}/enclave/enclave.json
)
add_custom_target(voting-svc-sign ALL)

# Create config for remote attestation
add_custom_command(
  OUTPUT config.json
  DEPENDS voting-svc
  COMMAND openenclave::oesign eradump -e ${CMAKE_CURRENT_BINARY_DIR}/voting-svc > ${CMAKE_CURRENT_BINARY_DIR}/config.json)
add_custom_target(voting-svc-config ALL DEPENDS config.json)
