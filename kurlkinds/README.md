To make a change to the Installer type.

1. Edit ./pkg/apis/cluster/v1beta1/installer_types.go
1. Run `make schemas` (make sure you have the dependencies installed with `make deps`)
1. Define a new bash variable in kurl_util/cmd/yamltobash/main.go to hold the value of the new field.
1. Use the new bash variable in kurl install scripts.
