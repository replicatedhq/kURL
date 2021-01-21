package persistence

import (
	"fmt"
	"sync"
	"time"

	"github.com/DataDog/datadog-go/statsd"
	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/ec2metadata"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/pkg/errors"
)

var (
	StatsdClientNotInitialized = errors.New("statsd client not initialized")

	statsdClient *statsd.Client
	statsdMu     sync.Mutex
)

func InitStatsd(port, namespace string) (*statsd.Client, error) {
	statsdMu.Lock()
	defer statsdMu.Unlock()

	if statsdClient == nil {
		sess, err := session.NewSession(aws.NewConfig())
		if err != nil {
			return nil, errors.Wrap(err, "failed to init AWS session")
		} else {
			ip, err := getInstancePrivateIP(sess)
			if err != nil {
				return nil, errors.Wrap(err, "failed to find instance ip")
			}
			c, err := statsd.New(fmt.Sprintf("%s:%s", ip, port))
			if err != nil {
				return nil, errors.Wrapf(err, "failed to init statsd client targeting ip %s", ip)
			}
			// prefix every metric with the app name
			c.Namespace = namespace
			statsdClient = c
		}
	}
	return statsdClient, nil
}

func Statsd() *statsd.Client {
	return statsdClient
}

func MaybeSendStatsdTiming(name string, value time.Duration, tags []string, rate float64) error {
	client := Statsd()
	if client == nil {
		return StatsdClientNotInitialized
	}
	return client.Timing(name, value, tags, rate)
}

func MaybeSendStatsdGauge(name string, value float64, tags []string, rate float64) error {
	client := Statsd()
	if client == nil {
		return StatsdClientNotInitialized
	}
	return client.Gauge(name, value, tags, rate)
}

func getInstancePrivateIP(sess *session.Session) (string, error) {
	ec2metadataSvc := ec2metadata.New(sess)
	doc, err := ec2metadataSvc.GetInstanceIdentityDocument()
	if err != nil {
		return "", err
	}
	return doc.PrivateIP, nil
}
