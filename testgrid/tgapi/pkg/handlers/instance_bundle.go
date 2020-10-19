package handlers

import (
	"fmt"
	"net/http"
	"os"
	"time"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/service/s3/s3manager"
	"github.com/gorilla/mux"
	"github.com/pkg/errors"
	"github.com/replicatedhq/kurl/testgrid/tgapi/pkg/logger"
	"github.com/replicatedhq/kurl/testgrid/tgapi/pkg/persistence"
)

func InstanceBundle(w http.ResponseWriter, r *http.Request) {
	bucket := os.Getenv("SUPPORT_BUNDLE_BUCKET")
	if bucket == "" {
		w.WriteHeader(http.StatusNotImplemented)
		return
	}

	instanceID := mux.Vars(r)["instanceId"]

	input := &s3manager.UploadInput{
		Body:   aws.ReadSeekCloser(r.Body),
		Bucket: aws.String(bucket),
		Key:    aws.String(fmt.Sprintf("%s-%d/bundle.tgz", instanceID, time.Now().Unix())),
	}

	s3Uploader := persistence.GetS3Uploader()
	_, err := s3Uploader.UploadWithContext(r.Context(), input)
	if err != nil {
		logger.Error(errors.Errorf("Failed to upload bundle for instance %s; %v", instanceID, err))
		w.WriteHeader(http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusNoContent)
	return
}
