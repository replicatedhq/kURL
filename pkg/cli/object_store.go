package cli

import (
	"context"
	"fmt"
	"log"

	"github.com/minio/minio-go"
	"github.com/spf13/cobra"
	"github.com/spf13/pflag"
	"github.com/spf13/viper"
)

func newObjectStoreCmd(cli CLI) *cobra.Command {
	cmd := &cobra.Command{
		Use:   "object-store",
		Short: "Perform operations related to the object store within a kURL cluster",
		PersistentPreRunE: func(cmd *cobra.Command, _ []string) error {
			return cli.GetViper().BindPFlags(cmd.PersistentFlags())
		},
		PreRunE: func(cmd *cobra.Command, _ []string) error {
			return cli.GetViper().BindPFlags(cmd.Flags())
		},
	}
	return cmd
}

func newSyncObjectStoreCmdDeprecated(cli CLI) *cobra.Command {
	cmd := newSyncObjectStoreCmd(cli)
	cmd.Use = "sync-object-store"
	cmd.Deprecated = "use 'kurl object-store sync' instead"
	cmd.Hidden = true
	return cmd
}

func newSyncObjectStoreCmd(_ CLI) *cobra.Command {
	var srcHost string
	var srcAccessKeyID string
	var srcAccessKeySecret string

	var dstHost string
	var dstAccessKeyID string
	var dstAccessKeySecret string

	syncObjectStoreCmd := &cobra.Command{
		Use:   "sync",
		Short: "Copies buckets and objects from one object store to another",
		PreRunE: func(cmd *cobra.Command, _ []string) error {
			v := viper.New()
			v.SetEnvPrefix("KURL")
			v.AutomaticEnv()
			cmd.Flags().VisitAll(
				func(f *pflag.Flag) {
					if f.Changed || !v.IsSet(f.Name) {
						return
					}
					value := fmt.Sprintf("%v", v.Get(f.Name))
					_ = cmd.Flags().Set(f.Name, value)
				},
			)
			return nil
		},
		Run: func(_ *cobra.Command, _ []string) {
			src, err := minio.New(
				srcHost,
				srcAccessKeyID,
				srcAccessKeySecret,
				false,
			)
			if err != nil {
				log.Panic(err)
			}

			dst, err := minio.New(
				dstHost,
				dstAccessKeyID,
				dstAccessKeySecret,
				false,
			)
			if err != nil {
				log.Panic(err)
			}

			ctx := context.Background()

			srcBuckets, err := src.ListBuckets()
			if err != nil {
				log.Fatalf("Failed to list buckets in %s: %v", srcHost, err)
			}

			for _, srcBucket := range srcBuckets {
				fmt.Printf("Syncing %s from %s to %s\n", srcBucket.Name, srcHost, dstHost)

				count, err := syncBucket(ctx, src, dst, srcBucket.Name)
				if err != nil {
					log.Fatal(err)
				}

				fmt.Printf("Successfully synced %d objects in bucket %s from %s to %s\n", count, srcBucket.Name, srcHost, dstHost)
			}

			fmt.Printf("Successfully synced %d buckets from %s to %s\n", len(srcBuckets), srcHost, dstHost)
		},
	}

	syncObjectStoreCmd.Flags().StringVar(&srcHost, "source_host", "", "Hostname of the source object store")
	syncObjectStoreCmd.Flags().StringVar(&srcAccessKeyID, "source_access_key_id", "", "Access key ID for the source object store")
	syncObjectStoreCmd.Flags().StringVar(&srcAccessKeySecret, "source_access_key_secret", "", "Access key secret for the source object store")

	syncObjectStoreCmd.Flags().StringVar(&dstHost, "dest_host", "", "Hostname of the destination object store")
	syncObjectStoreCmd.Flags().StringVar(&dstAccessKeyID, "dest_access_key_id", "", "Access key ID for the destination object store")
	syncObjectStoreCmd.Flags().StringVar(&dstAccessKeySecret, "dest_access_key_secret", "", "Access key secret for the destination object store")

	return syncObjectStoreCmd
}

func syncBucket(ctx context.Context, src *minio.Client, dst *minio.Client, bucket string) (int, error) {
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()

	count := 0

	exists, err := dst.BucketExists(bucket)
	if err != nil {
		return count, fmt.Errorf("Failed to check if bucket %q exists in destination: %v", bucket, err)
	}
	if !exists {
		if err := dst.MakeBucket(bucket, ""); err != nil {
			return count, fmt.Errorf("Failed to make bucket %q in destination: %v", bucket, err)
		}
	}

	srcObjectInfoChan := src.ListObjects(bucket, "", true, ctx.Done())

	for srcObjectInfo := range srcObjectInfoChan {
		srcObject, err := src.GetObject(bucket, srcObjectInfo.Key, minio.GetObjectOptions{})
		if err != nil {
			return count, fmt.Errorf("Get %s from source: %v", srcObjectInfo.Key, err)
		}

		_, err = dst.PutObject(bucket, srcObjectInfo.Key, srcObject, srcObjectInfo.Size, minio.PutObjectOptions{
			ContentType:     srcObjectInfo.ContentType,
			ContentEncoding: srcObjectInfo.Metadata.Get("Content-Encoding"),
		})
		srcObject.Close()
		if err != nil {
			return count, fmt.Errorf("Failed to copy object %s to destination: %v", srcObjectInfo.Key, err)
		}

		count++
	}

	return count, nil
}
