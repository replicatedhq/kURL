package main

import (
	"archive/tar"
	"compress/gzip"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"io/ioutil"
	"log"
	"net"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"os/signal"
	"path"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/bugsnag/bugsnag-go/v2"
	"github.com/containers/image/v5/copy"
	"github.com/containers/image/v5/docker/reference"
	"github.com/containers/image/v5/signature"
	"github.com/containers/image/v5/transports/alltransports"
	"github.com/containers/image/v5/types"
	"github.com/gorilla/mux"
	"github.com/pkg/errors"
	"golang.org/x/net/publicsuffix"
)

const upstream = "http://localhost:3000"

var activeStreams int64 = 0

func main() {
	log.Printf("Commit %s", os.Getenv("VERSION"))

	if bugsnagKey := os.Getenv("BUGSNAG_KEY"); bugsnagKey != "" {
		bugsnag.Configure(bugsnag.Configuration{
			APIKey:       bugsnagKey,
			ReleaseStage: os.Getenv("ENVIRONMENT"),
			AppVersion:   os.Getenv("VERSION"),
		})
	}

	r := mux.NewRouter()

	r.HandleFunc("/bundle/{installerID}", http.HandlerFunc(bundle))
	r.HandleFunc("/bundle/version/{kurlVersion}/{installerID}", http.HandlerFunc(bundle))
	r.HandleFunc("/healthz", http.HandlerFunc(healthz))

	upstreamURL, err := url.Parse(upstream)
	if err != nil {
		log.Panic(err)
	}
	proxy := httputil.NewSingleHostReverseProxy(upstreamURL)
	r.PathPrefix("/").Handler(proxy)

	http.Handle("/", r)

	log.Println("Listening on :3001")
	server := &http.Server{Addr: ":3001", Handler: bugsnag.Handler(nil)}

	exitMutex := sync.Mutex{}
	go func() {
		exit := make(chan os.Signal, 1) // reserve buffer size one to avoid blocking the notifier
		signal.Notify(exit, os.Interrupt, syscall.SIGTERM)

		<-exit // wait for shutdown signal, then terminate server
		exitMutex.Lock()
		log.Printf("Shutting down server after recieving SIGINT or SIGTERM, %d bundle downloads remain\n", atomic.LoadInt64(&activeStreams))

		err := server.Shutdown(context.TODO())
		if err != nil {
			log.Print(err)
		}
		log.Println("All server connections closed, exiting")
		os.Exit(0)
	}()

	err = server.ListenAndServe()
	if err != nil {
		if err != http.ErrServerClosed {
			log.Fatal(err)
		} else {
			log.Println("No longer accepting new connections")
			exitMutex.Lock() // if the server shutdown handler is still running, don't return from main or the program will exit
		}
	}
}

type BundleManifest struct {
	Layers []string          `json:"layers"`
	Files  map[string]string `json:"files"`
	Images []string          `json:"images"`
}

var policyContextInsecureAcceptAnything *signature.PolicyContext

func init() {
	policy := signature.Policy{Default: []signature.PolicyRequirement{
		signature.NewPRInsecureAcceptAnything(),
	}}
	pc, err := signature.NewPolicyContext(&policy)
	if err != nil {
		panic(errors.Wrapf(err, "failed to create image policy context"))
	}
	policyContextInsecureAcceptAnything = pc
}

