package netlink

import "github.com/vishvananda/netlink"

func RouteList() ([]netlink.Route, error) {
	routes, err := netlink.RouteList(nil, netlink.FAMILY_V4)
	if err != nil {
		return nil, err
	}
	return routes, nil
}
