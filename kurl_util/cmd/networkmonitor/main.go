package main

import (
	"context"
	"fmt"
	"io/ioutil"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/pkg/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"sigs.k8s.io/controller-runtime/pkg/client/config"
)

func main() {
	server()
	err := requester()
	if err != nil {
		log.Fatal(err)
	}
}

// run the server - this should respond to requests from other nodes on port 8080
func server() {
	go func() {
		log.Printf("starting server on port 8080\n")
		server := &http.Server{
			Addr: ":8080",
		}
		http.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
			_, err := w.Write([]byte("{}"))
			if err != nil {
				log.Println(err.Error())
				return
			}
		})

		// - name: POD_NAME
		//   valueFrom:
		//     fieldRef:
		//       fieldPath: metadata.name
		http.HandleFunc("/netcheck", func(w http.ResponseWriter, r *http.Request) {
			_, err := w.Write([]byte(os.Getenv("POD_NAME")))
			if err != nil {
				log.Println(err.Error())
				return
			}
		})

		err := server.ListenAndServe()
		if err != http.ErrServerClosed && err != nil {
			log.Println(err.Error())
			os.Exit(1)
		}

	}()
}

// send requests to other nodes in cluster, report errors if they occur
// update list of other pods at
func requester() error {
	cfg, err := config.GetConfig()
	if err != nil {
		return errors.Wrap(err, "failed to get config")
	}
	clientset, err := kubernetes.NewForConfig(cfg)
	if err != nil {
		return errors.Wrap(err, "failed to create kubernetes clientset")
	}

	for {
		otherPods, err := clientset.CoreV1().Pods("kurl").List(context.TODO(), metav1.ListOptions{
			LabelSelector: "app=networkmonitor",
		})
		if err != nil {
			log.Println(errors.Wrap(err, "failed to list pods"))
			time.Sleep(time.Minute)
			continue
		}
		for _, otherPod := range otherPods.Items {
			address := podAddress(otherPod.Status.PodIP)

			resp, err := http.Get(address)
			if err != nil {
				log.Println(errors.Wrapf(err, "request to %q for pod %s failed", address, otherPod.Name))
				continue
			}
			if resp.StatusCode != http.StatusOK {
				log.Println(fmt.Sprintf("got response code %d from pod %s", resp.Status, otherPod.Name))
			}
			body, err := ioutil.ReadAll(resp.Body)
			if err != nil {
				log.Println(errors.Wrapf(err, "reading body of request to %q for pod %s failed", address, otherPod.Name))
				continue
			}
			log.Println(fmt.Sprintf("body: %s", string(body)))
		}
	}
}

func podAddress(ip string) string {
	return fmt.Sprintf("%s.networkmonitor.kurl.svc.cluster.local", ip)
}
