// +build tools

package tools

import (
	_ "golang.org/x/lint/golint"
	_ "k8s.io/code-generator/pkg/util"
	_ "sigs.k8s.io/controller-tools/pkg/version"
)
