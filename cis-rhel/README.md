#Ansible + CIS Benchmarks + RHEL/CentOS 6

Starting a ansible audit for CIS.
This is an ansible playbook for auditing a system running Red Hat Enterprise Linux 6 or CentOS 6  to see if it passes CIS Security Benchmarks.

Insipired by https://github.com/major/cis-rhel-ansible but instead of applying the changes, this will just report if a system passes or fails for each task.

In progress, other sections will be added soon

- Added section 1 level1 and level2 checks
- Added section 2 level1 and level2 checks

Example:
add  hosts in test-hosts
```
ansible-playbook -i test-hosts playbook.yml --extra-vars="nodes=all" --tags=level2 -K -k
```
