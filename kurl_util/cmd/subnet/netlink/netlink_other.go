//go:build !linux

package netlink

import "github.com/vishvananda/netlink"

func RouteList() ([]netlink.Route, error) {
	return []netlink.Route{}, nil
}
