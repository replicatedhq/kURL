package api

import (
	"fmt"
	"log"
	"net/http"
	"os"
	"time"

	ghandlers "github.com/gorilla/handlers"
	"github.com/gorilla/mux"
	"github.com/replicatedhq/kurl/testgrid/tgapi/pkg/handlers"
	"github.com/replicatedhq/kurl/testgrid/tgapi/pkg/metrics"
	"github.com/replicatedhq/kurl/testgrid/tgapi/pkg/middleware"
	"github.com/replicatedhq/kurl/testgrid/tgapi/pkg/persistence"
	"github.com/replicatedhq/kurl/testgrid/tgapi/pkg/version"
	"github.com/spf13/cobra"
	"github.com/spf13/viper"
)

func RunCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use: "run",
		PreRun: func(cmd *cobra.Command, args []string) {
			viper.BindPFlags(cmd.PersistentFlags())
			viper.BindPFlags(cmd.Flags())
		},
		RunE: func(cmd *cobra.Command, args []string) error {
			rRoot := mux.NewRouter()
			rRoot.Use(mux.CORSMethodMiddleware(rRoot))

			rRoot.HandleFunc("/healthz", handlers.Healthz).Methods("GET")

			r := rRoot.NewRoute().Subrouter()
			r.Use(loggingMiddleware)

			rAuth := r.NewRoute().Subrouter()
			rAuth.Use(middleware.APITokenAuthentication(viper.GetString("api-token")))

			r.HandleFunc("/api/v1/config", handlers.WebConfig).Methods("GET", "OPTIONS")
			r.HandleFunc("/api/v1/runs", handlers.ListRuns).Methods("GET", "OPTIONS")
			r.HandleFunc("/api/v1/run/{refId}", handlers.GetRun).Methods("POST", "OPTIONS")
			r.HandleFunc("/api/v1/run/{refId}/addons", handlers.GetRunAddons).Methods("GET", "OPTIONS")
			r.HandleFunc("/api/v1/instance/{instanceId}/logs", handlers.GetInstanceLogs).Methods("GET", "OPTIONS")
			r.HandleFunc("/api/v1/instance/{instanceId}/sonobuoy", handlers.GetInstanceSonobuoyResults).Methods("GET", "OPTIONS")
			r.HandleFunc("/api/v1/instance/{nodeId}/node-logs", handlers.GetNodeLogs).Methods("GET")

			rAuth.HandleFunc("/v1/ref/{refId}/start", handlers.StartRef).Methods("POST")

			r.HandleFunc("/v1/instance/{instanceId}/start", handlers.StartInstance).Methods("POST")     // called when vm image has been loaded and k8s object created
			r.HandleFunc("/v1/instance/{instanceId}/running", handlers.RunningInstance).Methods("POST") // called by script running within vm
			r.HandleFunc("/v1/instance/{instanceId}/finish", handlers.FinishInstance).Methods("POST")
			r.HandleFunc("/v1/instance/{instanceId}/join-command", handlers.AddNodeJoinCommand).Methods("POST")
			r.HandleFunc("/v1/instance/{instanceId}/join-command", handlers.GetNodeJoinCommand).Methods("GET")
			r.HandleFunc("/v1/instance/{instanceId}/status", handlers.GetRunStatus).Methods("GET")
			r.HandleFunc("/v1/instance/{instanceId}/cluster-node", handlers.AddClusterNode).Methods("POST")
			r.HandleFunc("/v1/instance/{nodeId}/node-status", handlers.UpdateNodeStatus).Methods("PUT")
			r.HandleFunc("/v1/instance/{nodeId}/node-logs", handlers.NodeLogs).Methods("PUT")
			r.HandleFunc("/v1/instance/{nodeId}/node-status", handlers.GetNodeStatus).Methods("GET")

			r.HandleFunc("/v1/instance/{instanceId}/logs", handlers.InstanceLogs).Methods("POST")
			r.HandleFunc("/v1/instance/{instanceId}/bundle", handlers.InstanceBundle).Methods("POST")
			r.HandleFunc("/v1/instance/{instanceId}/sonobuoy", handlers.InstanceSonobuoyResults).Methods("POST")

			r.HandleFunc("/v1/dequeue/instance", handlers.DequeueInstance).Methods("GET")
			r.HandleFunc("/v1/dequeue/ref/{refId}/instance", handlers.DequeueInstanceWithRef).Methods("GET")
			r.HandleFunc("/v1/dequeue/ref/{refId}/skip", handlers.SkipInstances).Methods("POST")

			r.HandleFunc("/v1/runner/status", handlers.RunnerStatus).Methods("POST")

			srv := &http.Server{
				Handler:      rRoot,
				Addr:         ":3000",
				WriteTimeout: 15 * time.Second,
				ReadTimeout:  15 * time.Second,
			}

			fmt.Printf("Starting tgapi on port %d...\n", 3000)
			version.Print()

			if _, err := persistence.InitStatsd(
				"8125",
				"kurl_testgrid_api.",
			); err != nil {
				log.Printf("Failed to initialize statsd client: %v", err)
			}

			go metrics.PollTestStats()

			log.Fatal(srv.ListenAndServe())

			return nil
		},
	}

	cmd.Flags().String("api-token", "", "API token for authentication")

	return cmd
}

func loggingMiddleware(next http.Handler) http.Handler {
	return ghandlers.LoggingHandler(os.Stdout, next)
}
