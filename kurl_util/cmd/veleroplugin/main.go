package main

import (
	"context"
	"fmt"
	"os"

	"github.com/pkg/errors"
	"github.com/sirupsen/logrus"
	"github.com/vmware-tanzu/velero/pkg/plugin/framework"
	"github.com/vmware-tanzu/velero/pkg/plugin/velero"
	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/meta"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
)

type restoreKotsadmPlugin struct {
	log logrus.FieldLogger
}

const name = "kurl.sh/restore-kotsadm-plugin"

func main() {
	framework.NewServer().
		RegisterRestoreItemAction(name, newRestorePlugin).
		Serve()
}

func newRestorePlugin(logger logrus.FieldLogger) (interface{}, error) {
	return &restoreKotsadmPlugin{
		log: logger,
	}, nil
}

func (p *restoreKotsadmPlugin) AppliesTo() (velero.ResourceSelector, error) {
	return velero.ResourceSelector{
		IncludedNamespaces: []string{"default"},
		IncludedResources:  []string{"deployments"},
	}, nil
}

func (p *restoreKotsadmPlugin) Execute(input *velero.RestoreItemActionExecuteInput) (*velero.RestoreItemActionExecuteOutput, error) {
	metadata, err := meta.Accessor(input.Item)
	if err != nil {
		return nil, err
	}
	if metadata.GetName() != "kotsadm" {
		return &velero.RestoreItemActionExecuteOutput{UpdatedItem: input.Item}, nil
	}

	data, err := getPluginConfig()
	if err != nil {
		return nil, err
	}
	if len(data) == 0 {
		return &velero.RestoreItemActionExecuteOutput{UpdatedItem: input.Item}, nil
	}

	deployment := &appsv1.Deployment{}
	if err := runtime.DefaultUnstructuredConverter.FromUnstructured(input.Item.UnstructuredContent(), deployment); err != nil {
		return nil, errors.Wrap(err, "unable to convert kotsadm deployment from runtime.Unstructured")
	}

	if noProxy, ok := data["NO_PROXY"]; ok {
		setKotsadmEnv(deployment, "NO_PROXY", noProxy)
	}
	if httpProxy, ok := data["HTTP_PROXY"]; ok {
		setKotsadmEnv(deployment, "HTTP_PROXY", httpProxy)
	}
	if httpsProxy, ok := data["HTTPS_PROXY"]; ok {
		setKotsadmEnv(deployment, "HTTPS_PROXY", httpsProxy)
	}
	if caHostPath, ok := data["hostCAPath"]; ok && caHostPath != "" {
		setKotsadmHostCAPath(deployment, caHostPath)
	}

	updated, err := runtime.DefaultUnstructuredConverter.ToUnstructured(deployment)
	if err != nil {
		return nil, errors.Wrap(err, "unable to convert kotsadm deployment to runtime.Unstructured")
	}
	item := &unstructured.Unstructured{Object: updated}

	return &velero.RestoreItemActionExecuteOutput{UpdatedItem: item}, err
}

func getPluginConfig() (map[string]string, error) {
	config, err := rest.InClusterConfig()
	if err != nil {
		return nil, err
	}
	client, err := kubernetes.NewForConfig(config)
	if err != nil {
		return nil, err
	}

	opts := metav1.ListOptions{
		LabelSelector: fmt.Sprintf("velero.io/plugin-config,%s=%s", name, framework.PluginKindRestoreItemAction),
	}
	list, err := client.CoreV1().ConfigMaps(os.Getenv("VELERO_NAMESPACE")).List(context.TODO(), opts)
	if err != nil {
		return nil, errors.WithStack(err)
	}

	if len(list.Items) == 0 {
		return nil, nil
	}

	if len(list.Items) > 1 {
		var items []string
		for _, item := range list.Items {
			items = append(items, item.Name)
		}
		return nil, errors.Errorf("found more than one ConfigMap matching label selector %q: %v", opts.LabelSelector, items)
	}

	return list.Items[0].Data, nil
}

func setKotsadmEnv(deployment *appsv1.Deployment, key string, value string) {
	for i, container := range deployment.Spec.Template.Spec.Containers {
		if container.Name != "kotsadm" {
			continue
		}
		for j, env := range container.Env {
			if env.Name == key {
				container.Env[j].Value = value
				return
			}
		}
		// append since not found (unless empty)
		if value == "" {
			return
		}
		deployment.Spec.Template.Spec.Containers[i].Env = append(container.Env, corev1.EnvVar{
			Name:  key,
			Value: value,
		})
	}
}

func setKotsadmHostCAPath(deployment *appsv1.Deployment, caHostPath string) {
	for i, volume := range deployment.Spec.Template.Spec.Volumes {
		if volume.Name != "host-cacerts" {
			continue
		}
		if volume.HostPath == nil {
			continue
		}
		deployment.Spec.Template.Spec.Volumes[i].HostPath.Path = caHostPath
	}
}
