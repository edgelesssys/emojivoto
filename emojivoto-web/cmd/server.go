package main

import (
	"crypto/tls"
	"crypto/x509"
	"log"
	"os"
	"time"

	"contrib.go.opencensus.io/exporter/ocagent"
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
		domain               = os.Getenv("DOMAIN")
		emojisvcHost         = os.Getenv("EMOJISVC_HOST")
		votingsvcHost        = os.Getenv("VOTINGSVC_HOST")
		indexBundle          = os.Getenv("INDEX_BUNDLE")
		webpackDevServerHost = os.Getenv("WEBPACK_DEV_SERVER")
		ocagentHost          = os.Getenv("OC_AGENT_HOST")
		tlsCertPem           = os.Getenv("TLS_CERT")
		privk                = os.Getenv("TLS_PRIV_KEY")
		rootCA               = os.Getenv("ROOT_CA")
	)

	if webPort == "" || emojisvcHost == "" || votingsvcHost == "" {
		log.Fatalf("WEB_PORT (currently [%s]) EMOJISVC_HOST (currently [%s]) and VOTINGSVC_HOST (currently [%s]) INDEX_BUNDLE (currently [%s]) environment variables must me set.", webPort, emojisvcHost, votingsvcHost, indexBundle)
	}

	// create CertPool
	roots := x509.NewCertPool()
	if !roots.AppendCertsFromPEM([]byte(rootCA)) {
		log.Fatalf("cannot append rootCa to CertPool")
	}
	// create certificate
	tlsCert, err := tls.X509KeyPair([]byte(tlsCertPem), []byte(privk))
	if err != nil {
		log.Fatalf("cannot create TLS cert: %v", err)
	}
	// create TLS config
	serverCfg := &tls.Config{
		ClientCAs:    roots,
		Certificates: []tls.Certificate{tlsCert},
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
		Certificates: []tls.Certificate{tlsCert},
	}
	// create creds
	clientCreds := credentials.NewTLS(clientCfg)

	votingSvcConn := openGrpcClientConnection(votingsvcHost, clientCreds)
	votingClient := pb.NewVotingServiceClient(votingSvcConn)
	defer votingSvcConn.Close()

	emojiSvcConn := openGrpcClientConnection(emojisvcHost, clientCreds)
	emojiSvcClient := pb.NewEmojiServiceClient(emojiSvcConn)
	defer emojiSvcConn.Close()

	web.StartServer(webPort, domain, webpackDevServerHost, indexBundle, emojiSvcClient, votingClient, serverCfg)
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
