# ansible-talend-runner

Role to provide scripts to run jobs using talend metaservlet api.

## setup

Include role.

```bash
---
- name: Talend runner
  hosts: all
  roles:
    - talend-runner

```

installs scripts at /opt/talend_runner by default.

Provides two functionality

1. script to run tasks in talend.

``` bash
/opt/talend_runner/bin/talend_runner.sh -n <TASK_NAME> [-t <TiMEOUTOUT>]

```

1. Installs script to auto register jobservers, include the role on jobserver.

it will run on host with ec2_tag_Role='job-server'
or by setting.

``` bash
self_register_js: true
```

auto registration and deregistration is done via systemd service

scripts

``` bash
/opt/talend_runner/bin/talend_register.sh -s $HOSTNAME
/opt/talend_runner/bin/talend_deregister.sh -s $HOSTNAME
```

configs generated at

``` bash
/opt/talend_runner/etc/config
```
