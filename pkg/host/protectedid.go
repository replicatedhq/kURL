package host

import "github.com/denisbrodbeck/machineid"

func ProtectedID() (string, error) {
	return machineid.ProtectedID("replicated")
}
