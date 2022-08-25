package helpers

import (
	"os"
	"path/filepath"

	"github.com/pkg/errors"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/tools/clientcmd"
	"kubevirt.io/client-go/kubecli"
)

func GetRestConfig() (*rest.Config, error) {
	kubeconfig := filepath.Join(homeDir(), ".kube", "config")

	if os.Getenv("KUBECONFIG") != "" {
		kubeconfig = os.Getenv("KUBECONFIG")
	}

	// use the current context in kubeconfig
	config, err := clientcmd.BuildConfigFromFlags("", kubeconfig)
	if err != nil {
		return nil, errors.Wrap(err, "failed to build config")
	}
	return config, nil
}

func GetClientset() (*kubernetes.Clientset, error) {
	config, err := GetRestConfig()
	if err != nil {
		return nil, errors.Wrap(err, "failed to get restconfig")
	}

	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		return nil, errors.Wrap(err, "failed to create clientset")
	}

	return clientset, nil
}

func GetKubevirtClientset() (kubecli.KubevirtClient, error) {
	config, err := GetRestConfig()
	if err != nil {
		return nil, errors.Wrap(err, "failed to get restconfig")
	}

	virtClient, err := kubecli.GetKubevirtClientFromRESTConfig(config)
	if err != nil {
		return nil, errors.Wrap(err, "failed to create kubevirt clientset")
	}

	return virtClient, nil
}

func homeDir() string {
	if h := os.Getenv("HOME"); h != "" {
		return h
	}
	return os.Getenv("USERPROFILE") // windows
}
