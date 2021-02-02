package api

import (
	"fmt"
	"log"
	"net/http"
	"time"

	"github.com/gorilla/mux"
	"github.com/replicatedhq/kurl/testgrid/tgapi/pkg/handlers"
	"github.com/replicatedhq/kurl/testgrid/tgapi/pkg/middleware"
	"github.com/replicatedhq/kurl/testgrid/tgapi/pkg/persistence"
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

			rAuth := r.NewRoute().Subrouter()
			rAuth.Use(middleware.APITokenAuthentication(viper.GetString("api-token")))

			r.HandleFunc("/healthz", handlers.Healthz).Methods("GET")

			r.HandleFunc("/api/v1/config", handlers.WebConfig).Methods("GET", "OPTIONS")
			r.HandleFunc("/api/v1/runs", handlers.ListRuns).Methods("GET", "OPTIONS")
			r.HandleFunc("/api/v1/run/{refId}", handlers.GetRun).Methods("POST", "OPTIONS")
			r.HandleFunc("/api/v1/run/{refId}/addons", handlers.GetRunAddons).Methods("GET", "OPTIONS")
			r.HandleFunc("/api/v1/instance/{instanceId}/logs", handlers.GetInstanceLogs).Methods("GET", "OPTIONS")
			r.HandleFunc("/api/v1/instance/{instanceId}/sonobuoy", handlers.GetInstanceSonobuoyResults).Methods("GET", "OPTIONS")

			rAuth.HandleFunc("/v1/ref/{refId}/start", handlers.StartRef).Methods("POST")

			r.HandleFunc("/v1/instance/{instanceId}/start", handlers.StartInstance).Methods("POST")     // called when vm image has been loaded and k8s object created
			r.HandleFunc("/v1/instance/{instanceId}/running", handlers.RunningInstance).Methods("POST") // called by script running within vm
			r.HandleFunc("/v1/instance/{instanceId}/finish", handlers.FinishInstance).Methods("POST")

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

			if _, err := persistence.InitStatsd(
				"8125",
				"kurl_testgrid_api.",
			); err != nil {
				log.Printf("Failed to initialize statsd client: %v", err)
			}

			log.Fatal(srv.ListenAndServe())

			return nil
		},
	}

	cmd.Flags().String("api-token", "", "API token for authentication")

	return cmd
}
