package host

import "github.com/denisbrodbeck/machineid"

// ProtectedID returns a hashed version of the machine ID in a cryptographically secure way,
func ProtectedID() (string, error) {
	return machineid.ProtectedID("replicated")
}
