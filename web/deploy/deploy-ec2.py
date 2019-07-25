#!/bin/python
import boto
from boto.sqs.message import RawMessage
import json
import os


def addMessageToQueue(project, sha):
    # Data required by the API
    data = {"project": project, "sha": sha}

    # Connect to SQS and open the queue
    sqs = boto.connect_sqs(os.environ["AWS_ACCESS_KEY_ID"],
                           os.environ["AWS_SECRET_ACCESS_KEY"])
    q = sqs.create_queue("chatops-deployer-staging")

    # Put the message in the queue
    m = RawMessage()
    m.set_body(json.dumps(data))
    q.write(m)


addMessageToQueue("install-scripts",
                  os.environ["CIRCLE_SHA1"][:7])