maestro-tomcat-plugin
====================

A Maestro Plugin that allows a war to be deployed using Tomcat manager

Task
----

/tomcat/deploy

Task Parameters
---------------

* "Host"

  IP Address or Hostname of the server running Tomcat

* "Port"

  Port that Tomcat manager can be contacted on

* "User"

  Username to use when logging onto Tomcat manager

* "Password"

  Password to use when logging onto Tomcat manager

* "Path"

  Path on "host" that the new war file has been copied to (see "scp plugin" to copy the file)

* "Web Path"

  Path to load war file to (i.e. /app-name)
