## Setting up a nodeless Kubernetes cluster

Enable the aws, nodeless and calico plugins, and disable prometheus, weave, rook, kotsadm and contour:

    diff --git a/scripts/Manifest b/scripts/Manifest
    index 04d4f74..a467744 100644
    --- a/scripts/Manifest
    +++ b/scripts/Manifest
    @@ -1,12 +1,15 @@
     KUBERNETES_VERSION=1.15.3
     DOCKER_VERSION=18.09.8
    -WEAVE_VERSION=2.5.2
    -ROOK_VERSION=1.0.4
    -CONTOUR_VERSION=0.14.0
    +#WEAVE_VERSION=2.5.2
    +#ROOK_VERSION=1.0.4
    +#CONTOUR_VERSION=0.14.0
     REGISTRY_VERSION=2.7.1
    -PROMETHEUS_VERSION=0.33.0
    -KOTSADM_VERSION=1.6.0
    +#PROMETHEUS_VERSION=0.33.0
    +#KOTSADM_VERSION=1.6.0
     KOTSADM_APPLICATION_SLUG=sentry-enterprise
    +AWS_VERSION=0.0.1
    +NODELESS_VERSION=0.0.1
    +CALICO_VERSION=3.9.1

     KURL_URL=

The AWS cloud provider in Kubernetes needs cloud resources to be tagged with the cluster name, otherwise it won't use them. For an example on how to create a VPC, subnet, route table, instance, IAM profile and security groups, everything tagged correctly, please see the file `addons/aws/0.0.1/create-vpc.tf`.
