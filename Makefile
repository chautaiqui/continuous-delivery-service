# =======================
#  K8S-LOCAL Makefile
# =======================
SHELL := /bin/bash
.DEFAULT_GOAL := deploy

## --------------------- VARIABLES ---------------------
# Namespaces
NS_ARGO       := argocd
NS_HARBOR     := harbor
NS_KONG       := kong
NS_MON        := monitoring
NS_LOG        := logging
NS_CERT       := cert-manager
NS_DEMO       := demo
NS_JENKINS    := jenkins

# All namespaces (for cleanup/reset)
ALL_NS := $(NS_ARGO) $(NS_HARBOR) $(NS_KONG) $(NS_MON) $(NS_LOG) $(NS_CERT) $(NS_DEMO)

# Common files
NS_FILE := namespaces.yaml

# Convenience
MINIKUBE_DRIVER ?= docker
MINIKUBE_CPUS   ?= 6
MINIKUBE_MEM    ?= 8g

## --------------------- PHONY RULES ---------------------
.PHONY: help up down reset \
        add-repos ns \
        install-all deploy \
        install-argo install-harbor install-kong install-monitoring install-logging install-cert \
        fix-kong-crds \
        expose-services \
        info urls argopwd kong-url \
        check wait ingresses \
        uninstall

help:
	@echo "Usage: make <target>"
	@echo ""
	@echo "Cluster Management:"
	@echo "  up                 - Start minikube cluster if not running"
	@echo "  down               - Delete the minikube cluster"
	@echo "  reset              - Uninstall releases & delete component namespaces"
	@echo ""
	@echo "Setup & Installation:"
	@echo "  add-repos          - Add all required Helm repos"
	@echo "  ns                 - Create all required namespaces from namespaces.yaml"
	@echo "  install-all        - Run up, add-repos, ns, and install core components"
	@echo "  deploy             - Alias for install-all (default goal)"
	@echo "  install-cert       - Install Cert-Manager (with CRDs)"
	@echo "  install-argo       - Install Argo CD"
	@echo "  install-harbor     - Install Harbor"
	@echo "  install-kong       - Install Kong API Gateway/Ingress Controller"
	@echo "  install-monitoring - Install Kube Prometheus Stack (Prometheus, Grafana)"
	@echo "  install-logging    - Install Loki Stack (Loki, Promtail)"
	@echo ""
	@echo "Service Exposure:"
	@echo "  expose-services    - Apply all ingress.yaml files to expose via Kong"
	@echo ""
	@echo "Helpers & Info:"
	@echo "  info               - Show access URLs and ArgoCD password"
	@echo "  urls               - Show NodePort URLs (for debugging)"
	@echo "  argopwd            - Get ArgoCD initial admin password"
	@echo "  kong-url           - Get base URL for the Kong proxy"
	@echo "  check              - Show status of pods, services, and ingresses"
	@echo "  wait               - Wait for core component deployments to be ready"
	@echo "  ingresses          - List all ingresses in the cluster"
	@echo "  fix-kong-crds      - Reinstall Kong + clean CRDs (if CRDs are broken)"
	@echo ""
	@echo "Cleanup:"
	@echo "  uninstall          - Uninstall all Helm releases"

## ----------------- CLUSTER BOOTSTRAP -----------------
up:
	@minikube status >/dev/null 2>&1 || minikube start --cpus=$(MINIKUBE_CPUS) --memory=$(MINIKUBE_MEM) --driver=$(MINIKUBE_DRIVER)
	@echo "✅ Minikube is running."

add-repos:
	@helm repo add argo https://argoproj.github.io/argo-helm >/dev/null || true
	@helm repo add harbor https://helm.goharbor.io >/dev/null || true
	@helm repo add kong https://charts.konghq.com >/dev/null || true
	@helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null || true
	@helm repo add grafana https://grafana.github.io/helm-charts >/dev/null || true
	@helm repo add jetstack https://charts.jetstack.io >/dev/null || true
	@helm repo add bitnami https://charts.bitnami.com/bitnami >/dev/null || true
	@helm repo update >/dev/null
	@echo "✅ Helm repos are up to date."

ns:
	@test -f $(NS_FILE) || (echo "namespaces.yaml not found"; exit 1)
	@kubectl apply -f $(NS_FILE)
	@echo "✅ Namespaces created."

## ---------------- COMPONENT INSTALLS -----------------
install-cert:
	@helm upgrade --install cert-manager jetstack/cert-manager \
	  -n $(NS_CERT) --create-namespace \
	  --set crds.enabled=true \
	  -f components/cert-manager/values.yaml --wait
	@echo "✅ cert-manager installed."

install-argo:
	@helm upgrade --install argocd argo/argo-cd \
	  -n $(NS_ARGO) --create-namespace \
	  -f components/argo-cd/values.yaml --wait
	@echo "✅ Argo CD installed."

install-harbor:
	@helm upgrade --install harbor harbor/harbor \
	  -n $(NS_HARBOR) --create-namespace \
	  -f components/harbor/values.yaml --wait
	@echo "✅ Harbor installed."

install-kong:
	@helm upgrade --install kong kong/kong \
	  -n $(NS_KONG) --create-namespace \
	  -f components/kong/values.yaml --wait
	@echo "✅ Kong installed."

