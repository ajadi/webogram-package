# webogram-package

A script to install [Webogram](https://github.com/zhukov/webogram), choosing version, system-wide and as service, or as an application for a single user (not root access requried).

# Requirements

* [Git](https://git-scm.com/)
* [NodeJS](https://nodejs.org/) (>= 0.12.0). npm must be in the user PATH.

# Usage

Clone webogram-package repo:
```
git clone git@github.com:juliogonzalez/webogram-package.git
```
Switch to repo directory:
```
cd webogram-package
```
See help:
```
./setup -h
```
Finally call *setup.sh* with the appropriate parameters.

# Limitations

When installing as a service, only sysvinit is supported (not as systemd). At this moment all GNU/Linux flavors using systemd should include compatibility with systemd.

Also please note that the service will not be configured to start on boot. You'll need to use your distro tools to configure it (update-rc.d for Debian-Like and chkconfig for RHEL-like).

Scripts are tested at Raspbian stretch/sid, but should be compatible with Debian-like systems, RHEL/CentOS, etc as long as node is available.

When webogram is started, it will listen as *0.0.0.0* at port *8080* as *http*. You should use a reverse proxy to offer SSL and serve content at standard ports. An example for apache is provided at *examples/apache/webogram.conf*
