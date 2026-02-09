#!/bin/bash 
set -euxo pipefail

######### ENV ##########

ENV_FILE_PARENT_DIR=/home/kubernetes-vm
ENV_FILE=$ENV_FILE_PARENT_DIR/env
export $(cat $ENV_FILE | xargs)
#######################

# remove alerts
curl -H "Authorization: ApiKey $ELASTICSEARCH_APIKEY" -H "Content-Type: application/json" -XPOST "http://elasticsearch-es-http.default.svc:9200/*alerts*/_delete_by_query" -d \
'{
  "query": {
  "match": {
    "kibana.alert.rule.name": "stall_detected"
  }
  }
}'

# delete live cooking data
curl -H "Authorization: ApiKey $ELASTICSEARCH_APIKEY" -H "Content-Type: application/json" -XPOST "http://elasticsearch-es-http.default.svc:9200/live-cooking/_delete_by_query" -d \
'{
 "query": {
  "match_all": {}
 }
}'