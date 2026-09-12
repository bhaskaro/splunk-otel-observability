# Homelab Tomcat observability implementation

## Purpose

This project is a small Docker Compose lab for sending Tomcat telemetry to
Splunk Observability Cloud. It demonstrates Java zero-code instrumentation,
host infrastructure metrics, file-based log collection, and synthetic traffic
without building custom container images.

Git repository name: **`splunk-otel-observability`**.

## Architecture

```text
                           OTLP/HTTP :4318
  traffic-generator ---> Tomcat + Splunk Java agent -------------------+
       5-10 concurrent      | traces and JVM metrics                    |
       requests/second      |                                           v
                            +--> ./tomcat/logs <-- file_log ------ OTel Collector
                                                          host_metrics --+
                                                                        |
                         +----------------------------------------------+
                         | traces -> Splunk APM
                         | metrics -> Splunk Infrastructure Monitoring
                         + logs -> Splunk log ingest (currently HTTP 404)
```

## Components

| Compose service | Image | Responsibility |
| --- | --- | --- |
| `otel-java-agent` | `ghcr.io/signalfx/splunk-otel-java/splunk-otel-java:v2.30.0` | One-shot init container that copies the Java agent JAR into a shared volume |
| `tomcat` | `tomcat` | Runs the root and demo JSP applications with automatic Java instrumentation |
| `otel-collector` | `quay.io/signalfx/splunk-otel-collector:0.157.0` | Receives, enriches, batches, and exports traces, metrics, and logs |
| `traffic-generator` | `curlimages/curl:8.16.0` | Sends a random batch of 5-10 concurrent requests every second |

No image is built locally. Application files are bind-mounted from
`tomcat/webapps`, while logs are persisted in `tomcat/logs`.

## Telemetry identity

Use these attributes when filtering in Splunk:

```text
service.name = homelab-tomcat-otel-demo
deployment.environment.name = homelab
host.name = homelab-docker-host
```

The same `host.name` is placed on application telemetry and host metrics so
Splunk APM can correlate the service with Infrastructure Monitoring.

## Signal flow

### Traces

The Splunk Java agent instruments Tomcat and sends OTLP/HTTP to
`http://otel-collector:4318`. The collector sends traces to the realm-specific
Splunk APM endpoint.

### Metrics

There are two metric sources:

- Java-agent JVM and runtime metrics received through OTLP.
- Host CPU, load, memory, network, paging, and process metrics collected every
  10 seconds from the read-only `/proc` and `/sys` mounts.

The SignalFx exporter sends both sources to Splunk Infrastructure Monitoring
and synchronizes host metadata.

### Logs

Both JSP pages write a structured `page_access` message through Tomcat JULI on
every request. Tomcat also writes an HTTP access record. The collector tails:

```text
tomcat/logs/catalina*.log
tomcat/logs/localhost*.log
tomcat/logs/localhost_access_log*.txt
```

Tomcat uses `UMASK=0022`, and its startup command repairs existing log-file
permissions. The collector mounts the log directory read-only.

Local log collection is working. Remote log export currently receives:

```text
HTTP "/v1/log" 404 "Not Found"
```

This is a remote endpoint or account-entitlement issue, not a file collection
issue. Confirm that log ingest is enabled for the Splunk Observability Cloud
organization. Alternatively, configure a Splunk Cloud Platform or Splunk
Enterprise HEC URL and its corresponding HEC token.

## Applications and generated load

| URL | Purpose |
| --- | --- |
| `http://localhost:8080/` | Tomcat homelab landing page |
| `http://localhost:8080/tomcat-splunk-otel-demo/` | Instrumented Splunk OTel demo page |
| `http://localhost:13133/` | Collector health endpoint |

Each traffic cycle randomly chooses 5-10 workers. Each worker randomly selects
one of the two application URLs, and all requests in the batch run concurrently.
The next batch begins after a one-second pause.

## Configuration and startup

Copy the example environment file and provide an organization access token and
realm:

```sh
cp .env.example .env
```

```dotenv
SPLUNK_ACCESS_TOKEN=your-org-access-token
SPLUNK_REALM=us1
```

The `.env` file is ignored by Git. Never commit an actual access token.

Start the lab:

```sh
docker compose pull
docker compose up -d
docker compose ps
```

Validate it:

```sh
curl http://localhost:8080/
curl http://localhost:8080/tomcat-splunk-otel-demo/
curl http://localhost:13133/
docker compose logs --tail=100 otel-collector tomcat traffic-generator
```

