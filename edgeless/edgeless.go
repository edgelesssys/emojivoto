package edgeless

import (
	"crypto/tls"
	"crypto/x509"
	"log"
	"os"
)

// GetCredentials parses the credentials from the environment.
func GetCredentials() ([]tls.Certificate, *x509.CertPool) {
	tlsCertPem := os.Getenv("TLS_CERT")
	privk := os.Getenv("TLS_PRIV_KEY")
	rootCA := os.Getenv("ROOT_CA")
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
	return []tls.Certificate{tlsCert}, roots
}
