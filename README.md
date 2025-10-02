k8s-local/
├─ README.md
├─ Makefile
├─ bootstrap.sh
├─ namespaces.yaml
├─ components/
│  ├─ argo-cd/
│  │  └─ ingress.yaml   
│  │  └─ values.yaml
│  ├─ harbor/
│  │  └─ ingress.yaml 
│  │  └─ values.yaml
│  ├─ kong/
│  │  └─ values.yaml
│  ├─ monitoring/                 # Prometheus + Grafana + Alertmanager
│  │  └─ ingress.yaml 
│  │  └─ kube-prom-stack.values.yaml
│  ├─ logging/                    # Loki + Promtail (tuỳ chọn)
│  │  └─ loki-stack.values.yaml
│  └─ cert-manager/               # optional (để sau này bật TLS dev)
│     └─ values.yaml
└─ demo/
   ├─ echo-deploy.yaml
   └─ echo-ingress.yaml



make install-all  # cài ArgoCD + Harbor + Kong + Monitoring + Logging


make urls -> expose port to browser
make argopwd -> get passwork argoCD (admin/password)


make up
make add-repos
make ns
make deploy
make expose-services
minikube -n kong service kong-kong-proxy
kubectl -n kong port-forward svc/kong-kong-proxy 30000:80

robot$test
VYKsi3fqvRT39oPBezJCBPK4gZ63ZB9G

robot$library+ci - wJoKqc7XdEs9dz0jdHb9BaRyoiqgwBob