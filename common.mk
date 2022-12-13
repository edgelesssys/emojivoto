.PHONY: package protoc test

target_dir := target

clean:
	rm -rf gen
	rm -rf $(target_dir)
	mkdir -p $(target_dir)
	mkdir -p gen

protoc:
	protoc -I .. ../proto/*.proto --go_out=./gen --go_opt=paths=source_relative --go-grpc_out=./gen --go-grpc_opt=paths=source_relative

package: protoc compile

compile:
	GOOS=linux go build -v -o $(target_dir)/$(svc_name) cmd/server.go
	ego sign enclave/enclave.json

test:
	go test ./...

run:
	go run cmd/server.go