fix-kong-crds:
	@echo "🔥 Deleting existing Kong CRDs..."
	@kubectl get crd -o name | grep "konghq.com" | xargs -r kubectl delete
	@$(MAKE) install-kong

install-monitoring:
	@helm upgrade --install kps prometheus-community/kube-prometheus-stack \
	  -n $(NS_MON) --create-namespace \
	  -f components/monitoring/kube-prom-stack.values.yaml --wait
	@echo "✅ Monitoring stack installed."

install-logging:
	@helm upgrade --install loki grafana/loki-stack \
	  -n $(NS_LOG) --create-namespace \
	  -f components/logging/loki-stack.values.yaml --wait
	@echo "✅ Logging stack installed."

install-all: up add-repos ns install-cert install-argo install-harbor install-kong install-monitoring
	@echo ""
	@echo "🚀 All components installed successfully!"
	@echo "Next steps:"
	@echo "1) Expose services via Kong: make expose-services"
	@echo "2) Get access details:      make info"

deploy: install-all

## ----------------- SERVICE EXPOSURE ------------------
expose-services:
	@echo "⏳ Ensuring Kong is ready..."
	@kubectl rollout status deploy -n $(NS_KONG) kong-kong --timeout=180s || true
	@echo "🔍 Applying Ingress manifests..."
	@kubectl apply -f components/argo-cd/ingress.yaml
	@kubectl apply -f components/harbor/ingress.yaml || true
	@kubectl apply -f components/monitoring/ingress.yaml
	@[ -f demo/echo-ingress.yaml ] && kubectl apply -f demo/echo-ingress.yaml || true
	@echo "✅ Ingress resources applied."
	@echo
	@echo "🧪 Quick test (Kong NodePort):"
	@echo "  KONG=http://$$(minikube ip):30000"
	@echo "  curl -I -H 'Host: argocd.internal'       $$KONG/"
	@echo "  curl -I -H 'Host: harbor.internal'       $$KONG/"
	@echo "  curl -I -H 'Host: grafana.internal'      $$KONG/"
	@echo "  curl -I -H 'Host: prometheus.internal'   $$KONG/"
	@echo "  curl -I -H 'Host: alertmanager.internal' $$KONG/"
	@echo "  curl -I -H 'Host: echo.internal'         $$KONG/ || true"

## ------------------- HELPERS & INFO --------------------
info:
	@echo "\n🔗 Kong Gateway URL:"
	@KONG_URL=$$(make --no-print-directory kong-url); echo "$$KONG_URL"
	@echo "\n-- Access URLs (hosts -> Kong) --"
	@echo "ArgoCD:      argocd.internal        -> $$KONG_URL/"
	@echo "Harbor:      harbor.internal        -> $$KONG_URL/"
	@echo "Grafana:     grafana.internal       -> $$KONG_URL/"
	@echo "Prometheus:  prometheus.internal    -> $$KONG_URL/"
	@echo "Alertmanager:alertmanager.internal  -> $$KONG_URL/"
	@echo "Echo (demo): echo.internal          -> $$KONG_URL/"
	@echo "\n🔑 ArgoCD Admin Password:"
	@$(MAKE) --no-print-directory argopwd

kong-url:
	@SVC=$$(kubectl -n $(NS_KONG) get svc kong-kong-proxy -o name 2>/dev/null | cut -d/ -f2); \
	if [ -z "$$SVC" ]; then echo "Kong proxy service not found"; exit 1; fi; \
	IP=$$(minikube ip); \
	PORT=$$(kubectl -n $(NS_KONG) get svc $$SVC -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}'); \
	echo "http://$$IP:$${PORT:-30000}"

argopwd:
	@kubectl -n $(NS_ARGO) get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo

urls:
	@echo "--- NodePort URLs (for debugging) ---"
	@minikube service list || true

check:
	@echo "\n--- Pods ---"; kubectl get pods -A
	@echo "\n--- Services ---"; kubectl get svc -A
	@echo "\n--- Ingresses ---"; kubectl get ing -A || true

ingresses:
	@kubectl get ing -A

wait:
	@echo "⏳ Waiting for core pods to be ready..."
	@kubectl wait --for=condition=Available deployment -n $(NS_ARGO) argocd-server --timeout=600s || true
	@kubectl rollout status deploy -n $(NS_HARBOR) harbor-core --timeout=600s || true
	@kubectl rollout status deploy -n $(NS_KONG) kong-kong --timeout=600s || true
	@kubectl rollout status deploy -n $(NS_MON) kps-grafana --timeout=600s || true
	@echo "✅ Core pods are ready."

## ---------------------- CLEANUP ----------------------
uninstall:
	@echo "🔥 Uninstalling all Helm releases..."
	-@helm uninstall argocd -n $(NS_ARGO) || true
	-@helm uninstall harbor -n $(NS_HARBOR) || true
	-@helm uninstall kong   -n $(NS_KONG) || true
	-@helm uninstall kps    -n $(NS_MON)  || true
	-@helm uninstall loki   -n $(NS_LOG)  || true
	-@helm uninstall cert-manager -n $(NS_CERT) || true
	@echo "✅ Helm releases removed."

reset: uninstall
	@echo "🔥 Deleting component namespaces..."
	@kubectl delete ns $(ALL_NS) --ignore-not-found
	@echo "✅ Namespaces deleted."

down:
	@echo "🔥 Deleting minikube cluster..."
	@minikube delete
	@echo "✅ Minikube deleted."
