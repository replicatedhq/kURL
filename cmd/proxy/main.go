package main

import (
	"context"
	"crypto/sha1"
	"crypto/tls"
	"crypto/x509"
	"encoding/pem"
	"fmt"
	"io/ioutil"
	"log"
	"net"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/pkg/errors"
	"github.com/soheilhy/cmux"
	v1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/fields"
	"k8s.io/apimachinery/pkg/watch"
	"k8s.io/client-go/kubernetes"
	corev1 "k8s.io/client-go/kubernetes/typed/core/v1"
	"k8s.io/client-go/rest"
)

type cert struct {
	tlsCert                tls.Certificate
	fingerprint            string
	acceptAnonymousUploads bool
}

func main() {
	upstreamOrigin := os.Getenv("UPSTREAM_ORIGIN")
	tlsSecretName := os.Getenv("TLS_SECRET_NAME")
	namespace := os.Getenv("NAMESPACE")
	nodePort := os.Getenv("NODE_PORT")

	gin.SetMode(gin.ReleaseMode)

	upstream, err := url.Parse(upstreamOrigin)
	if err != nil {
		log.Panic(err)
	}
	config, err := rest.InClusterConfig()
	if err != nil {
		log.Panic(err)
	}
	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		log.Panic(err)
	}
	secrets := clientset.CoreV1().Secrets(namespace)

	certs := make(chan cert)
	go watchSecret(certs, tlsSecretName, secrets)

	var httpServer *http.Server
	var httpsServer *http.Server
	var listener net.Listener

	log.Printf("Waiting for TLS credentials from secret %s", tlsSecretName)
	for cert := range certs {
		ctx, _ := context.WithTimeout(context.Background(), time.Minute)
		if httpServer != nil {
			httpServer.Shutdown(ctx)
		}
		if httpsServer != nil {
			httpsServer.Shutdown(ctx)
		}
		if listener != nil {
			listener.Close()
		}

		l, err := net.Listen("tcp", ":8800")
		if err != nil {
			log.Panic(err)
		}
		listener = l

		m := cmux.New(listener)

		httpsServer = getHttpsServer(upstream, tlsSecretName, secrets, cert.acceptAnonymousUploads, nodePort)
		tlsConfig := &tls.Config{
			Certificates: []tls.Certificate{cert.tlsCert},
		}
		go httpsServer.Serve(tls.NewListener(m.Match(cmux.TLS()), tlsConfig))

		httpServer = getHttpServer(cert.fingerprint)
		go httpServer.Serve(m.Match(cmux.Any()))

		log.Println("Kurl Proxy listening on :8800")
		log.Printf("\tupstream: %s\n", upstreamOrigin)
		log.Printf("\tcert: %s\n", cert.fingerprint)
		log.Printf("\tanonymous uploads enabled: %t\n", cert.acceptAnonymousUploads)

		go func() {
			err := m.Serve()
			log.Printf("Cmux server terminated with %v", err)
		}()
	}
}

func watchSecret(certs chan cert, name string, secrets corev1.SecretInterface) {
	opts := metav1.ListOptions{
		FieldSelector: fields.OneTermEqualSelector("metadata.name", name).String(),
	}
	w, err := secrets.Watch(opts)
	if err != nil {
		log.Panic(err)
	}
	for e := range w.ResultChan() {
		switch e.Type {
		case watch.Added:
			fallthrough
		case watch.Modified:
			secret, ok := e.Object.(*v1.Secret)
			if !ok {
				log.Printf("Watched object wasn't a secret")
				break
			}
			certData := secret.Data["tls.crt"]
			keyData := secret.Data["tls.key"]
			crt, err := tls.X509KeyPair(certData, keyData)
			if err != nil {
				log.Printf("Ignoring secret %s: invalid cert/key pair: %v", name, err)
				break
			}

			derBlock, _ := pem.Decode(certData)
			if derBlock == nil {
				log.Printf("Ignoring secret %s: no PEM data found in certificate", name)
				break
			}
			x509Cert, err := x509.ParseCertificate(derBlock.Bytes)
			if err != nil {
				log.Printf("Ignoring secret %s: parse certificate: %v", name, err)
				break
			}
			//sha1 fingerprint is the hash of the certificate in DER form
			fingerprint := strings.ToUpper(strings.Replace(fmt.Sprintf("% x", sha1.Sum(x509Cert.Raw)), " ", ":", -1))

			acceptAnonymousUploads := false
			acceptAnonymousUploadsVal, ok := secret.Data["acceptAnonymousUploads"]
			if ok && string(acceptAnonymousUploadsVal) == "1" {
				acceptAnonymousUploads = true
			}

			certs <- cert{
				tlsCert:                crt,
				fingerprint:            fingerprint,
				acceptAnonymousUploads: acceptAnonymousUploads,
			}
		}
	}
}

