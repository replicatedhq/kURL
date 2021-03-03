package machineid

import "github.com/denisbrodbeck/machineid"

func ID() (string, error) {
	return machineid.ProtectedID("replicated")
}
