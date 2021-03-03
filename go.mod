module github.com/replicatedhq/kurl

go 1.16

require (
	github.com/StackExchange/wmi v0.0.0-20190523213315-cbe66965904d // indirect
	github.com/briandowns/spinner v1.12.0
	github.com/chzyer/readline v0.0.0-20180603132655-2972be24d48e
	github.com/denisbrodbeck/machineid v1.0.1
	github.com/fatih/color v1.10.0
	github.com/go-ole/go-ole v1.2.5 // indirect
	github.com/golang/mock v1.5.0
	github.com/google/go-cmp v0.5.4 // indirect
	github.com/mattn/go-isatty v0.0.12
	github.com/pkg/errors v0.9.1
	github.com/replicatedhq/kurl/kurlkinds v0.0.0-20210223231814-ca7e7b16afa0
	github.com/replicatedhq/troubleshoot v0.10.8
	github.com/spf13/afero v1.2.2
	github.com/spf13/cobra v1.1.3
	github.com/spf13/viper v1.7.1
	github.com/stretchr/testify v1.6.1
	k8s.io/client-go v0.20.4
)

replace github.com/replicatedhq/kurl/kurlkinds => ./kurlkinds