func getHttpServer(fingerprint string) *http.Server {
	r := gin.Default()

	r.StaticFS("/assets", http.Dir("/assets"))
	r.LoadHTMLGlob("/assets/*.html")

	r.GET("/", func(c *gin.Context) {
		c.HTML(http.StatusOK, "insecure.html", gin.H{
			"fingerprintSHA1": fingerprint,
		})
	})

	return &http.Server{
		Handler: r,
	}
}

func getHttpsServer(upstream *url.URL, tlsSecretName string, secrets corev1.SecretInterface, acceptAnonymousUploads bool, nodePort string) *http.Server {
	mux := http.NewServeMux()

	r := gin.Default()

	mux.Handle("/tls/assets/", http.StripPrefix("/tls/assets/", http.FileServer(http.Dir("/assets"))))
	r.LoadHTMLGlob("/assets/*.html")

	r.GET("/tls", func(c *gin.Context) {
		err := c.Query("error") != ""
		success := c.Query("success") != ""
		enabled := !success && acceptAnonymousUploads
		help := !err && !success && !acceptAnonymousUploads
		c.HTML(http.StatusOK, "tls.html", gin.H{
			"Error":   err,
			"Success": success,
			"Enabled": enabled,
			"Help":    help,
			"Secret":  tlsSecretName,
		})
	})

	r.POST("/tls", func(c *gin.Context) {
		if !acceptAnonymousUploads {
			c.AbortWithStatus(403)
			return
		}
		certData, keyData, err := getUploadedCerts(c)
		if err != nil {
			log.Printf("POST /tls: %v", err)
			c.Redirect(http.StatusFound, "/tls?error=1")
			return
		}

		secret, err := secrets.Get(tlsSecretName, metav1.GetOptions{})
		if err != nil {
			log.Print(err)
			c.AbortWithStatus(http.StatusInternalServerError)
			return
		}

		location := fmt.Sprintf("https://%s:%s/tls?success=1", c.PostForm("hostname"), nodePort)
		if c.PostForm("hostname") == "" {
			location = "/tls?success=1"
		}
		c.Redirect(http.StatusSeeOther, location)

		go func() {
			time.Sleep(time.Millisecond * 100)
			secret.Data["tls.crt"] = certData
			secret.Data["tls.key"] = keyData
			delete(secret.Data, "acceptAnonymousUploads")
			_, err = secrets.Update(secret)
			if err != nil {
				log.Print(err)
				c.AbortWithStatus(http.StatusInternalServerError)
				return
			}
		}()
	})
	mux.Handle("/tls", r)

	mux.Handle("/", httputil.NewSingleHostReverseProxy(upstream))

	return &http.Server{
		Handler: mux,
	}
}

func getUploadedCerts(c *gin.Context) ([]byte, []byte, error) {
	certHeader, err := c.FormFile("cert")
	if err != nil {
		return nil, nil, errors.Wrapf(err, "get cert file")
	}
	certFile, err := certHeader.Open()
	if err != nil {
		return nil, nil, errors.Wrapf(err, "open cert file")
	}
	defer certFile.Close()
	certData, err := ioutil.ReadAll(certFile)
	if err != nil {
		return nil, nil, errors.Wrapf(err, "read cert file")
	}

	keyHeader, err := c.FormFile("key")
	if err != nil {
		return nil, nil, errors.Wrapf(err, "get key file")
	}
	keyFile, err := keyHeader.Open()
	if err != nil {
		return nil, nil, errors.Wrapf(err, "open key file")
	}
	defer keyFile.Close()
	keyData, err := ioutil.ReadAll(keyFile)
	if err != nil {
		return nil, nil, errors.Wrapf(err, "read key file")
	}

	// validate
	_, err = tls.X509KeyPair(certData, keyData)
	if err != nil {
		return nil, nil, errors.Wrapf(err, "validate uploaded cert/key pair")
	}

	return certData, keyData, nil
}
