//go:build !linux

package main

import "github.com/vishvananda/netlink"

func routeList() ([]netlink.Route, error) {
	return []netlink.Route{}, nil
}
