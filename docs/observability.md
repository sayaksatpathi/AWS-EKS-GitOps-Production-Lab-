# Observability

## Stack

| Component | Role | Namespace |
|-----------|------|-----------|
| Prometheus | Metrics collection and alerting | monitoring |
| Grafana | Dashboards and visualization | monitoring |
| Alertmanager | Alert routing and grouping | monitoring |
| Loki | Log aggregation | monitoring |
| Promtail | Log shipping (DaemonSet) | monitoring |

## Accessing Dashboards

### Grafana

```bash
kubectl port-forward svc/prometheus-grafana -n monitoring 3000:80
# Open: http://localhost:3000
# Username: admin
# Password: admin123 (or as configured in helm install)
```

### Prometheus

```bash
kubectl port-forward svc/prometheus-kube-prometheus-prometheus -n monitoring 9090:9090
# Open: http://localhost:9090
```

### Alertmanager

```bash
kubectl port-forward svc/prometheus-kube-prometheus-alertmanager -n monitoring 9093:9093
# Open: http://localhost:9093
```

### Loki (via Grafana)

Loki is queried through Grafana. In Grafana:
1. Go to Explore
2. Select the Loki datasource
3. Query: `{namespace="cloudlaunch"}`

## Application Metrics

The CloudLaunch API exposes Prometheus metrics at `/metrics`:

| Metric | Type | Description |
|--------|------|-------------|
| `cloudlaunch_http_requests_total` | Counter | Total HTTP requests by method, endpoint, status |
| `cloudlaunch_http_request_duration_seconds` | Histogram | Request latency by method and endpoint |
| `cloudlaunch_errors_total` | Counter | Total errors by type |

### Useful Queries

**Request rate (5m)**
```promql
sum(rate(cloudlaunch_http_requests_total[5m])) by (endpoint)
```

**Error rate**
```promql
sum(rate(cloudlaunch_http_requests_total{status=~"5.."}[5m])) 
/ sum(rate(cloudlaunch_http_requests_total[5m]))
```

**p95 latency**
```promql
histogram_quantile(0.95, 
  sum(rate(cloudlaunch_http_request_duration_seconds_bucket[5m])) by (le, endpoint))
```

**Pod readiness**
```promql
kube_pod_status_ready{namespace="cloudlaunch", condition="true"}
```

## Grafana Dashboard

Import `monitoring/dashboards/cloudlaunch-dashboard.json` into Grafana:
1. Grafana → Dashboards → Import
2. Upload `cloudlaunch-dashboard.json`
3. Select Prometheus datasource
4. Click Import

The dashboard shows:
- Pod count (healthy/total)
- Request rate per endpoint
- p95 latency per endpoint
- Error rate (%)
- Memory usage per pod

## Alerts

Alerts are defined in `monitoring/alerts/cloudlaunch-alerts.yaml`.

| Alert | Condition | Severity |
|-------|-----------|----------|
| CloudLaunchHighErrorRate | >5% 5xx errors for 2m | critical |
| CloudLaunchNoHealthyPods | 0 ready pods for 1m | critical |
| CloudLaunchHighLatency | p95 > 1s for 5m | warning |
| CloudLaunchPodRestartingFrequently | >3 restarts in 15m | warning |
| CloudLaunchDeploymentNotReady | <50% replicas for 5m | critical |

## Log Investigation

### View live logs

```bash
kubectl logs -n cloudlaunch -l app=cloudlaunch-api -f
```

### Query in Grafana/Loki

```logql
# All logs for cloudlaunch
{namespace="cloudlaunch"}

# Only error logs
{namespace="cloudlaunch"} |= "ERROR"

# 5xx requests
{namespace="cloudlaunch"} | json | status >= 500

# Logs from a failed deployment
{namespace="cloudlaunch"} | json | event="readiness_failure"
```

### Investigate a failed deployment

When a deployment is failing:
```bash
# Check pod events
kubectl describe pod -n cloudlaunch <pod-name>

# Check recent logs
kubectl logs -n cloudlaunch <pod-name> --previous

# Check readiness probe history
kubectl get events -n cloudlaunch --field-selector=involvedObject.name=<pod-name> --sort-by='.lastTimestamp'
```
