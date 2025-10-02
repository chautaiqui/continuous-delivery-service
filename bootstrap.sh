#!/usr/bin/env bash
set -euo pipefail
echo "==> namespaces"; kubectl apply -f namespaces.yaml
echo "==> helm repos"; make add-repos
echo "==> argo";       make install-argo
echo "==> harbor";     make install-harbor
echo "==> kong";       make install-kong
echo "==> monitoring"; make install-monitoring
echo "==> logging";    make install-logging
echo "==> wait..."
kubectl wait --for=condition=Available deployment -n argocd argocd-server --timeout=300s || true
kubectl rollout status deploy -n harbor harbor-core --timeout=300s || true
kubectl rollout status deploy -n kong kong --timeout=300s || true
echo "==> done. run: make urls"
