module github.com/replicatedhq/kurl/testgrid/tgrun

go 1.14

require (
	github.com/pkg/errors v0.8.1
	github.com/replicatedhq/kurl/kurlkinds v0.0.0-20200616210543-a7ac91c8c90b
	github.com/replicatedhq/kurl/testgrid/tgapi v0.0.0-20200609141000-22fb64716037
	github.com/spf13/cobra v0.0.5
	github.com/spf13/viper v1.6.2
	github.com/stretchr/testify v1.4.0
	go.uber.org/zap v1.13.0
	k8s.io/api v0.18.3
	k8s.io/apimachinery v0.18.3
	k8s.io/client-go v12.0.0+incompatible
	kubevirt.io/client-go v0.30.0
)

replace k8s.io/client-go => k8s.io/client-go v0.18.3
