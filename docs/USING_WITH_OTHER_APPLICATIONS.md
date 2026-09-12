# Use this collector with other applications

This Compose stack can act as a local OpenTelemetry gateway for applications
other than the included Tomcat demo. It accepts OTLP on:

| Protocol | From another Compose service | From the Docker host |
| --- | --- | --- |
| OTLP/gRPC | `http://otel-collector:4317` | `http://localhost:4317` |
| OTLP/HTTP protobuf | `http://otel-collector:4318` | `http://localhost:4318` |

Ports `4317` and `4318` are published by Compose. Applications in another
machine must use this Docker host's reachable DNS name or IP instead of
`localhost`, and the host firewall must permit the selected port.

## Common configuration

Every application should have a unique service name. Applications on this same
homelab machine should use the shared host and environment attributes so APM can
correlate them with the infrastructure metrics collected by this stack.

For an application added to this Compose file:

```yaml
environment:
  OTEL_SERVICE_NAME: my-application
  OTEL_RESOURCE_ATTRIBUTES: deployment.environment.name=homelab,host.name=homelab-docker-host
  OTEL_EXPORTER_OTLP_ENDPOINT: http://otel-collector:4318
  OTEL_EXPORTER_OTLP_PROTOCOL: http/protobuf
  OTEL_TRACES_EXPORTER: otlp
  OTEL_METRICS_EXPORTER: otlp
  OTEL_LOGS_EXPORTER: otlp
depends_on:
  - otel-collector
```

These environment variables follow the OpenTelemetry SDK convention, but exact
support and defaults vary by language. Configure an OpenTelemetry SDK or
automatic-instrumentation agent in the application; setting environment
variables alone does not instrument otherwise uninstrumented code.

The collector now accepts OTLP logs as well as file-based Tomcat logs. Remote
log export will work only after the repository's documented `/v1/log` issue is
resolved or a Splunk Platform HEC endpoint is configured.

## Java applications

The included `otel-java-agent` init service places the Splunk Java agent in the
named `java-agent` volume. Another Java Compose service can reuse it:

```yaml
my-java-app:
  image: my-java-application:latest
  environment:
    JAVA_TOOL_OPTIONS: -javaagent:/opt/splunk/splunk-otel-javaagent.jar
    OTEL_SERVICE_NAME: my-java-application
    OTEL_RESOURCE_ATTRIBUTES: deployment.environment.name=homelab,host.name=homelab-docker-host
    OTEL_EXPORTER_OTLP_ENDPOINT: http://otel-collector:4318
    OTEL_EXPORTER_OTLP_PROTOCOL: http/protobuf
    OTEL_TRACES_EXPORTER: otlp
    OTEL_METRICS_EXPORTER: otlp
  volumes:
    - java-agent:/opt/splunk:ro
  depends_on:
    otel-java-agent:
      condition: service_completed_successfully
    otel-collector:
      condition: service_started
```

If the application uses Logback, Log4j, or another logging framework, review
the Splunk Java-agent log instrumentation for that framework. An alternative is
to write logs to a mounted directory and add a uniquely named `file_log`
receiver, following the Tomcat example.

## Other language runtimes

Use the Splunk or upstream OpenTelemetry automatic-instrumentation package for
the application's language, then send OTLP to this collector.

| Runtime | Typical instrumentation approach |
| --- | --- |
| Node.js | Load the Splunk/OpenTelemetry Node.js instrumentation before application modules |
| Python | Launch the application with the OpenTelemetry distribution's instrumentation command |
| .NET | Install the .NET automatic-instrumentation files and set the documented CLR startup variables |
| Go | Add the OpenTelemetry SDK or compile with an appropriate zero-code instrumentation option |
| Ruby/PHP/Rust | Configure the language's OpenTelemetry SDK/exporter and point it to OTLP |

Use `http/protobuf` on port `4318` when supported consistently by the chosen
SDK. For SDKs configured for gRPC, use port `4317` and the SDK's expected URL
syntax.

## Applications running directly on this host

An application running outside Docker can send to the published HTTP endpoint:

```sh
export OTEL_SERVICE_NAME=my-host-application
export OTEL_RESOURCE_ATTRIBUTES=deployment.environment.name=homelab,host.name=homelab-docker-host
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318
export OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
export OTEL_TRACES_EXPORTER=otlp
export OTEL_METRICS_EXPORTER=otlp
export OTEL_LOGS_EXPORTER=otlp
```

Start the application through its language-specific instrumentation mechanism.
Do not give the Splunk cloud access token to each application; the local
collector owns the cloud credentials and forwarding responsibility.

## Applications on another Linux host

For a quick test, point the remote application's OTLP exporter at this Docker
host. For ongoing host monitoring, install the Splunk Distribution of the OTel
Collector on that Linux machine in agent mode and forward it to a central
gateway. A per-host agent can collect accurate CPU, memory, disk, filesystem,
network, paging, and process metrics from that host.

Do not reuse `host.name=homelab-docker-host` for a different physical or virtual
machine. Give each host a stable, unique `host.name`; ensure its application
spans and infrastructure metrics use that same value.

## File-based logs from another container

To collect a log file rather than OTLP logs:

