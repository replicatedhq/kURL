package cli

import (
	"fmt"
	"net"

	"github.com/pkg/errors"
	"github.com/replicatedhq/kurl/pkg/netutils"
	"github.com/spf13/cobra"
)

func newNetutilCommand(cli CLI) *cobra.Command {
	cmd := &cobra.Command{
		Use:   "netutil",
		Short: "Networking utility commands",
		PersistentPreRunE: func(cmd *cobra.Command, _ []string) error {
			return cli.GetViper().BindPFlags(cmd.PersistentFlags())
		},
		PreRunE: func(cmd *cobra.Command, _ []string) error {
			return cli.GetViper().BindPFlags(cmd.Flags())
		},
	}
	return cmd
}

func newNetutilIfaceFromIPCommand(cli CLI) *cobra.Command {
	cmd := &cobra.Command{
		Use:   "iface-from-ip IP",
		Short: "Gets the interface name for a given IP address",
		Args:  cobra.ExactArgs(1),
		RunE: func(_ *cobra.Command, args []string) error {
			ip := net.ParseIP(args[0])
			if ip.To16() == nil {
				return errors.New("invalid IP address")
			}
			iface, err := netutils.GetInterfaceByIPv6(ip)
			if err == nil {
				fmt.Fprintln(cli.Stdout(), iface.Name)
				return nil
			}
			if ip.To4() != nil {
				iface, err := netutils.GetInterfaceByIP(ip)
				if err != nil {
					return err
				}
				fmt.Fprintln(cli.Stdout(), iface.Name)
				return nil
			}
			return err
		},
	}
	return cmd
}

func newNetutilDefaultIfaceCommand(cli CLI) *cobra.Command {
	ipv6 := false
	cmd := &cobra.Command{
		Use:   "default-gateway-iface",
		Short: "Gets the default gateway interface name",
		RunE: func(_ *cobra.Command, _ []string) error {
			if ipv6 {
				iface, err := netutils.GetDefaultV6GatewayInterface()
				if err != nil {
					return err
				}
				fmt.Fprintln(cli.Stdout(), iface.Name)
				return nil
			}
			iface, err := netutils.GetDefaultGatewayInterface()
			if err != nil {
				return err
			}
			fmt.Fprintln(cli.Stdout(), iface.Name)
			return nil
		},
	}

	cmd.Flags().BoolVar(&ipv6, "ipv6", false, "Get the default IPv6 interface")
	return cmd
}
