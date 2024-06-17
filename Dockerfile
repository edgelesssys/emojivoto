FROM alpine/git:latest AS pull
COPY . /emojivoto

ARG EGO_VER=v1.5.3

FROM ghcr.io/edgelesssys/ego-deploy:${EGO_VER} AS emoji_base
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl dnsutils iptables jq nghttp2 && \
    apt clean && \
    apt autoclean
COPY ./start.sh /start.sh

FROM ghcr.io/edgelesssys/ego-dev:${EGO_VER} AS emoji_build
WORKDIR /node
RUN curl -sL https://deb.nodesource.com/setup_10.x -o nodesource_setup.sh && \
    bash nodesource_setup.sh
RUN curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add - && \
    echo "deb https://dl.yarnpkg.com/debian/ stable main" | tee /etc/apt/sources.list.d/yarn.list
RUN apt update && \
    apt install -y yarn nodejs wget tar unzip
ARG GEN_GO_VER=1.28.1
ARG GEN_GO_GRPC_VER=1.2.0
ARG PB_VER=21.8
RUN wget -q https://github.com/protocolbuffers/protobuf/releases/download/v${PB_VER}/protoc-${PB_VER}-linux-x86_64.zip && \
    unzip protoc-${PB_VER}-linux-x86_64.zip -d /root/.local && \
    cp /root/.local/bin/protoc /usr/local/bin/protoc
RUN go install google.golang.org/protobuf/cmd/protoc-gen-go@v${GEN_GO_VER} && \
    go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@v${GEN_GO_GRPC_VER}
ENV PATH="$PATH:/root/.local/bin:/root/go/bin"

COPY --from=pull /emojivoto /emojivoto
WORKDIR /emojivoto
RUN --mount=type=secret,id=signingkey,dst=/emojivoto/emojivoto-web/private.pem,required=true \
    --mount=type=secret,id=signingkey,dst=/emojivoto/emojivoto-emoji-svc/private.pem,required=true \
    --mount=type=secret,id=signingkey,dst=/emojivoto/emojivoto-voting-svc/private.pem,required=true \
    ego env make build

FROM ghcr.io/edgelesssys/ego-dev:${EGO_VER} AS patch_build
RUN apt update && apt install -y wget tar unzip
ARG GEN_GO_VER=1.28.1
ARG GEN_GO_GRPC_VER=1.2.0
ARG PB_VER=21.8
RUN wget -q https://github.com/protocolbuffers/protobuf/releases/download/v${PB_VER}/protoc-${PB_VER}-linux-x86_64.zip && \
    unzip protoc-${PB_VER}-linux-x86_64.zip -d /root/.local && \
    cp /root/.local/bin/protoc /usr/local/bin/protoc
ENV PATH="$PATH:/root/.local/bin:/root/go/bin"
RUN go install google.golang.org/protobuf/cmd/protoc-gen-go@v${GEN_GO_VER} && \
    go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@v${GEN_GO_GRPC_VER}
COPY --from=pull /emojivoto /emojivoto
WORKDIR /emojivoto
RUN --mount=type=secret,id=signingkey,dst=/emojivoto/emojivoto-voting-svc/private.pem,required=true \
    ego env make patch

FROM emoji_base AS release_emoji_svc
LABEL description="/emojivoto-emoji-svc"
COPY --from=emoji_build /emojivoto/emojivoto-emoji-svc/target/emojivoto-emoji-svc /emojivoto-emoji-svc
ENTRYPOINT ["/start.sh", "/emojivoto-emoji-svc"]

FROM emoji_base AS release_voting_svc
LABEL description="emojivoto-voting-svc"
COPY --from=emoji_build /emojivoto/emojivoto-voting-svc/target/emojivoto-voting-svc /emojivoto-voting-svc
ENTRYPOINT ["/start.sh", "/emojivoto-voting-svc"]

FROM emoji_base AS release_voting_update
LABEL description="emojivoto-voting-update"
COPY --from=patch_build /emojivoto/emojivoto-voting-svc/target/emojivoto-voting-svc /emojivoto-voting-svc
ENTRYPOINT ["/start.sh", "/emojivoto-voting-svc"]

FROM emoji_base AS release_web
LABEL description="emojivoto-web"
COPY --from=emoji_build /emojivoto/emojivoto-web/target/emojivoto-web /emojivoto-web
COPY --from=emoji_build /emojivoto/emojivoto-web/target/web /web
COPY --from=emoji_build /emojivoto/emojivoto-web/target/dist /dist
COPY --from=emoji_build /emojivoto/emojivoto-web/target/emojivoto-vote-bot /emojivoto-vote-bot
ENTRYPOINT ["/start.sh", "/emojivoto-web"]
