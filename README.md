# Curiefense NGINX Ingress

This repo contains a custom NGINX ingress build based on Curiefense's [custom build](https://github.com/curiefense/curiefense/blob/445c48fed33c05743004b19d8816980b318205b5/curiefense/images/curiefense-nginx-ingress/Dockerfile).

Primary differences:

- NGINX Ingress upgraded to 2.0.3
- Openresty upgraded to the latest version
- Curiesync is not installed (should be a sidecar)
- There is an initial bootstrap config in case no sidecar pulls the real config
- Curielogger defaults to `curielogger.curiefense.svc.cluster.local` so NGINX can be installed in a separate namespace
- Curiefense can be enabled with `custom.nginx.org/enable-curiefense` annotation selectively

## Installation

Follow the guide I wrote earlier: https://docs.curiefense.io/installation/deployment-first-steps/nginx-ingress

When you get to installing the ingress controller:

Create a namespace for the ingress controller:

```shell
kubectl create namespace nginx-ingress
```

Create a `curiesync-secret.yaml` with the following content:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: curiesync
data:
  curiesync.env: |
    export CURIE_BUCKET_LINK=s3://my-curiefense-test/prod/manifest.json
    export CURIE_S3_ACCESS_KEY=YOUR_ACCESS_KEY_ID
    export CURIE_S3_SECRET_KEY=YOUR_SECRET_ACCESS_KEY
```

Apply the ConfigMap:

```shell
kubectl --namespace nginx-ingress apply -f curiesync-secret.yaml
```

Create a `values.ingress.yaml` with the following content:

```yaml
controller:
  image:
    repository: ghcr.io/sagikazarmark/curiefense-nginx-ingress
    tag: main
    pullPolicy: Always

  volumes:
    - name: curiesync
      secret:
        secretName: curiesync
    - name: curieconf
      emptyDir: {}

  volumeMounts:
    - name: curieconf
      mountPath: /config

  initContainers:
    - name: curiesync-init
      image: curiefense/curiesync:main
      env:
        - name: RUN_MODE
          value: COPY_BOOTSTRAP
      volumeMounts:
        - name: curiesync
          mountPath: /etc/curiefense
        - name: curieconf
          mountPath: /config

  extraContainers:
    - name: curiesync
      image: curiefense/curiesync:main
      env:
        - name: RUN_MODE
          value: PERIODIC_SYNC
      volumeMounts:
        - name: curiesync
          mountPath: /etc/curiefense
        - name: curieconf
          mountPath: /config
```

Instead of using the official Helm chart from the Helm repo, do this:

```shell
git clone git@github.com:sagikazarmark/kubernetes-ingress.git -b extra-containers-backport
helm -n nginx-ingress install -f values.ingress.yaml ingress ./kubernetes-ingress/deployments/helm-chart
```

Proceed with the installation of Curiefense.

## Potential future improvements

- Syslog should also be a sidecar container AND/OR curiefense log should also be sent to stdout
- Curielogger service should be configurable

## Getting closer to production

- Curiesync sidecar should be injected by a mutation webhook? (Right now the NGINX Helm chart provides most of the options we need for manual and automatic injection)
- Use the NGINX ingress controller operator?
