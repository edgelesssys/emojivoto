.PHONY: package protoc test

target_dir := target

clean:
	rm -rf gen
	rm -rf $(target_dir)
	mkdir -p $(target_dir)
	mkdir -p gen

protoc:
	protoc -I .. ../proto/*.proto --go_out=plugins=grpc:gen

package: protoc compile

compile:
	GOOS=linux go build -v -o $(target_dir)/$(svc_name) cmd/server.go
	ego sign enclave/enclave.json

test:
	go test ./...

run:
	go run cmd/server.go