package main

import (
	"crypto/tls"
	"log"
	"os"
	"time"

	"contrib.go.opencensus.io/exporter/ocagent"
	pb "github.com/edgelesssys/emojivoto/emojivoto-web/gen/proto"
	"github.com/edgelesssys/emojivoto/emojivoto-web/web"
	"github.com/edgelesssys/ertgolib/marble"
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

	// get TLS config
	tlsCfg, err := marble.GetServerTLSConfig()
	if err != nil {
		log.Fatalf("Failed to retrieve server TLS config from ertgolib")
	}

	// create creds
	serverCreds := credentials.NewTLS(tlsCfg)

	oce, err := ocagent.NewExporter(
		ocagent.WithTLSCredentials(serverCreds),
		ocagent.WithReconnectionPeriod(5*time.Second),
		ocagent.WithAddress(ocagentHost),
		ocagent.WithServiceName("web"))
	if err != nil {
		log.Fatalf("Failed to create ocagent-exporter: %v", err)
	}
	trace.RegisterExporter(oce)

	// get gRPC config
	clientCfg, err := marble.GetClientTLSConfig()
	if err != nil {
		log.Fatalf("Failed to retrieve client TLS config from ertgolib")
	}
	// create creds
	clientCreds := credentials.NewTLS(clientCfg)

	votingSvcConn := openGrpcClientConnection(votingsvcHost, clientCreds)
	votingClient := pb.NewVotingServiceClient(votingSvcConn)
	defer votingSvcConn.Close()

	emojiSvcConn := openGrpcClientConnection(emojisvcHost, clientCreds)
	emojiSvcClient := pb.NewEmojiServiceClient(emojiSvcConn)
	defer emojiSvcConn.Close()

	// Use a different certificate for the web server
	cert := []byte(os.Getenv("WEB_CERT"))
	privk := []byte(os.Getenv("WEB_CERT_KEY"))

	tlsCert, err := tls.X509KeyPair(cert, privk)
	if err != nil {
		log.Fatalf("cannot create TLS cert: %v", err)
	}
	webTLSCfg := &tls.Config{
		Certificates: []tls.Certificate{tlsCert},
	}
	web.StartServer(webPort, webpackDevServerHost, indexBundle, emojiSvcClient, votingClient, webTLSCfg)
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
