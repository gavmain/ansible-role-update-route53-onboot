#!/bin/bash

# Allows public EC2 instances to create/update Route53 records at boot

# The config file assumes the following variables are defined
#  - ENDPOINT_FQDN - The endpoint FQDN we want to update at boot-time. E.g foo.example.com
#  - TTL           - The time-to-live value for the DNS record

# Load in pre-defined settings to drive Route53
CONFIG_FILE=/usr/local/etc/update-route53.cfg
if [[ -f $CONFIG_FILE ]]; then
  . $CONFIG_FILE
else
  echo "Error - $CONFIG_FILE does not exist."
  exit 1
fi

if [[ -z "$ENDPOINT_FQDN" ]]; then
  echo "Error - The variable 'ENDPOINT_FQDN' is not set in $CONFIG_FILE."
  exit 1
fi

# We need the domain name to search route53 for the associated Hosted Zone ID
DOMAIN=$(echo $ENDPOINT_FQDN | cut -d. -f 2-)

# Get some facts about this EC2 instance
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)

# Get the Hosted Zone ID
HOSTED_ZONE_ID=$(aws route53 list-hosted-zones-by-name |jq --raw-output --arg DOMAIN "${DOMAIN}." '.HostedZones | .[] | select( .Name == $DOMAIN) | ( .Id | split ("/"))[-1]')
if [[ -z "$HOSTED_ZONE_ID" ]]; then
  echo "Error - Could not find the 'Hosted Zone ID' for the $DOMAIN domain."
  exit 1
fi

# Query Route53 for the current record. A policy attached to the EC2 instance's role is required for this.
CURRENT_RECORD_VALUE=$(aws route53 list-resource-record-sets --hosted-zone-id $HOSTED_ZONE_ID --query "ResourceRecordSets[?Name == '${ENDPOINT_FQDN}.']" |jq --raw-output '.[].ResourceRecords[] | .Value')
rc=$?
if [[ $rc -ne 0 ]]; then
  echo "Failed to list-resource-record-sets. Check there is an associated policy which allows you to perform list-resource-record-sets. Exit code - ($rc)"
  exit $rc
fi

# If the current record for the endpoint matches our current public IP address, there is nothing more to do.
if [[ $CURRENT_RECORD_VALUE == $PUBLIC_IP ]]; then
  echo "$ENDPOINT_FQDN is correct. Nothing to do. Bye bye."
  exit 0
fi

# If the record needs modification, or doesn't exist, then create a json file to send up to Route53
COMMENT="Updating ${ENDPOINT_FQDN} on `hostname` at `date`"
TMPFILE=$(mktemp /tmp/${ENDPOINT_FQDN}.XXXXXXXX)
DEFAULT_TTL=300

cat > ${TMPFILE} << EOF
{
  "Comment":"$COMMENT",
  "Changes":[
    {
      "Action":"UPSERT",
      "ResourceRecordSet":{
        "ResourceRecords":[
          {
            "Value":"$PUBLIC_IP"
          }
        ],
        "Name":"$ENDPOINT_FQDN",
        "Type":"A",
        "TTL":${TTL:-$DEFAULT_TTL}
      }
    }
  ]
}
EOF

# Change the A record and capture the change ID to interrogate the status of the modification
CHANGE_ID=$(aws route53 --output json change-resource-record-sets --hosted-zone-id $HOSTED_ZONE_ID --change-batch file:///$TMPFILE | jq --raw-output '.ChangeInfo.Id' | cut -d'/' -f 3-)

# Give Route53 some time to affect the change and log if the change was successful or not within the timeout threshold set below
TIMEOUT_SECS=180s
start_clock=$SECONDS
CHECK_CMD="aws route53 --output json get-change --id $CHANGE_ID | jq --raw-output '.ChangeInfo.Status' | grep INSYNC"

UPDATE_TIME_OUTPUT=$( { timeout $TIMEOUT_SECS bash -c "until $CHECK_CMD; do sleep 10; done"; } 2>&1 )
rc=$?
if [[ $rc -ne 0 ]]; then
  echo "Failed to verify if $ENDPOINT_FQDN updated. get-change timed out in $TIMEOUT_SECS"
else
  rm -f $TMPFILE
  echo "Successfully updated $ENDPOINT_FQDN within $((SECONDS - start_clock)) seconds. Exiting!"
fi

exit $rc