1. Mount a host directory into the application as writable.
2. Mount the same directory into the collector as read-only.
3. Ensure files are readable by the collector process, for example with a
   suitable application umask.
4. Add a unique `file_log/<application>` receiver with the file paths.
5. Add that receiver to `service.pipelines.logs.receivers`.
6. Add `service.name`, `deployment.environment.name`, and `host.name` resource
   attributes for correlation.

Example receiver:

```yaml
receivers:
  file_log/my_application:
    include: [/var/log/my-application/*.log]
    start_at: end
    operators:
      - type: add
        field: resource["service.name"]
        value: my-application
```

Use `start_at: end` for ongoing production collection to avoid importing old
files after a fresh collector state. The demo uses `beginning` so historical
lab logs are visible.

## Adding more receivers

OTLP is appropriate for instrumented application telemetry. Other sources need
receivers suited to their protocols, such as Prometheus scraping, host metrics,
Docker statistics, database receivers, or file logs. A receiver must be defined
under `receivers` and referenced by the appropriate traces, metrics, or logs
pipeline before it becomes active.

When mounting `/var/run/docker.sock` for discovery or container statistics,
remember that access to the Docker socket is highly privileged. Review the
permissions and security impact before enabling it.

## Validation checklist

1. Confirm the collector is ready at `http://localhost:13133/`.
2. Confirm the application can resolve and connect to the collector endpoint.
3. Confirm the application instrumentation reports a successful startup.
4. Generate requests or application activity.
5. Check collector logs for receiver, authentication, queue, or export errors.
6. Search Splunk using the exact `service.name` and environment.
7. Confirm `host.name` matches between spans and infrastructure metrics.
8. Allow several minutes for new services and infrastructure correlation to
   appear in the Splunk UI.

## Official references

### Splunk OpenTelemetry Collector

- [Splunk OpenTelemetry Collector project](https://github.com/signalfx/splunk-otel-collector)
- [Install the Collector for Linux manually](https://help.splunk.com/en/splunk-observability-cloud/manage-data/splunk-distribution-of-the-opentelemetry-collector/get-started-with-the-splunk-distribution-of-the-opentelemetry-collector/collector-for-linux/install-the-collector-for-linux-manual)
- [Collector for Linux default configuration](https://help.splunk.com/en/splunk-observability-cloud/manage-data/splunk-distribution-of-the-opentelemetry-collector/get-started-with-the-splunk-distribution-of-the-opentelemetry-collector/collector-for-linux/collector-for-linux-default-configuration)
- [Collector deployment modes](https://help.splunk.com/en/splunk-observability-cloud/manage-data/splunk-distribution-of-the-opentelemetry-collector/get-started-with-the-splunk-distribution-of-the-opentelemetry-collector/get-started-understand-and-use-the-collector/deployment-modes)
- [Collector ports and endpoints](https://help.splunk.com/en/splunk-observability-cloud/manage-data/splunk-distribution-of-the-opentelemetry-collector/get-started-with-the-splunk-distribution-of-the-opentelemetry-collector/collector-requirements/exposed-ports-and-endpoints)

### Instrumentation and correlation

- [Instrument Java applications for Splunk Observability](https://help.splunk.com/en/splunk-observability-cloud/manage-data/instrument-back-end-services/instrument-back-end-applications-to-send-spans-to-splunk-apm/instrument-a-java-application/instrument-your-java-application)
- [Splunk Java instrumentation project](https://github.com/signalfx/splunk-otel-java)
- [APM and Infrastructure Monitoring related content](https://help.splunk.com/en/splunk-observability-cloud/data-tools/related-content)
- [Configure APM deployment environments](https://help.splunk.com/en/splunk-observability-cloud/monitor-application-performance/set-up-splunk-apm/set-up-deployment-environments-in-splunk-apm)

### Metrics and logs

- [Configure Linux host metrics](https://help.splunk.com/en/splunk-observability-cloud/manage-data/splunk-distribution-of-the-opentelemetry-collector/get-started-with-the-splunk-distribution-of-the-opentelemetry-collector/collector-for-linux/advanced-configuration-for-linux)
- [Collect container logs with the file-log receiver](https://help.splunk.com/en/splunk-observability-cloud/manage-data/splunk-distribution-of-the-opentelemetry-collector/get-started-with-the-splunk-distribution-of-the-opentelemetry-collector/get-started-understand-and-use-the-collector/use-the-collector-to-send-container-logs-to-splunk-enterprise/part-2-configure-the-collector-and-splunk-enterprise-instance)
- [Splunk HEC exporter](https://help.splunk.com/splunk-observability-cloud/manage-data/splunk-distribution-of-the-opentelemetry-collector/get-started-with-the-splunk-distribution-of-the-opentelemetry-collector/collector-components/exporters/splunk-hec-exporter)

### OpenTelemetry

- [OpenTelemetry language instrumentation](https://opentelemetry.io/docs/languages/)
- [OpenTelemetry zero-code instrumentation](https://opentelemetry.io/docs/zero-code/)
- [OpenTelemetry SDK environment variables](https://opentelemetry.io/docs/specs/otel/configuration/sdk-environment-variables/)
- [OTLP exporter configuration](https://opentelemetry.io/docs/languages/sdk-configuration/otlp-exporter/)
