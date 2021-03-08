Ansible Role: update-route53-onboot
=========

This role provides a systemd mechanism to create or update a Route53 record with the public IP address of the EC2 instance upon boot.

Requirements
------------

For the boot script to run, you will need to ensure you have assigned an IAM policy to the EC2 instance that can interact with Route53. E.g.

    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Sid": "ChangeHostedZone",
          "Effect": "Allow",
          "Action": "route53:ChangeResourceRecordSets",
          "Resource": "arn:aws:route53:::hostedzone/XXXXXXXXXXXXXXXXXXXXX"
        }
      ]
    }

This role only supports Amazon Linux 2.

Role Variables
--------------

The role accepts two variables.
The fist holds the A record you wish to apply.

Example: `host.example.com`

    endpoint_fqdn: host.example.com

The second, holds time-to-live value for the DNS record.

Example: `300`

    endpoint_ttl: 300

Dependencies
------------
A running EC2 instance running Amazon Linux 2 with a policy assigned to its role which will permit read/write access to Route53.

Example Playbook
----------------

    hosts:
      localhost:
      roles:
        - role: gavmain.update-route53-onboot
          vars:
            endpoint_fqdn: host.example.com
            endpoint_ttl: 300

License
-------

MIT

Author Information
------------------

This role was created in 2021 by [Gav Main](https://github.com/gavmain).
