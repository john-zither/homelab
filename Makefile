# Single-node k3s homelab. First time: sudo ./bootstrap/install-k3s.sh, then
#   make cluster images secrets deploy
# See README.md for the cutover checklist before enabling trading CronJobs.

.PHONY: validate cluster images secrets deploy status gpu \
        trading-enable trading-disable media-up media-down search-up search-down audiobook

KUSTOMIZATIONS := cluster apps/media apps/trading

validate:            ## render every kustomization and schema-check it
	@for k in $(KUSTOMIZATIONS); do echo "== $$k"; kubectl kustomize $$k | kubeconform -strict -summary -; done

cluster:             ## namespaces + NVIDIA device plugin (12 GPU slots)
	kubectl apply -k cluster
	kubectl -n kube-system rollout status ds/nvidia-device-plugin --timeout=180s

images:              ## build runtime images into Docker (shared with k3s)
	scripts/build-images.sh

secrets:             ## Alpaca keys from ../stocks/keys.env
	scripts/create-secrets.sh

deploy:              ## apply apps (trading CronJobs stay suspended)
	kubectl apply -k apps/media
	kubectl apply -k apps/trading

status:
	@kubectl get nodes -o wide
	@echo; kubectl get deploy,cronjob,job,pod -n media
	@echo; kubectl get deploy,cronjob,job,pod -n trading
	@echo; $(MAKE) --no-print-directory gpu

gpu:                 ## GPU slots: capacity and what currently holds them
	@kubectl get node -o jsonpath='{range .items[*]}{.metadata.name}: {.status.allocatable.nvidia\.com/gpu} slots allocatable{"\n"}{end}'
	@kubectl get pods -A -o jsonpath='{range .items[?(@.status.phase!="Succeeded")]}{.metadata.namespace}/{.metadata.name}{"\t"}{.spec.containers[*].resources.limits.nvidia\.com/gpu}{"\n"}{end}' | awk -F'\t' '$$2 != "" {print "  " $$2 " slots  " $$1}'

trading-enable:      ## only after removing the stocks lines from your crontab!
	@if crontab -l 2>/dev/null | grep -q 'agents/stocks/run_'; then \
	  echo "crontab still runs stocks jobs; remove them first (crontab -e) or trades will double"; exit 1; fi
	for cj in paper-gnn vgslx dashboard retrain-gnn; do \
	  kubectl -n trading patch cronjob $$cj -p '{"spec":{"suspend":false}}'; done

trading-disable:
	for cj in paper-gnn vgslx dashboard retrain-gnn; do \
	  kubectl -n trading patch cronjob $$cj -p '{"spec":{"suspend":true}}'; done

media-up:
	scripts/audiobook.sh up
media-down:
	scripts/audiobook.sh down
search-up:
	kubectl -n media scale deploy/storysearch-api --replicas=1
search-down:
	kubectl -n media scale deploy/storysearch-api --replicas=0

audiobook:           ## make audiobook ARGS='batch --count 10'
	scripts/audiobook.sh run $(ARGS)
