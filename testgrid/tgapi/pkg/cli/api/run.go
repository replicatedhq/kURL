package api

import (
	"fmt"
	"log"
	"net/http"
	"time"

	"github.com/gorilla/mux"
	"github.com/replicatedhq/kurl/testgrid/tgapi/pkg/handlers"
	"github.com/spf13/cobra"
	"github.com/spf13/viper"
)

func RunCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use: "run",
		PreRun: func(cmd *cobra.Command, args []string) {
			viper.BindPFlags(cmd.Flags())
		},
		RunE: func(cmd *cobra.Command, args []string) error {
			r := mux.NewRouter()
			r.Use(mux.CORSMethodMiddleware(r))

			r.HandleFunc("/healthz", handlers.Healthz).Methods("GET")

			r.HandleFunc("/api/v1/config", handlers.WebConfig).Methods("GET", "OPTIONS")
			r.HandleFunc("/api/v1/runs", handlers.ListRuns).Methods("GET", "OPTIONS")
			r.HandleFunc("/api/v1/run/{refId}", handlers.GetRun).Methods("POST", "OPTIONS")
			r.HandleFunc("/api/v1/run/{refId}/addons", handlers.GetRunAddons).Methods("GET", "OPTIONS")
			r.HandleFunc("/api/v1/instance/{instanceId}/logs", handlers.GetInstanceLogs).Methods("GET", "OPTIONS")

			r.HandleFunc("/v1/ref/{refId}/start", handlers.StartRef)

			r.HandleFunc("/v1/instance/{instanceId}/start", handlers.StartInstance).Methods("POST")
			r.HandleFunc("/v1/instance/{instanceId}/logs", handlers.InstanceLogs).Methods("POST")
			r.HandleFunc("/v1/instance/{instanceId}/bundle", handlers.InstanceBundle).Methods("POST")
			r.HandleFunc("/v1/instance/{instanceId}/sonobuoy", handlers.InstanceSonobuoyResults).Methods("POST")

			r.HandleFunc("/v1/dequeue/instance", handlers.DequeueInstance).Methods("GET")

			srv := &http.Server{
				Handler:      r,
				Addr:         ":3000",
				WriteTimeout: 15 * time.Second,
				ReadTimeout:  15 * time.Second,
			}

			fmt.Printf("Starting tgapi on port %d...\n", 3000)

			log.Fatal(srv.ListenAndServe())

			return nil
		},
	}

	return cmd
}
