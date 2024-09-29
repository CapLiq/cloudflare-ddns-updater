#!/bin/bash
## Change to "bin/sh" if necessary

# Cloudflare account details
auth_email="REDACTED_EMAIL"                    # The email used to login 'https://dash.cloudflare.com'
auth_method="global"                           # Set to "global" for Global API Key or "token" for Scoped API Token
auth_key="REDACTED_API_KEY"                    # Your API Token or Global API Key
declare -A domains=(["REDACTED_ZONE_ID1"]="example1.com" ["REDACTED_ZONE_ID2"]="example2.com") # Associative array with zone IDs and record names
ttl=3600                                       # Set the DNS TTL (seconds)
proxy=true                                     # Set the proxy to true or false
# sitename="Example Site"                      # Title of site
# slackchannel="#example"                      # Slack Channel
# slackuri="https://hooks.slack.com/services/xxxxx" # URI for Slack WebHook
# discorduri="https://discordapp.com/api/webhooks/xxxxx" # URI for Discord WebHook

# Function to check and update the A record
update_dns_record() {
    local zone_identifier=$1
    local record_name=$2

    # Fetch public IP
    ipv4_regex='([01]?[0-9]?[0-9]|2[0-4][0-9]|25[0-5])\.([01]?[0-9]?[0-9]|2[0-4][0-9]|25[0-5])\.([01]?[0-9]?[0-9]|2[0-4][0-9]|25[0-5])\.([01]?[0-9]?[0-9]|2[0-4][0-9]|25[0-5])'
    ip=$(curl -s -4 https://cloudflare.com/cdn-cgi/trace | grep -Eo "ip=$ipv4_regex" | sed -E "s/^ip=($ipv4_regex)$/\1/")
    if [[ ! $ip =~ ^$ipv4_regex$ ]]; then
        ip=$(curl -s https://api.ipify.org || curl -s https://ipv4.icanhazip.com)
        if [[ ! $ip =~ ^$ipv4_regex$ ]]; then
            logger -s "DDNS Updater: Failed to find a valid IP."
            exit 2
        fi
    fi

    # Set the appropriate authorization header based on the auth method
    if [[ "${auth_method}" == "global" ]]; then
        auth_header="X-Auth-Key: $auth_key"
    else
        auth_header="Authorization: Bearer $auth_key"
    fi

    # Fetch current A record for the domain
    record=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records?type=A&name=$record_name" \
                      -H "X-Auth-Email: $auth_email" \
                      -H "$auth_header" \
                      -H "Content-Type: application/json")

    # Check if the A record exists
    if [[ $record == *"\"count\":0"* ]]; then
        logger -s "DDNS Updater: A record for $record_name does not exist, please create one."
        exit 1
    fi

    # Extract the current IP address from the fetched A record
    old_ip=$(echo "$record" | sed -E 's/.*"content":"(([0-9]{1,3}\.){3}[0-9]{1,3})".*/\1/')
    if [[ $ip == $old_ip ]]; then
        logger "DDNS Updater: IP for $record_name is unchanged."
        return 0
    fi

    # Extract record identifier for updating
    record_identifier=$(echo "$record" | grep -Po '"id":"\K[^"]*')

    # Update the A record with the new IP
    update=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records/$record_identifier" \
                     -H "X-Auth-Email: $auth_email" \
                     -H "$auth_header" \
                     -H "Content-Type: application/json" \
                     --data "{\"type\":\"A\",\"name\":\"$record_name\",\"content\":\"$ip\",\"ttl\":$ttl,\"proxied\":$proxy}")

    # Check the response and log accordingly
    if [[ $update == *"\"success\":false"* ]]; then
        logger -s "DDNS Updater: Failed to update $record_name to $ip."
        exit 1
    else
        logger "DDNS Updater: Successfully updated $record_name to $ip."
    fi
}

# Iterate over each domain and update its A record
for zone_identifier in "${!domains[@]}"; do
    record_name="${domains[$zone_identifier]}"
    update_dns_record $zone_identifier $record_name
done
