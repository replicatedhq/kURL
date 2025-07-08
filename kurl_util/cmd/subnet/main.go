package main

import (
	"flag"
	"fmt"
	"net"
	"os"
	"strings"

	"github.com/apparentlymart/go-cidr/cidr"
	"github.com/vishvananda/netlink"
)

const (
	// CIDRRangeDefault is the default subnet size when unspecified in the subnet-size flag
	CIDRRangeDefault = 22

	// SubnetAllocRangeDefault represents the default ip range from which to allocate subnets
	SubnetAllocRangeDefault = "10.0.0.0/8"
)

func main() {
	cidrRangeFlag := flag.Int("cidr-range", CIDRRangeDefault, "the cidr range to request from the ip range specified by subnet-alloc-range")
	subnetAllocRangeFlag := flag.String("subnet-alloc-range", SubnetAllocRangeDefault, "ip range from which to allocate subnets")
	excludeSubnetFlag := flag.String("exclude-subnet", "", "comma separated list of subnets to exclude")
	debugFlag := flag.Bool("debug", false, "enable debug logging")

	flag.Parse()

	cidrRange := *cidrRangeFlag
	debug := *debugFlag

	if cidrRange < 1 || cidrRange > 32 {
		fmt.Printf("cidr-range %d invalid, must be between 1 and 32\n", cidrRange)
		os.Exit(1)
	}

	_, subnetAllocRange, err := net.ParseCIDR(*subnetAllocRangeFlag)
	if err != nil {
		fmt.Printf("failed to parse subnet-alloc-range cidr: %s\n", err.Error())
		os.Exit(1)
	}

	var excludeSubnets []*net.IPNet
	if *excludeSubnetFlag != "" {
		for _, s := range strings.Split(*excludeSubnetFlag, ",") {
			_, subnet, err := net.ParseCIDR(s)
			if err != nil {
				fmt.Printf("failed to parse exclude-subnet cidr: %s\n", err.Error())
				os.Exit(1)
			}
			excludeSubnets = append(excludeSubnets, subnet)
		}
	}

	routes, err := routeList()
	if err != nil {
		fmt.Printf("failed to list routes: %s\n", err.Error())
		os.Exit(1)
	}
	if debug {
		for _, route := range routes {
			fmt.Fprintf(os.Stderr, "Found route %s\n", route)
		}
	}

	for _, subnet := range excludeSubnets {
		route := netlink.Route{
			Src: subnet.IP,
			Dst: subnet,
		}
		if debug {
			fmt.Fprintf(os.Stderr, "Exluding additional route %s\n", route)
		}
		routes = append(routes, route)
	}

	subnet, err := FindAvailableSubnet(cidrRange, subnetAllocRange, routes, debug)
	if err != nil {
		fmt.Printf("failed to find available subnet: %s\n", err.Error())
		os.Exit(1)
	}

	fmt.Print(subnet)
}

// FindAvailableSubnet will find an available subnet for a given size in a given range.
func FindAvailableSubnet(cidrRange int, subnetRange *net.IPNet, routes []netlink.Route, debug bool) (*net.IPNet, error) {
	forceV4 := len(subnetRange.IP) == net.IPv4len

	startIP, _ := cidr.AddressRange(subnetRange)

	_, subnet, err := net.ParseCIDR(fmt.Sprintf("%s/%d", startIP, cidrRange))
	if err != nil {
		return nil, fmt.Errorf("parse cidr: %w", err)
	}
	if debug {
		fmt.Fprintf(os.Stderr, "First subnet %s\n", subnet)
	}

	for {
		firstIP, lastIP := cidr.AddressRange(subnet)
		if !subnetRange.Contains(firstIP) || !subnetRange.Contains(lastIP) {
			return nil, fmt.Errorf("no available subnet found within %s", subnet.String())
		}

		route := findFirstOverlappingRoute(subnet, routes)
		if route == nil {
			return subnet, nil
		}
		if forceV4 {
			// NOTE: this may break with v6 addresses
			if ip4 := route.Dst.IP.To4(); ip4 != nil {
				route.Dst.IP = ip4
			}
		}
		if debug {
			fmt.Fprintf(os.Stderr, "Route %s overlaps with subnet %s\n", *route, subnet)
		}

		s, exceeded := cidr.NextSubnet(route.Dst, cidrRange)
		if exceeded {
			return nil, fmt.Errorf("no available subnet found within %s", subnet.String())
		}
		subnet = s
		if debug {
			fmt.Fprintf(os.Stderr, "Next subnet %s\n", subnet)
		}
	}
}

// findFirstOverlappingRoute will return the first overlapping route with the subnet specified
func findFirstOverlappingRoute(subnet *net.IPNet, routes []netlink.Route) *netlink.Route {
	for _, route := range routes {
		if route.Dst == nil || route.Dst.IP.Equal(net.IPv4zero) || route.Dst.IP.Equal(net.IPv6zero) {
			continue
		}
		if route.Dst != nil && overlaps(route.Dst, subnet) {
			return &route
		}
	}
	return nil
}

func overlaps(n1, n2 *net.IPNet) bool {
	return n1.Contains(n2.IP) || n2.Contains(n1.IP)
}
