package cli

import (
	"net"

	"github.com/pkg/errors"
	"github.com/replicatedhq/kurl/pkg/netutils"
	"github.com/spf13/cobra"
)

func newUtilCommand(cli CLI) *cobra.Command {
	cmd := &cobra.Command{
		Use:   "util",
		Short: "Utility commands",
		PersistentPreRunE: func(cmd *cobra.Command, args []string) error {
			return cli.GetViper().BindPFlags(cmd.PersistentFlags())
		},
		PreRunE: func(cmd *cobra.Command, args []string) error {
			return cli.GetViper().BindPFlags(cmd.Flags())
		},
	}
	return cmd
}

func newUtilIfaceFromIPCommand(_ CLI) *cobra.Command {
	cmd := &cobra.Command{
		Use:   "iface-from-ip IP",
		Short: "Gets the interface name for a given IP address",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			ip := net.ParseIP(args[0])
			if ip.To16() == nil {
				return errors.New("invalid IP address")
			}
			iface, err := netutils.GetInterfaceByIPv6(ip)
			if err == nil {
				cmd.Println(iface.Name)
				return nil
			}
			if ip.To4() != nil {
				iface, err := netutils.GetInterfaceByIP(ip)
				if err != nil {
					return err
				}
				cmd.Println(iface.Name)
				return nil
			}
			return err
		},
	}
	return cmd
}

func newUtilDefaultIfaceCommand(_ CLI) *cobra.Command {
	ipv6 := false
	cmd := &cobra.Command{
		Use:   "default-gateway-iface",
		Short: "Gets the default gateway interface name",
		RunE: func(cmd *cobra.Command, args []string) error {
			if ipv6 {
				iface, err := netutils.GetDefaultV6GatewayInterface()
				if err != nil {
					return err
				}
				cmd.Println(iface.Name)
				return nil
			}
			iface, err := netutils.GetDefaultGatewayInterface()
			if err != nil {
				return err
			}
			cmd.Println(iface.Name)
			return nil
		},
	}
	cmd.Flags().BoolVar(&ipv6, "ipv6", false, "Get the default IPv6 interface")
	return cmd
}