func bundle(w http.ResponseWriter, r *http.Request) {
	atomic.AddInt64(&activeStreams, 1)
	defer atomic.AddInt64(&activeStreams, -1)

	if r.Method == "OPTIONS" {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET")
		w.Header().Set("Access-Control-Allow-Headers", "Access-Control-Allow-Origin, Content-Type")
		w.Header().Set("Access-Control-Max-Age", "86400")
		w.WriteHeader(http.StatusNoContent)
		return
	}
	if r.Method != "GET" && r.Method != "HEAD" {
		http.Error(w, "Method Not Allowed", http.StatusMethodNotAllowed)
		return
	}
	log.Printf("%s %s", r.Method, r.URL.Path)

	vars := mux.Vars(r)

	kurlVersion := vars["kurlVersion"]
	installerID := strings.TrimSuffix(vars["installerID"], ".tar.gz")
	var installerURL string
	if kurlVersion != "" {
		installerURL = fmt.Sprintf("%s/bundle/version/%s/%s", upstream, kurlVersion, installerID)
	} else {
		installerURL = fmt.Sprintf("%s/bundle/%s", upstream, installerID)
	}
	request, err := http.NewRequest("GET", installerURL, nil)
	if err != nil {
		err = errors.Wrapf(err, "error building request for %s", installerURL)
		handleHttpError(w, r, err, http.StatusInternalServerError)
		return
	}
	// forward request headers for metrics
	request.Header = r.Header
	if request.Header.Get("X-Forwarded-For") == "" {
		if host, _, _ := net.SplitHostPort(r.RemoteAddr); host != "" {
			request.Header.Set("X-Forwarded-For", host)
		}
	}
	resp, err := http.DefaultClient.Do(request)
	if err != nil {
		err = errors.Wrapf(err, "error fetching %s", installerURL)
		handleHttpError(w, r, err, http.StatusInternalServerError)
		return
	}
	defer resp.Body.Close()
	body, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		err = errors.Wrapf(err, "error reading response body from %s", installerURL)
		handleHttpError(w, r, err, http.StatusInternalServerError)
		return
	}
	if resp.StatusCode == http.StatusNotFound {
		http.Error(w, string(body), http.StatusNotFound)
		return
	}
	bundle := &BundleManifest{}
	err = json.Unmarshal(body, bundle)
	if err != nil {
		err = errors.Wrapf(err, "error unmarshaling installer bundle manifest from %s: %s", installerURL, body)
		handleHttpError(w, r, err, http.StatusInternalServerError)
		return
	}

	for _, srcURL := range bundle.Layers {
		resp, err := http.Head(srcURL)
		if err != nil {
			err = errors.Wrapf(err, "error http head %s for installer %s bundle", srcURL, installerID)
			handleHttpError(w, r, err, http.StatusInternalServerError)
			return
		}
		resp.Body.Close()
		if resp.StatusCode != http.StatusOK {
			err := errors.Errorf("unexpected response status code %d", resp.StatusCode)
			err = errors.Wrapf(err, "error http head %s for installer %s bundle", srcURL, installerID)
			handleHttpError(w, r, err, http.StatusInternalServerError)
			return
		}
	}

	for _, image := range bundle.Images {
		if !allowRegistry(image) {
			err := errors.Errorf("Unsupported image registry %s", image)
			handleHttpError(w, r, err, http.StatusUnprocessableEntity)
			return
		}
	}

	w.Header().Set("Content-Type", "binary/octet-stream")
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Content-Disposition", "attachment")
	w.Header().Set("Transfer-Encoding", "chunked")

	// use handleError below here since headers have already been written

	if r.Method == "HEAD" {
		return
	}

	wz := gzip.NewWriter(w)
	archive := tar.NewWriter(wz)
	defer func() {
		if err := archive.Close(); err != nil {
			err = errors.Wrapf(err, "error closing archive for installer %s", installerID)
			handleError(r.Context(), err, nil)
		}

		if err := wz.Close(); err != nil {
			err = errors.Wrapf(err, "error closing gzip stream for installer %s", installerID)
			handleError(r.Context(), err, nil)
		}
	}()

	var tempDir string
	if len(bundle.Images) > 0 {
		tempDir, err = ioutil.TempDir("/images", "temp-image-pull")
		if err != nil {
			err = errors.Wrap(err, "error creating temp directory")
			handleError(r.Context(), err, archive)
			return
		}
		defer os.RemoveAll(tempDir)
	}

	errCh := make(chan error, 1)
	defer close(errCh)

	imageCh := make(chan string, len(bundle.Images))

	// HACK: Work around the fact that github.com/containers/image/v5/copy copy.Image does not support streaming.
	// Download images concurrently while streaming the rest of the bundle to minimize idle time.
	go func() {
		defer close(imageCh)

		for i, image := range bundle.Images {
			destPath := filepath.Join(tempDir, fmt.Sprintf("%d.tar", i))

			if err := downloadImage(r.Context(), image, destPath); err != nil {
				errCh <- errors.Wrapf(err, "failed to download image %s to path %s", image, destPath)
				return
			}

			imageCh <- destPath
		}
	}()

	for _, layerURL := range bundle.Layers {
		if err := pipeAddonArchive(archive, layerURL); err != nil {
			err = errors.Wrapf(err, "error piping layer %s to bundle %s", layerURL, installerID)
			handleError(r.Context(), err, archive)
			return
		}
	}

	for filepath, contents := range bundle.Files {
		err := pipeBlob(archive, []byte(contents), filepath)
		if err != nil {
			err = errors.Wrapf(err, "error writing file %s to bundle %s", filepath, installerID)
			handleError(r.Context(), err, archive)
			return
		}
	}

	for i := 0; ; i++ {
		select {
		case err := <-errCh:
			handleError(r.Context(), err, archive)
			return

		case srcPath, ok := <-imageCh:
			if !ok {
				return
			}

			destPath := fmt.Sprintf("kurl/image-overrides/%d.tar", i)
			if err := pipeFile(archive, srcPath, destPath); err != nil {
				err = errors.Wrapf(err, "error piping image %s to bundle %s", srcPath, installerID)
				handleError(r.Context(), err, archive)
				return
			}
		}
	}
}

