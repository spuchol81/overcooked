#!/bin/bash

######### ENV ##########

ENV_FILE_PARENT_DIR=/home/kubernetes-vm
ENV_FILE=$ENV_FILE_PARENT_DIR/env
export $(cat $ENV_FILE | xargs)

##### orders #####

ETA=$(date -u -d "+2 hours" +"%Y-%m-%dT%H:%M:%SZ")
curl -H "Authorization: ApiKey $ELASTICSEARCH_APIKEY" \
     -H "Content-Type: application/json" \
     -X POST "http://elasticsearch-es-http.default.svc:9200/orders/_doc" \
     -d @- <<EOF
{
    "cook_id": "demo-001",
    "recipe": "pulled_pork",
    "eta": "$ETA"
}
EOF
