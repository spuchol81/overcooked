#!/bin/bash 
#set -euxo pipefail

######### ENV ##########

ENV_FILE_PARENT_DIR=/home/kubernetes-vm
ENV_FILE=$ENV_FILE_PARENT_DIR/env
export $(cat $ENV_FILE | xargs)

########## Solution view ##########

#/opt/workshops/elastic-view.sh -v oblt


########### AI SETUP ###########
#/opt/workshops/elastic-llm.sh -k true

curl -H "Authorization: ApiKey $ELASTICSEARCH_APIKEY" \
     -H "Content-Type: application/json" \
     -X PUT "http://elasticsearch-es-http.default.svc:9200/_index_template/my-cook-sensor-index-template" \
     -d '
{
  "index_patterns": [
    "metrics-cook_sensors-*"
  ],
  "data_stream": {
    "hidden": false,
    "allow_custom_routing": false
  },
  "priority": 500,
  "composed_of": [],
  "template": {
    "settings": {
      "index.mode": "time_series"
    },
    "mappings": {
      "properties": {
        "@timestamp": {
          "type": "date"
        },
        "cook_id": {
          "type": "keyword",
          "time_series_dimension": true
        },
        "recipe": {
          "type": "keyword",
          "time_series_dimension": true
        },
        "meat_temperature_c": {
          "type": "half_float",
          "time_series_metric": "gauge"
        },
        "ambient_temperature_c": {
          "type": "half_float",
          "time_series_metric": "gauge"
        }
      }
    }
  },
  "_meta": {
    "description": "Template for my cook sensor data"
  }
}'


python3 generate_cook.py
for file in cooks_2025/*.ndjson;
do                                                                          
curl -H "Content-Type: application/x-ndjson" -H "Authorization: ApiKey $ELASTICSEARCH_APIKEY" -XPOST "http://elasticsearch-es-http.default.svc:9200/metrics-cook_sensors-2025/_bulk" --data-binary "@$file"
done

curl -H "Authorization: ApiKey $ELASTICSEARCH_APIKEY" \
     -H "Content-Type: application/json" \
     -X PUT "http://elasticsearch-es-http.default.svc:9200/_transform/2025_cooking_stats" \
     -d '
{
  "source": {
    "index": [
      "metrics-cook_sensors-*"
    ],
    "query": {
      "match_all": {}
    }
  },
  "dest": {
    "index": "2025_cooking_stats"
  },
  "pivot": {
    "group_by": {
      "cook_id": {
        "terms": {
          "field": "cook_id"
        }
      },
      "recipe": {
        "terms": {
          "field": "recipe"
        }
      }
    },
    "aggregations": {
      "max_meat_temperature_c": {
        "max": {
          "field": "meat_temperature_c"
        }
      },
      "min_meat_temperature_c": {
        "min": {
          "field": "meat_temperature_c"
        }
      },
      "avg_ambient_temperature_c": {
        "avg": {
          "field": "ambient_temperature_c"
        }
      },
      "start_time": {
        "min": {
          "field": "@timestamp"
        }
      },
      "end_time": {
        "max": {
          "field": "@timestamp"
        }
      }
    }
  }
}'


