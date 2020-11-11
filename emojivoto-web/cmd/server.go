package main

import (
	"crypto/tls"
	"log"
	"os"
	"time"

	"contrib.go.opencensus.io/exporter/ocagent"
	"github.com/edgelesssys/emojivoto/edgeless"
	pb "github.com/edgelesssys/emojivoto/emojivoto-web/gen/proto"
	"github.com/edgelesssys/emojivoto/emojivoto-web/web"
	"go.opencensus.io/plugin/ocgrpc"
	"go.opencensus.io/trace"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials"
)

func main() {
	var (
		webPort              = os.Getenv("WEB_PORT")
		emojisvcHost         = os.Getenv("EMOJISVC_HOST")
		votingsvcHost        = os.Getenv("VOTINGSVC_HOST")
		indexBundle          = os.Getenv("INDEX_BUNDLE")
		webpackDevServerHost = os.Getenv("WEBPACK_DEV_SERVER")
		ocagentHost          = os.Getenv("OC_AGENT_HOST")
	)

	if webPort == "" || emojisvcHost == "" || votingsvcHost == "" {
		log.Fatalf("WEB_PORT (currently [%s]) EMOJISVC_HOST (currently [%s]) and VOTINGSVC_HOST (currently [%s]) INDEX_BUNDLE (currently [%s]) environment variables must me set.", webPort, emojisvcHost, votingsvcHost, indexBundle)
	}

	tlsCerts, roots := edgeless.GetCredentials()
	// create TLS config
	serverCfg := &tls.Config{
		ClientCAs:    roots,
		Certificates: tlsCerts,
	}
	// create creds
	serverCreds := credentials.NewTLS(serverCfg)

	oce, err := ocagent.NewExporter(
		ocagent.WithTLSCredentials(serverCreds),
		ocagent.WithReconnectionPeriod(5*time.Second),
		ocagent.WithAddress(ocagentHost),
		ocagent.WithServiceName("web"))
	if err != nil {
		log.Fatalf("Failed to create ocagent-exporter: %v", err)
	}
	trace.RegisterExporter(oce)

	// create gRPC config
	clientCfg := &tls.Config{
		RootCAs:      roots,
		Certificates: tlsCerts,
	}
	// create creds
	clientCreds := credentials.NewTLS(clientCfg)

	votingSvcConn := openGrpcClientConnection(votingsvcHost, clientCreds)
	votingClient := pb.NewVotingServiceClient(votingSvcConn)
	defer votingSvcConn.Close()

	emojiSvcConn := openGrpcClientConnection(emojisvcHost, clientCreds)
	emojiSvcClient := pb.NewEmojiServiceClient(emojiSvcConn)
	defer emojiSvcConn.Close()

	web.StartServer(webPort, webpackDevServerHost, indexBundle, emojiSvcClient, votingClient, serverCfg)
}

func openGrpcClientConnection(host string, creds credentials.TransportCredentials) *grpc.ClientConn {
	log.Printf("Connecting to [%s]", host)
	conn, err := grpc.Dial(
		host,
		grpc.WithTransportCredentials(creds),
		grpc.WithStatsHandler(new(ocgrpc.ClientHandler)))

	if err != nil {
		panic(err)
	}
	return conn
}
