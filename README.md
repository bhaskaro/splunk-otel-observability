# Splunk OTel Collector + Tomcat demo

Repository name: **`splunk-otel-observability`**.

For the architecture, implementation record, current status, troubleshooting,
and prioritized roadmap, see [docs/IMPLEMENTATION.md](docs/IMPLEMENTATION.md).
To connect Java, Linux-hosted, containerized, or other language applications,
see [docs/USING_WITH_OTHER_APPLICATIONS.md](docs/USING_WITH_OTHER_APPLICATIONS.md).

This Compose project runs:

- the Splunk distribution of the OpenTelemetry Collector;
- the official prebuilt `tomcat` image with the Splunk Java agent, exporting traces and JVM/runtime metrics over OTLP/HTTP;
- a file-log receiver that tails Tomcat application and access logs, with remote
  export configured but currently receiving HTTP 404 from the log endpoint;
- a traffic generator that sends a random batch of 5–10 concurrent requests
  every second, distributing requests randomly across both Tomcat pages.

## Configure credentials

Create the local environment file and edit it:

```sh
cp .env.example .env
```

Set these two values in `.env`:

```dotenv
SPLUNK_ACCESS_TOKEN=your-org-access-token
SPLUNK_REALM=us0
```

Use an **organization access token** with ingest permission. The realm is visible in
your Splunk Observability Cloud profile and in your realm-specific URL (examples:
`us0`, `us1`, or `eu0`). The `.env` file is ignored by Git.

## Start and test

```sh
docker compose pull
docker compose up -d
docker compose ps
curl http://localhost:8080/
curl http://localhost:8080/tomcat-splunk-otel-demo/
docker compose logs -f otel-collector tomcat
```

The root URL is a Tomcat landing page; the demo application is independently
deployed at `/tomcat-splunk-otel-demo/`. Both JSPs write a structured
`page_access` message through Tomcat JULI on every request, in addition to
Tomcat's HTTP access log. The collector tails both log files and attempts to
export them; see the known remote log-ingest issue below.

The traffic generator continues to create test telemetry in the background. In
Splunk Observability Cloud, filter for
`service.name = homelab-tomcat-otel-demo`,
`deployment.environment.name = homelab`, and
`host.name = homelab-docker-host`.

No local image is built. A short-lived init container copies the agent JAR from
Splunk's prebuilt Java-agent image into a shared read-only volume for Tomcat, and
both webapps are bind-mounted from `tomcat/webapps`. Tomcat writes its log
files to the host directory `tomcat/logs`, which the collector mounts read-only.

Stop the services with:

```sh
docker compose down
```

Tomcat log files remain under `tomcat/logs` after the containers stop.

## Data paths

| Signal | Source | Collector destination |
| --- | --- | --- |
| Traces | Splunk Java agent | Splunk APM OTLP ingest |
| Metrics | Java-agent JVM/runtime instrumentation plus host CPU, memory, load, network, paging, and process metrics | Splunk Infrastructure Monitoring |
| Logs | Tomcat access and JULI files | Locally collected; remote Splunk log ingest currently returns HTTP 404 |

The cloud endpoints are derived from `SPLUNK_REALM` in
`otel-collector-config.yaml`. If sending logs to Splunk Enterprise or Splunk Cloud
Platform instead, change `exporters.splunk_hec/logs.endpoint` to that deployment's
HEC URL and provide its HEC token separately.

## Useful checks

```sh
curl http://localhost:13133/
docker compose config
docker compose logs otel-collector
```

If the collector reports `401` or `403`, confirm the access token and its ingest
permissions. DNS/TLS failures usually indicate an incorrect realm or outbound
firewall restrictions.
