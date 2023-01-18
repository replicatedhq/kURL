package k8sutil

import (
	"github.com/replicatedhq/kurl/pkg/version"
)

const (
	// LabelKeyKurlshManaged is the metadata label key for kurl.sh managed resources
	LabelKeyKurlshManaged = "kurl.sh/managed"
	// LabelKeyKurlshVersion is the metadata label key for kurl.sh version
	LabelKeyKurlshVersion = "kurl.sh/version"
)

// AppendKurlLabels appends kurl.sh managed labels to the given map
func AppendKurlLabels(labels map[string]string) map[string]string {
	if labels == nil {
		labels = map[string]string{}
	}
	labels[LabelKeyKurlshManaged] = "true"
	labels[LabelKeyKurlshVersion] = version.Version()
	return labels
}
