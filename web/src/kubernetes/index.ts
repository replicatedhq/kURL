import {
  KubeConfig,
  BatchV1Api,
  CoreV1Api,
  V1ConfigMap,
  V1Job} from "@kubernetes/client-node";
import {Service} from "ts-express-decorators";
import { Installer } from "../installers";
import { Templates } from "../util/services/templates";
import { S3Signer } from "../util/persistence/s3";

@Service()
export class Kubernetes {
  private distOrigin: string;
  private ns: string;
  private disabled: boolean;
  private s3Signer: S3Signer;
  private bucket: string;

  constructor(
    private readonly templates: Templates,
  ) {
    this.distOrigin = process.env["KURL_DIST_ORIGIN"] || "";
    this.ns = process.env["KURL_NAMESPACE"] || "kurl";
    this.disabled = !!process.env["AIRGAP_BUNDLING_DISABLED"];
    this.s3Signer = new S3Signer();
  }

  public async runCreateAirgapBundleJob(i: Installer) {
    if (this.disabled) {
      return;
    }
    const kc = new KubeConfig();
    kc.loadFromDefault();
    const coreV1Client: CoreV1Api = kc.makeApiClient(CoreV1Api);
    const batchV1Client: BatchV1Api = kc.makeApiClient(BatchV1Api);

    const name = `create-bundle-${i.id}`;

    const configMap: V1ConfigMap = {
      apiVersion: "v1",
      kind: "ConfigMap",
      metadata: {
        name: `bundle-${i.id}`,
        namespace: this.ns,
      },
      data: {
        "install.sh": this.templates.renderInstallScript(i),
        "join.sh": this.templates.renderJoinScript(i),
        "create-bundle-alpine.sh": this.templates.renderCreateBundleScript(i),
      },
    };
    await coreV1Client.createNamespacedConfigMap(this.ns, configMap);

    const packages: Array<string> = [
      "common.tar.gz",
      `docker-${i.dockerVersion()}.tar.gz`,
      `kubernetes-${i.kubernetesVersion()}.tar.gz`,
    ];
    if (i.weaveVersion()) {
      packages.push(`weave-${i.weaveVersion()}.tar.gz`);
    }
    if (i.rookVersion()) {
      packages.push(`rook-${i.rookVersion()}.tar.gz`);
    }
    if (i.contourVersion()) {
      packages.push(`contour-${i.contourVersion()}.tar.gz`);
    }

    // todo get param from env.
    const { signedUrl } = await this.s3Signer.signPutRequest({
      Bucket: this.bucket,
      Key: `bundles/${i.id}.tar.gz`,
      ContentType: "application/tar+gzip",
    });

    const job: V1Job = {
      apiVersion: "batch/v1",
      kind: "Job",
      metadata: {
        name: name,
        namespace: this.ns,
      },
      spec: {
        activeDeadlineSeconds: 600,
        template: {
          spec: {
            containers: [
              {
                name: "bundle",
                image: "alpine:3.10",
                command: [
                  "/scripts/create-bundle-alpine.sh",
                  signedUrl,
                ].concat(packages),
                volumeMounts: [
                  {
                    name: "scripts",
                    mountPath: "/scripts",
                  },
                ],
              },
            ],
            volumes: [
              {
                name: "scripts",
                configMap: {
                  name: name,
                  defaultMode: 511 // 0777
                },
              },
            ],
          },
        },
      },
    };
    await batchV1Client.createNamespacedJob(this.ns, job);
  };
}
