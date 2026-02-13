#!/bin/bash

######### ENV ##########

ENV_FILE_PARENT_DIR=/home/kubernetes-vm
ENV_FILE=$ENV_FILE_PARENT_DIR/env
export $(cat $ENV_FILE | xargs)

##### ARGUMENTS #####

# Use the first argument as ID, second as Recipe. 
# Default values provided if you forget to pass them.
ORDER_ID=${1:-"order-$(date +%s)"}
RECIPE=${2:-"daily_special"}

##### orders #####

ETA=$(date -u -d "+2 hours" +"%Y-%m-%dT%H:%M:%SZ")
timestamp=$(date -u -d "+0 hours" +"%Y-%m-%dT%H:%M:%SZ")

echo "Chef: Placing order $ORDER_ID for $RECIPE..."

curl -s -H "Authorization: ApiKey $ELASTICSEARCH_APIKEY" \
     -H "Content-Type: application/json" \
     -X POST "http://elasticsearch-es-http.default.svc:9200/orders/_doc" \
     -d @- <<EOF
{
    "cook_id": "$ORDER_ID",
    "recipe": "$RECIPE",
    "eta": "$ETA",
    "status": "pending",
    "@timestamp": "$timestamp"
}
EOF

echo -e "\nOrder sent to Elastic."
