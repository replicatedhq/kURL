package main

import (
	"net"
	"reflect"
	"testing"

	"github.com/vishvananda/netlink"
)

func TestFindAvailableSubnet(t *testing.T) {
	type args struct {
		cidrRange   int
		subnetRange *net.IPNet
		routes      []netlink.Route
	}
	tests := []struct {
		name    string
		args    args
		want    *net.IPNet
		wantErr bool
	}{
		{
			name: "basic",
			args: args{
				cidrRange:   16,
				subnetRange: mustParseCIDR("10.0.0.0/8"),
				routes:      []netlink.Route{},
			},
			want: mustParseCIDR("10.0.0.0/16"),
		},
		{
			name: "taken",
			args: args{
				cidrRange:   16,
				subnetRange: mustParseCIDR("10.0.0.0/8"),
				routes: []netlink.Route{
					makeRoute("10.0.0.0", 16),
				},
			},
			want: mustParseCIDR("10.1.0.0/16"),
		},
		{
			name: "smaller",
			args: args{
				cidrRange:   22,
				subnetRange: mustParseCIDR("10.0.0.0/8"),
				routes: []netlink.Route{
					makeRoute("10.0.0.0", 22),
					makeRoute("10.0.4.0", 22),
				},
			},
			want: mustParseCIDR("10.0.8.0/22"),
		},
		{
			name: "gap",
			args: args{
				cidrRange:   24,
				subnetRange: mustParseCIDR("10.0.0.0/8"),
				routes: []netlink.Route{
					makeRoute("10.0.0.0", 24),
					makeRoute("10.0.2.0", 24),
				},
			},
			want: mustParseCIDR("10.0.1.0/24"),
		},
		{
			name: "range",
			args: args{
				cidrRange:   22,
				subnetRange: mustParseCIDR("10.32.0.0/16"),
				routes: []netlink.Route{
					makeRoute("10.0.0.0", 16),
				},
			},
			want: mustParseCIDR("10.32.0.0/22"),
		},
		{
			name: "none available",
			args: args{
				cidrRange:   16,
				subnetRange: mustParseCIDR("10.0.0.0/8"),
				routes: []netlink.Route{
					makeRoute("10.0.0.0", 8),
				},
			},
			wantErr: true,
		},
		{
			name: "none available 10.17",
			args: args{
				cidrRange:   22,
				subnetRange: mustParseCIDR("10.17.0.0/16"),
				routes: []netlink.Route{
					makeRoute("10.17.0.0", 16),
				},
			},
			wantErr: true,
		},
		{
			name: "optimize",
			args: args{
				cidrRange:   32,
				subnetRange: mustParseCIDR("10.17.0.0/16"),
				routes: []netlink.Route{
					makeRoute("10.17.0.0", 16),
				},
			},
			wantErr: true,
		},
		{
			name: "request bigger than alloc range",
			args: args{
				cidrRange:   16,
				subnetRange: mustParseCIDR("10.17.0.0/22"),
				routes:      []netlink.Route{},
			},
			wantErr: true,
		},
		{
			name: "ipv4 in ipv6 range",
			args: args{
				cidrRange:   16,
				subnetRange: mustParseCIDR("10.0.0.0/8"),
				routes: []netlink.Route{
					makeRoute("0:0:0:0:0:ffff:a00:1", 16),
					makeRoute("10.1.0.0", 16),
				},
			},
			want: mustParseCIDR("10.2.0.0/16"),
		},
		{
			name: "no ipv4 in ipv6 range",
			args: args{
				cidrRange:   16,
				subnetRange: mustParseCIDR("10.0.0.0/8"),
				routes: []netlink.Route{
					makeRoute("0:ffff:a00:1:0:0:0:0", 16),
					makeRoute("10.0.0.0", 16),
				},
			},
			want: mustParseCIDR("10.1.0.0/16"),
		},
		{
			name: "nil and zero dst",
			args: args{
				cidrRange:   22,
				subnetRange: mustParseCIDR("10.0.0.0/8"),
				routes: []netlink.Route{
					netlink.Route{
						Dst: nil,
					},
					makeRoute("0.0.0.0", 0),
					makeRoute("10.0.0.0", 22),
					makeRoute("10.0.4.0", 22),
				},
			},
			want: mustParseCIDR("10.0.8.0/22"),
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := FindAvailableSubnet(tt.args.cidrRange, tt.args.subnetRange, tt.args.routes, false)
			if (err != nil) != tt.wantErr {
				t.Errorf("FindAvailableSubnet() error = %v, wantErr %v, got %v", err, tt.wantErr, got)
				return
			}
			if !reflect.DeepEqual(got, tt.want) {
				t.Errorf("FindAvailableSubnet() = %v, want %v", got, tt.want)
			}
		})
	}
}

func mustParseCIDR(s string) *net.IPNet {
	_, subnet, err := net.ParseCIDR(s)
	if err != nil {
		panic(err)
	}
	return subnet
}

func makeRoute(ip string, bits int) netlink.Route {
	return netlink.Route{
		Dst: &net.IPNet{
			IP:   net.ParseIP(ip),
			Mask: net.CIDRMask(bits, 32),
		},
	}
}
