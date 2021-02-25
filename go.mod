module github.com/replicatedhq/kurl

go 1.16

require (
	github.com/StackExchange/wmi v0.0.0-20190523213315-cbe66965904d // indirect
	github.com/fatih/color v1.10.0
	github.com/go-ole/go-ole v1.2.5 // indirect
	github.com/manifoldco/promptui v0.3.2
	github.com/pkg/errors v0.9.1
	github.com/replicatedhq/kurl/kurlkinds v0.0.0-20210223231814-ca7e7b16afa0
	github.com/replicatedhq/troubleshoot v0.10.6
	github.com/shirou/gopsutil v3.21.1+incompatible
	github.com/spf13/cobra v1.1.3
	github.com/spf13/viper v1.7.1
	golang.org/x/sys v0.0.0-20210124154548-22da62e12c0c
	k8s.io/client-go v0.20.4
)

replace github.com/replicatedhq/kurl/kurlkinds => ./kurlkinds
