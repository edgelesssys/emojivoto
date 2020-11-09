# syntax=docker/dockerfile:experimental

FROM alpine/git:latest AS pull
RUN --mount=type=secret,id=repoaccess,dst=/root/.netrc,required=true git clone https://github.com/edgelesssys/emojivoto.git /emojivoto

FROM ghcr.io/edgelesssys/edgelessrt-private:deploy AS emoji_base
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl dnsutils iptables jq nghttp2 && \
    apt clean && \
    apt autoclean

FROM ghcr.io/edgelesssys/edgelessrt-private:latest AS emoji_build
RUN go get github.com/golang/protobuf/protoc-gen-go && \
    go get google.golang.org/grpc/cmd/protoc-gen-go-grpc
COPY --from=pull /emojivoto /emojivoto

FROM emoji_build AS build_emoji_svc
WORKDIR /emojivoto/emojivoto-emoji-svc/build
RUN --mount=type=secret,id=repoaccess,dst=/root/.netrc,required=true \
    --mount=type=secret,id=signingkey,dst=/emojivoto/emojivoto-emoji-svc/build/private.pem,required=true \
    cmake .. && \
    GOPRIVATE=github.com/edgelesssys make

FROM emoji_build AS build_voting_svc
WORKDIR /emojivoto/emojivoto-voting-svc/build
RUN --mount=type=secret,id=repoaccess,dst=/root/.netrc,required=true \
    --mount=type=secret,id=signingkey,dst=/emojivoto/emojivoto-voting-svc/build/private.pem,required=true \
    cmake .. && \
    GOPRIVATE=github.com/edgelesssys make

FROM emoji_build AS build_web
WORKDIR /node
RUN curl -sL https://deb.nodesource.com/setup_10.x -o nodesource_setup.sh && \
    bash nodesource_setup.sh
RUN curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add - && \
    echo "deb https://dl.yarnpkg.com/debian/ stable main" | tee /etc/apt/sources.list.d/yarn.list
RUN apt update && \
    apt install -y yarn nodejs
WORKDIR /emojivoto/emojivoto-web/build
RUN --mount=type=secret,id=repoaccess,dst=/root/.netrc,required=true \
    --mount=type=secret,id=signingkey,dst=/emojivoto/emojivoto-web/build/private.pem,required=true \
    cmake .. && \
    GOPRIVATE=github.com/edgelesssys make

FROM emoji_base AS release_emoji_svc
LABEL description="emoji-svc"
COPY --from=build_emoji_svc /emojivoto/emojivoto-emoji-svc/build/enclave.signed /enclave.signed
ENTRYPOINT ["erthost", "/enclave.signed"]

FROM emoji_base AS release_voting_svc
LABEL description="voting-svc"
COPY --from=build_voting_svc /emojivoto/emojivoto-voting-svc/build/enclave.signed /enclave.signed
ENTRYPOINT ["erthost", "/enclave.signed"]

FROM emoji_base AS release_web
LABEL description="emoji-web"
COPY --from=build_web /emojivoto/emojivoto-web/build/enclave.signed /enclave.signed
COPY --from=build_web /emojivoto/emojivoto-web/build/web /web
COPY --from=build_web /emojivoto/emojivoto-web/build/dist /dist
COPY --from=build_web /emojivoto/emojivoto-web/build/emojivoto-vote-bot /emojivoto-vote-bot
ENTRYPOINT ["erthost", "/enclave.signed"]
