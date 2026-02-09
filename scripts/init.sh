#!/bin/bash 
#set -euxo pipefail

######### ENV ##########

ENV_FILE_PARENT_DIR=/home/kubernetes-vm
ENV_FILE=$ENV_FILE_PARENT_DIR/env
export $(cat $ENV_FILE | xargs)

########## Solution view ##########

/opt/workshops/elastic-view.sh -v oblt


########### AI SETUP ###########
/opt/workshops/elastic-llm.sh -k true

curl -H "Authorization: ApiKey $ELASTICSEARCH_APIKEY" -H "Content-Type: application/json" -XPUT "http://elasticsearch-es-http.default.svc:9200/_index_template/my-cook-sensor-index-template" -d \
'{
  "index_templates": [
    {
      "name": "my-cook-sensor-index-template",
      "index_template": {
        "index_patterns": [
          "metrics-cook_sensors-*"
        ],
        "template": {
          "settings": {},
          "mappings": {
            "properties": {
              "cook_id": {
                "time_series_dimension": true,
                "type": "keyword"
              },
              "@timestamp": {
                "type": "date"
              },
              "meat_temperature_c": {
                "type": "half_float"
              },
              "recipe": {
                "time_series_dimension": true,
                "type": "keyword"
              },
              "ambient_temperature_c": {
                "type": "half_float"
              }
            }
          },
          "lifecycle": {
            "enabled": false
          }
        },
        "composed_of": [],
        "priority": 500,
        "_meta": {
          "description": "Template for my weather cook. sensor data"
        },
        "data_stream": {
          "hidden": false,
          "allow_custom_routing": false
        }
      }
    }
  ]
}'

python3 generate_cook.py
for file in cooks_2025/*.ndjson;
do                                                                          
curl -H "Content-Type: application/x-ndjson" -H "Authorization: ApiKey $ELASTICSEARCH_APIKEY" -XPOST "http://elasticsearch-es-http.default.svc:9200/metrics-cook_sensors-2025/_bulk" --data-binary "@$file"
done