package persistence

import (
	"sync"

	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/s3"
	"github.com/aws/aws-sdk-go/service/s3/s3manager"
)

var s3Client *s3.S3
var s3UploadManager *s3manager.Uploader
var s3Mu sync.Mutex

func GetS3Client() *s3.S3 {
	s3Mu.Lock()
	defer s3Mu.Unlock()

	if s3Client == nil {
		s3Client = s3.New(session.New())
	}
	return s3Client
}

func GetS3Uploader() *s3manager.Uploader {
	s3Mu.Lock()
	defer s3Mu.Unlock()

	if s3UploadManager == nil {
		s3UploadManager = s3manager.NewUploader(session.New())
	}
	return s3UploadManager
}
