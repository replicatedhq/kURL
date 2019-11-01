package main

import (
	"log"
	"time"

	"github.com/pkg/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
	bootstraputil "k8s.io/cluster-bootstrap/token/util"
	"k8s.io/kubernetes/cmd/kubeadm/app/apis/kubeadm"
	kubeadmconstants "k8s.io/kubernetes/cmd/kubeadm/app/constants"
	tokenphase "k8s.io/kubernetes/cmd/kubeadm/app/phases/bootstraptoken/node"
)

const configMapName = "kurl-config"
const configMapNamespace = "kube-system"

const bootstrapTokenKey = "bootstrap_token"
const bootstrapTokenExpirationKey = "bootstrap_token_expiration"

func main() {
	client := clientsetOrDie()

	bootstrapTokenDuration := time.Hour * 24
	bootstrapTokenExpiration := time.Now().Add(bootstrapTokenDuration)
	bootstrapToken, err := GenerateBootstrapToken(client, bootstrapTokenDuration)
	if err != nil {
		log.Panic(err)
	}

	// TODO kubeadm init phase upload-certs for HA

	// TODO rbac Get ConfigMap in kube-system namespace
	cm, err := client.CoreV1().ConfigMaps(configMapNamespace).Get(configMapName, metav1.GetOptions{})
	if err != nil {
		log.Panic(err)
	}

	cm.Data[bootstrapTokenKey] = bootstrapToken
	cm.Data[bootstrapTokenExpirationKey] = bootstrapTokenExpiration.Format(time.RFC3339)

	_, err = client.CoreV1().ConfigMaps(configMapNamespace).Update(cm)
	if err != nil {
		log.Panic(err)
	}
}

// GenerateBootstrapToken will generate a node join token for kubeadm.
// ttl defines the time to live for this token.
func GenerateBootstrapToken(client kubernetes.Interface, ttl time.Duration) (string, error) {
	token, err := bootstraputil.GenerateBootstrapToken()
	if err != nil {
		return "", errors.Wrap(err, "generate kubeadm token")
	}

	bts, err := kubeadm.NewBootstrapTokenString(token)
	if err != nil {
		return "", errors.Wrap(err, "new kubeadm token string")
	}

	duration := &metav1.Duration{Duration: ttl}

	// TODO rbac - Update, Create Secrets in kube-system namespace
	if err := tokenphase.UpdateOrCreateTokens(client, false, []kubeadm.BootstrapToken{
		{
			Token:  bts,
			TTL:    duration,
			Usages: []string{"authentication", "signing"},
			Groups: []string{kubeadmconstants.NodeBootstrapTokenAuthGroup},
		},
	}); err != nil {
		return "", errors.Wrap(err, "create kubeadm token")
	}

	return token, nil
}

func clientsetOrDie() kubernetes.Interface {
	config, err := rest.InClusterConfig()
	if err != nil {
		log.Panic(err)
	}
	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		log.Panic(err)
	}
	return clientset
}
