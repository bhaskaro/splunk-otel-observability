<%@ page import="java.time.Instant" %>
<%@ page import="java.util.logging.Logger" %>
<%!
  private static final Logger LOGGER = Logger.getLogger("demo.tomcat");
%>
<%
  LOGGER.info("page_access application=tomcat-root method=" + request.getMethod()
      + " path=" + request.getRequestURI() + " remote_addr=" + request.getRemoteAddr());
%>
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Apache Tomcat root</title>
  </head>
  <body>
    <h1>Apache Tomcat root</h1>
    <p>Tomcat is running and instrumented with the Splunk OpenTelemetry Java agent.</p>
    <p><a href="/tomcat-splunk-otel-demo/">Open the Splunk OTel demo application</a></p>
    <p>Time: <%= Instant.now() %></p>
  </body>
</html>
