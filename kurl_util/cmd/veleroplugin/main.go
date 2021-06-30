// This plugin changes the proxy env vars and host CA path on restored kotsadm deployments (<1.46)
// and statefulsets (>=1.46). All replicasets and pods belonging to the kotsadm deployment/statefulset
// must also be changed to prevent Kubernetes from creating a new replicaset, which can cause the
// restore to fail because of race conditions.
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
	log    logrus.FieldLogger
	client kubernetes.Interface
}

const name = "kurl.sh/restore-kotsadm-plugin"

func main() {
	framework.NewServer().
		RegisterRestoreItemAction(name, newRestorePlugin).
		Serve()
}

func newRestorePlugin(logger logrus.FieldLogger) (interface{}, error) {
	config, err := rest.InClusterConfig()
	if err != nil {
		return nil, err
	}
	client, err := kubernetes.NewForConfig(config)
	if err != nil {
		return nil, err
	}

	return &restoreKotsadmPlugin{
		log:    logger,
		client: client,
	}, nil
}

func (p *restoreKotsadmPlugin) AppliesTo() (velero.ResourceSelector, error) {
	return velero.ResourceSelector{
		IncludedNamespaces: []string{"default"},
		IncludedResources:  []string{"deployments", "statefulsets", "replicasets", "pods"},
	}, nil
}

func (p *restoreKotsadmPlugin) Execute(input *velero.RestoreItemActionExecuteInput) (*velero.RestoreItemActionExecuteOutput, error) {
	metadata, err := meta.Accessor(input.Item)
	if err != nil {
		return nil, err
	}

	data, err := p.getPluginConfig()
	if err != nil {
		return nil, err
	}
	if len(data) == 0 {
		return &velero.RestoreItemActionExecuteOutput{UpdatedItem: input.Item}, nil
	}

	var updatedObj interface{}

	gvk := input.Item.GetObjectKind().GroupVersionKind()
	switch gvk.Kind {
	case "Deployment":
		if metadata.GetName() != "kotsadm" {
			return &velero.RestoreItemActionExecuteOutput{UpdatedItem: input.Item}, nil
		}

		deployment := &appsv1.Deployment{}
		if err := runtime.DefaultUnstructuredConverter.FromUnstructured(input.Item.UnstructuredContent(), deployment); err != nil {
			return nil, errors.Wrap(err, "unable to convert kotsadm deployment from runtime.Unstructured")
		}
		update(&deployment.Spec.Template.Spec, data)

		updatedObj = deployment

	case "StatefulSet":
		if metadata.GetName() != "kotsadm" {
			return &velero.RestoreItemActionExecuteOutput{UpdatedItem: input.Item}, nil
		}

		statefulset := &appsv1.StatefulSet{}
		if err := runtime.DefaultUnstructuredConverter.FromUnstructured(input.Item.UnstructuredContent(), statefulset); err != nil {
			return nil, errors.Wrap(err, "unable to convert kotsadm statefulset from runtime.Unstructured")
		}

		update(&statefulset.Spec.Template.Spec, data)
		updatedObj = statefulset

	case "ReplicaSet":
		if metadata.GetLabels()["app"] != "kotsadm" {
			return &velero.RestoreItemActionExecuteOutput{UpdatedItem: input.Item}, nil
		}

		replicaset := &appsv1.ReplicaSet{}
		if err := runtime.DefaultUnstructuredConverter.FromUnstructured(input.Item.UnstructuredContent(), replicaset); err != nil {
			return nil, errors.Wrap(err, "unable to convert kotsadm replicaset from runtime.Unstructured")
		}
		update(&replicaset.Spec.Template.Spec, data)

		updatedObj = replicaset

	case "Pod":
		if metadata.GetLabels()["app"] != "kotsadm" {
			return &velero.RestoreItemActionExecuteOutput{UpdatedItem: input.Item}, nil
		}

		pod := &corev1.Pod{}
		if err := runtime.DefaultUnstructuredConverter.FromUnstructured(input.Item.UnstructuredContent(), pod); err != nil {
			return nil, errors.Wrap(err, "unable to convert kotsadm pod from runtime.Unstructured")
		}
		update(&pod.Spec, data)

		updatedObj = pod

	default:
		return &velero.RestoreItemActionExecuteOutput{UpdatedItem: input.Item}, nil
	}

	updated, err := runtime.DefaultUnstructuredConverter.ToUnstructured(updatedObj)
	if err != nil {
		return nil, errors.Wrap(err, "unable to convert kotsadm resource to runtime.Unstructured")
	}
	item := &unstructured.Unstructured{Object: updated}

	return &velero.RestoreItemActionExecuteOutput{UpdatedItem: item}, err
}

func (p *restoreKotsadmPlugin) getPluginConfig() (map[string]string, error) {
	opts := metav1.ListOptions{
		LabelSelector: fmt.Sprintf("velero.io/plugin-config,%s=%s", name, framework.PluginKindRestoreItemAction),
	}
	list, err := p.client.CoreV1().ConfigMaps(os.Getenv("VELERO_NAMESPACE")).List(context.TODO(), opts)
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

func update(pod *corev1.PodSpec, data map[string]string) {
	if noProxy, ok := data["NO_PROXY"]; ok {
		setKotsadmEnv(pod, "NO_PROXY", noProxy)
	}
	if httpProxy, ok := data["HTTP_PROXY"]; ok {
		setKotsadmEnv(pod, "HTTP_PROXY", httpProxy)
	}
	if httpsProxy, ok := data["HTTPS_PROXY"]; ok {
		setKotsadmEnv(pod, "HTTPS_PROXY", httpsProxy)
	}
	if caHostPath, ok := data["hostCAPath"]; ok && caHostPath != "" {
		setKotsadmHostCAPath(pod, caHostPath)
	}
}

func setKotsadmEnv(pod *corev1.PodSpec, key string, value string) {
	for i, container := range pod.Containers {
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
		pod.Containers[i].Env = append(container.Env, corev1.EnvVar{
			Name:  key,
			Value: value,
		})
	}
}

func setKotsadmHostCAPath(pod *corev1.PodSpec, caHostPath string) {
	for i, volume := range pod.Volumes {
		if volume.Name != "host-cacerts" {
			continue
		}
		if volume.HostPath == nil {
			continue
		}
		pod.Volumes[i].HostPath.Path = caHostPath
	}
}
