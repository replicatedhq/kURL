package netutils

import (
	"errors"
	"net"
	"syscall"

	"github.com/vishvananda/netlink"
)

func GetDefaultGatewayInterface() (*net.Interface, error) {
	routes, err := netlink.RouteList(nil, syscall.AF_INET)
	if err != nil {
		return nil, err
	}

	for _, route := range routes {
		if route.Dst == nil || route.Dst.String() == "0.0.0.0/0" {
			if route.LinkIndex <= 0 {
				return nil, errors.New("found default route but could not determine interface")
			}
			return net.InterfaceByIndex(route.LinkIndex)
		}
	}

	return nil, errors.New("unable to find default route")
}

func GetDefaultV6GatewayInterface() (*net.Interface, error) {
	routes, err := netlink.RouteList(nil, syscall.AF_INET6)
	if err != nil {
		return nil, err
	}

	for _, route := range routes {
		if route.Dst == nil || route.Dst.String() == "::/0" {
			if route.LinkIndex <= 0 {
				return nil, errors.New("found default v6 route but could not determine interface")
			}
			return net.InterfaceByIndex(route.LinkIndex)
		}
	}

	return nil, errors.New("unable to find default v6 route")
}

func GetInterfaceByIP(ip net.IP) (*net.Interface, error) {
	ifaces, err := net.Interfaces()
	if err != nil {
		return nil, err
	}

	for _, iface := range ifaces {
		err := ifaceIPv4AddrMatch(&iface, ip)
		if err == nil {
			return &iface, nil
		}
	}

	return nil, errors.New("no interface with given IP address found")
}

func GetInterfaceByIPv6(ip net.IP) (*net.Interface, error) {
	ifaces, err := net.Interfaces()
	if err != nil {
		return nil, err
	}

	for _, iface := range ifaces {
		err := ifaceIPv6AddrMatch(&iface, ip)
		if err == nil {
			return &iface, nil
		}
	}

	return nil, errors.New("no interface with given IPv6 address found")
}

func ifaceIPv4AddrMatch(iface *net.Interface, matchAddr net.IP) error {
	addrs, err := getIfaceV4AddrList(iface)
	if err != nil {
		return err
	}

	for _, addr := range addrs {
		if addr.IP.To4() != nil {
			if addr.IP.To4().Equal(matchAddr) {
				return nil
			}
		}
	}

	return errors.New("no IPv4 address found for given interface")
}

func ifaceIPv6AddrMatch(iface *net.Interface, matchAddr net.IP) error {
	addrs, err := getIfaceV6AddrList(iface)
	if err != nil {
		return err
	}

	for _, addr := range addrs {
		if addr.IP.To16() != nil {
			if addr.IP.To16().Equal(matchAddr) {
				return nil
			}
		}
	}

	return errors.New("no IPv6 address found for given interface")
}

func getIfaceV4AddrList(iface *net.Interface) ([]netlink.Addr, error) {
	return netlink.AddrList(&netlink.Device{
		LinkAttrs: netlink.LinkAttrs{
			Index: iface.Index,
		},
	}, syscall.AF_INET)
}

func getIfaceV6AddrList(iface *net.Interface) ([]netlink.Addr, error) {
	return netlink.AddrList(&netlink.Device{
		LinkAttrs: netlink.LinkAttrs{
			Index: iface.Index,
		},
	}, syscall.AF_INET6)
}
