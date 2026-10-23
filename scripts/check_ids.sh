#!/bin/bash
cd /home/mluong/asset
for s in web db pgadmin nginx prometheus grafana cadvisor nginx-exporter postgres-exporter loki promtail alert-sink; do
  echo -n "$s: "
  docker compose exec -T $s id 2>&1 || true
done
