Steps in order top to bottom:

Run setup.sh
login as new "ansible-control" user
Run scripts/ansible_install.sh


Known issues:
Imported tasks run multiple times as encountered in roles. Most notably, the firewall tasks run multiple times when used.
I thought import worked like handlers, but at the beginning of execution. "Include statements are processed as they are encountered during execution of the playbook." But both include and import appear processed as they are found in a role. :/

Related to the above, roles are being used here as "functions" as well as a proper role for a host.
I did not realize you could include/import tasks from a file directly, I would like to refactor in the future to make use of that.