Stop the lab:

```sh
docker compose down
```

Application logs remain under `tomcat/logs`. The Java-agent named volume is
removed only if `docker compose down -v` is used.

## Work completed

- Created a Compose-based Splunk OTel Collector service.
- Used only prebuilt Tomcat, Splunk Java-agent, collector, and curl images.
- Added a one-shot init container for sharing the Java agent with Tomcat.
- Added separate root and `/tomcat-splunk-otel-demo/` JSP applications.
- Added structured application logging on every page request.
- Added persistent host-side Tomcat log storage and read-only collector access.
- Fixed Tomcat log permissions for the non-root collector process.
- Added OTLP trace and JVM/runtime metric export.
- Added host infrastructure metric collection and host metadata synchronization.
- Added consistent service, environment, and host correlation attributes.
- Added randomized concurrent load generation.
- Validated the Compose and collector configurations and exercised both pages.

## Current status

| Area | Status | Notes |
| --- | --- | --- |
| Containers | Working | Collector, Tomcat, and traffic generator run continuously; Java-agent init exits successfully |
| Application pages | Working | Both URLs return HTTP 200 |
| Synthetic load | Working | 5-10 concurrent randomized requests per second |
| Traces | Working | Java-agent traces are sent through the collector |
| JVM metrics | Working | Java-agent runtime metrics are sent through the collector |
| Infrastructure metrics | Working | Host metadata synchronization was confirmed in collector logs |
| Local log collection | Working | Collector watches readable Catalina and access-log files |
| Remote log export | Blocked externally | Splunk `/v1/log` currently returns HTTP 404 |

## Next actions

### Priority 1: finish remote log delivery

1. Confirm whether log ingest is enabled for the Splunk Observability Cloud
   organization and `us1` realm.
2. If logs are stored in Splunk Cloud Platform or Enterprise, create or identify
   a HEC input and collect its full URL, token, and target index.
3. Put log endpoint/token settings in `.env`, reference them from Compose, and
   replace the current `splunk_hec/logs` destination.
4. Verify that the collector no longer reports retries or HTTP 404 responses.
5. Search for `service.name=homelab-tomcat-otel-demo` and `page_access`.

### Priority 2: production-hardening

1. Pin `tomcat` to an explicit tested version instead of the moving `latest` tag.
2. Pin images by digest if reproducibility and supply-chain verification matter.
3. Move tokens from `.env` to Docker secrets or an external secret manager.
4. Configure collector queue persistence so telemetry can survive a restart or
   extended destination outage.
5. Add CPU and memory limits and tune the collector memory limiter accordingly.
6. Add log rotation and retention limits for `tomcat/logs`.
7. Add explicit health checks and make dependent services wait for readiness.

### Priority 3: expand observability coverage

1. Add Docker container statistics by configuring the Docker stats receiver;
   review the security implications before mounting the Docker socket.
2. Add error and slow-request endpoints to generate more useful APM scenarios.
3. Add custom business metrics and span attributes to the demo application.
4. Enable trace/log correlation fields and validate links from APM to logs.
5. Create Splunk dashboards and detectors for latency, error rate, JVM memory,
   CPU, and host availability.
6. Add a configurable load profile so concurrency and interval can be changed
   without editing Compose.

## Troubleshooting

### Infrastructure panel is empty

Wait several minutes for correlation to appear, then confirm that traces and
metrics share `host.name=homelab-docker-host`. Check for the collector message
`Host metadata synchronized`.

### Logs are not visible

Distinguish collection from export:

```sh
docker compose logs otel-collector | grep -E 'watching file|unreadable|splunk_hec|404|401|403'
docker exec otel-test-tomcat sh -c 'tail -n 20 /usr/local/tomcat/logs/catalina.*.log'
```

`Started watching file` means local collection works. HTTP 404 indicates the
remote log endpoint is unavailable; HTTP 401 or 403 indicates a token or
permission problem.

### Traces or metrics are missing

Confirm Tomcat loaded the Java agent and the collector is healthy:

```sh
docker compose logs tomcat | grep -i javaagent
curl http://localhost:13133/
docker compose logs otel-collector
```

## Repository initialization

After creating the remote repository named `splunk-otel-observability`:

```sh
git init
git add .
git commit -m "feat: add Splunk OTel Tomcat homelab"
git branch -M main
git remote add origin <repository-url>
git push -u origin main
```

Before committing, verify that `.env` is excluded:

```sh
git status --short
git check-ignore .env
```