func downloadImage(ctx context.Context, image string, destPath string) error {
	srcRef, err := alltransports.ParseImageName(fmt.Sprintf("docker://%s", image))
	if err != nil {
		return errors.Wrap(err, "parse src image name")
	}

	destStr := fmt.Sprintf("docker-archive:%s:%s", destPath, image)
	localRef, err := alltransports.ParseImageName(destStr)
	if err != nil {
		return errors.Wrap(err, "parse dest image name")
	}

	destCtx := &types.SystemContext{
		DockerDisableV1Ping: true,
	}
	srcCtx := &types.SystemContext{
		DockerDisableV1Ping: true,
		AuthFilePath:        "/dev/null",
		DockerAuthConfig: &types.DockerAuthConfig{
			Username:      "",
			Password:      "",
			IdentityToken: "",
		},
	}
	_, err = copy.Image(ctx, policyContextInsecureAcceptAnything, localRef, srcRef, &copy.Options{
		RemoveSignatures:      true,
		SignBy:                "",
		ForceManifestMIMEType: "",
		DestinationCtx:        destCtx,
		SourceCtx:             srcCtx,
	})

	// This is to keep memory usage down. Go will keep requesting more memory from the system
	// for each image pull, eventually the pod will be evicted.
	runtime.GC()

	return errors.Wrapf(err, "copy image")
}

func pipeAddonArchive(dst *tar.Writer, srcURL string) error {
	resp, err := http.Get(srcURL)
	if err != nil {
		filename := path.Base(srcURL)
		resp, err = http.Get(fmt.Sprintf("https://kurl-sh.s3.amazonaws.com/external/%s", filename))
		if err != nil {
			return err
		}
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return errors.Errorf("unexpected response code %d", resp.StatusCode)
	}

	zr, err := gzip.NewReader(resp.Body)
	if err != nil {
		return errors.Wrap(err, "gunzip response")
	}
	defer zr.Close()

	src := tar.NewReader(zr)

	for {
		header, err := src.Next()
		if err == io.EOF {
			return nil
		} else if err != nil {
			return errors.Wrap(err, "next file")
		}
		header.Name = filepath.Join("kurl", header.Name)

		err = dst.WriteHeader(header)
		if err != nil {
			return errors.Wrap(err, "write tar header")
		}

		_, err = io.Copy(dst, src)
		if err != nil {
			return errors.Wrap(err, "copy file contents")
		}
	}
}

func pipeBlob(dst *tar.Writer, srcBytes []byte, destPath string) error {
	err := dst.WriteHeader(&tar.Header{
		Name:    destPath,
		Size:    int64(len(srcBytes)),
		Mode:    0644,
		ModTime: time.Now(),
	})
	if err != nil {
		return errors.Wrap(err, "write tar header")
	}

	_, err = dst.Write(srcBytes)
	return errors.Wrap(err, "write blob")
}

func pipeFile(dst *tar.Writer, fileName, destPath string) error {
	f, err := os.Open(fileName)
	if err != nil {
		return errors.Wrap(err, "open file")
	}
	defer f.Close()

	fi, err := f.Stat()
	if err != nil {
		return errors.Wrap(err, "stat file")
	}

	header := &tar.Header{
		Name:    destPath,
		Size:    fi.Size(),
		Mode:    0644,
		ModTime: time.Now(),
	}
	err = dst.WriteHeader(header)
	if err != nil {
		return errors.Wrap(err, "write tar header")
	}

	_, err = io.Copy(dst, f)
	return errors.Wrapf(err, "copy file %s contents", header.Name)
}

func handleHttpError(w http.ResponseWriter, r *http.Request, err error, code int) {
	log.Println(err)
	http.Error(w, http.StatusText(code), code)
	bugsnag.Notify(err, r.Context())
}

func handleError(ctx context.Context, err error, archive *tar.Writer) {
	log.Println(err)
	if !errors.Is(err, syscall.EPIPE) && !errors.Is(err, syscall.ECONNRESET) {
		bugsnag.Notify(err, ctx)
	}

	if archive != nil {
		pipeBlob(archive, []byte("Failed to generate archive resulting in an incomplete bundle.\n"), "ERROR.txt")

		// HACK: This will prevent the archive from being extracted.
		// It will result in an unexpected EOF.
		archive.WriteHeader(&tar.Header{
			Name:    "INVALID BUNDLE",
			Size:    8,
			Mode:    0644,
			ModTime: time.Now(),
		})
	}
}

func allowRegistry(image string) bool {
	named, err := reference.ParseNormalizedNamed(image)
	if err != nil {
		return false
	}

	host := reference.Domain(named)
	host, _ = publicsuffix.EffectiveTLDPlusOne(host)

	switch host {
	case "docker.io", "gcr.io", "ghcr.io", "azurecr.io", "ttl.sh", "ecr.us-east-1.amazonaws.com":
		return true
	}

	return false
}

type HealthzResponse struct {
	IsAlive       bool  `json:"is_alive"`
	ActiveStreams int64 `json:"active_streams"`
}

func healthz(w http.ResponseWriter, r *http.Request) {
	healthzResponse := HealthzResponse{
		IsAlive:       true,
		ActiveStreams: atomic.LoadInt64(&activeStreams),
	}
	response, err := json.Marshal(healthzResponse)
	if err != nil {
		w.WriteHeader(500)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(200)
	w.Write(response)
}
