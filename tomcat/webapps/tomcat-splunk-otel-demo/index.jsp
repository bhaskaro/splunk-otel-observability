<%@ page import="java.time.Instant" %>
<%@ page import="java.util.logging.Logger" %>
<%!
  private static final Logger LOGGER = Logger.getLogger("demo.tomcat.splunk.otel");
%>
<%
  LOGGER.info("page_access application=tomcat-splunk-otel-demo method=" + request.getMethod()
      + " path=" + request.getRequestURI() + " remote_addr=" + request.getRemoteAddr()
      + " user_agent=\"" + request.getHeader("User-Agent") + "\"");
%>
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Tomcat Splunk OTel demo</title>
  </head>
  <body>
    <h1>Tomcat Splunk OTel demo</h1>
    <p>This request generated an instrumented server span, JVM metrics, an
       application log, and a Tomcat access-log entry.</p>
    <p><a href="/">Back to the Tomcat root</a></p>
    <p>Time: <%= Instant.now() %></p>
  </body>
</html>
