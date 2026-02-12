#!/bin/bash 
set -euxo pipefail

######### ENV ##########

ENV_FILE_PARENT_DIR=/home/kubernetes-vm
ENV_FILE=$ENV_FILE_PARENT_DIR/env
export $(cat $ENV_FILE | xargs)

############functions######@

bulk_upload_file() {
  local file="$1"
  local ES_URL="$2"
  local response_file
  response_file=$(mktemp)

  http_status=$(curl -sS \
    -o "$response_file" \
    -w "%{http_code}" \
    -X POST "$ES_URL" \
    -H "Content-Type: application/x-ndjson" \
    -H "Authorization: ApiKey $ELASTICSEARCH_APIKEY" \
    --data-binary "@$file")

  # Check HTTP status
  if [[ ! "$http_status" =~ ^2 ]]; then
    echo "HTTP error $http_status for $file"
    rm -f "$response_file"
    return 1
  fi

  # Check Elasticsearch bulk errors flag
  if jq -e '.errors == false' "$response_file" >/dev/null 2>&1; then
    echo "Bulk upload successful: $file"
    rm -f "$response_file"
    return 0
  else
    echo "Bulk API reported errors in $file"
    rm -f "$response_file"
    return 1
  fi
}

retry_command_lin() {
  local retries=5
  local delay=2
  local count=1

  until "$@"; do
    if (( count >= retries )); then
      echo "Command failed after $retries attempts."
      return 1
    fi

    sleep_time=$((delay ** count))
    echo "Retry $count/$retries in ${sleep_time}s..."
    sleep "$sleep_time"
    ((count++))
  done
}



########## Solution view ##########

/opt/workshops/elastic-view.sh -v oblt


########### AI SETUP ###########
/opt/workshops/elastic-llm.sh -k true

####push 2025 BBQ data #####
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


cd overcooked

for file in cooks_2025/*.ndjson;
do                                                                          
#curl -H "Content-Type: application/x-ndjson" -H "Authorization: ApiKey $ELASTICSEARCH_APIKEY" -XPOST "http://elasticsearch-es-http.default.svc:9200/metrics-cook_sensors-2025/_bulk" --data-binary "@$file"
retry_command_lin bulk_upload_file "$file" "http://elasticsearch-es-http.default.svc:9200/metrics-cook_sensors-2025/_bulk" || exit 1
done

####### create transform for ml job ###########

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
          "meat_temperature_c.max": {
            "max": {
              "field": "meat_temperature_c"
            }
          },
          "end_time": {
            "max": {
              "field": "@timestamp"
            }
          },
          "start_time": {
            "min": {
              "field": "@timestamp"
            }
          },
          "ambient_temperature_c.avg": {
            "avg": {
              "field": "ambient_temperature_c"
            }
          },
          "meat_temperature_c.min": {
            "min": {
              "field": "meat_temperature_c"
            }
          },
          "total_duration_minutes": {
            "bucket_script": {
              "buckets_path": {
                "start": "start_time",
                "end": "end_time"
              },
              "script": "(Math.round((params.end - params.start) / 60000))"
          }
        }
  }
}}'

curl -H "Authorization: ApiKey $ELASTICSEARCH_APIKEY" \
     -H "Content-Type: application/json" \
     -X POST "http://elasticsearch-es-http.default.svc:9200/_transform/2025_cooking_stats/_start"

sleep 5

curl -H "Authorization: ApiKey $ELASTICSEARCH_APIKEY" \
     -H "Content-Type: application/json" \
     -X PUT "http://elasticsearch-es-http.default.svc:9200/_ml/data_frame/analytics/cooking_time_prediction" \
     -d '
{
  "description": "Regression model to predict cooking duration",
  "source": {
    "index": [
      "2025_cooking_stats"
    ],
    "query": {
      "match_all": {}
    }
  },
  "dest": {
    "index": "cooking_time_prediction",
    "results_field": "ml"
  },
  "analysis": {
    "regression": {
      "dependent_variable": "total_duration_minutes",
      "prediction_field_name": "total_duration_minutes_prediction",
      "training_percent": 80,
      "randomize_seed": 3168482639878865400,
      "loss_function": "mse",
      "early_stopping_enabled": true,
      "num_top_feature_importance_values": 0
    }
  },
  "analyzed_fields": {
    "includes": [
      "recipe",
      "total_duration_minutes"
    ]
  },
  "model_memory_limit": "4mb",
  "max_num_threads": 1,
  "allow_lazy_start": false
}'

curl -H "Authorization: ApiKey $ELASTICSEARCH_APIKEY" \
     -X POST \
     "http://elasticsearch-es-http.default.svc:9200/_ml/data_frame/analytics/cooking_time_prediction/_start"

while true; do
  STATE=$(curl -s -H "Authorization: ApiKey $ELASTICSEARCH_APIKEY" \
    "http://elasticsearch-es-http.default.svc:9200/_ml/data_frame/analytics/cooking_time_prediction/_stats" \
    | jq -r '.data_frame_analytics[0].state')

  echo "Current ml job state: $STATE"

  if [ "$STATE" = "stopped" ]; then
    echo "Job finished."
    break
  fi

  if [ "$STATE" = "failed" ]; then
    echo "Job failed."
    exit 1
  fi

  sleep 2
done

#### data views ####
curl -u "elastic:changeme" -H "Content-Type: application/json" -H "kbn-xsrf: true" -H "x-elastic-internal-origin: Kibana" -XPOST "http://kubernetes-vm:30001/api/data_views/data_view" -d \
'{
    "data_view": {
      "id": "metrics-cook_sensors",
      "title": "metrics-cook_sensors-*",
      "name": "Cook Sensors (Raw)",
      "timeFieldName": "@timestamp"
    }
}'

curl -u "elastic:changeme" -H "Content-Type: application/json" -H "kbn-xsrf: true" -H "x-elastic-internal-origin: Kibana" -XPOST "http://kubernetes-vm:30001/api/data_views/data_view" -d \
'{
    "data_view": {
      "id": "2025_cooking_stats",
      "title": "2025_cooking_stats",
      "name": "Cooking Stats (Transform)",
      "timeFieldName": "start_time"
    }
}'

curl -u "elastic:changeme" -H "Content-Type: application/json" -H "kbn-xsrf: true" -H "x-elastic-internal-origin: Kibana" -XPOST "http://kubernetes-vm:30001/api/data_views/data_view" -d \
'{
  "data_view": {
    "id": "cooking_time_prediction",
    "title": "cooking_time_prediction",
    "name": "Cooking Time Predictions (ML)",
    "timeFieldName": "start_time"
  }
}'

curl -u "elastic:changeme" -H "Content-Type: application/json" -H "kbn-xsrf: true" -H "x-elastic-internal-origin: Kibana" -XPOST "http://kubernetes-vm:30001/api/data_views/data_view" -d \
'{
  "data_view": {
    "id": "live-cooking",
    "title": "live-cooking",
    "name": "Live cooking data",
    "timeFieldName": "@timestamp"
  }
}'

MODEL_ID=$(curl -s -H "Authorization: ApiKey $ELASTICSEARCH_APIKEY" \
  "http://elasticsearch-es-http.default.svc:9200/_ml/trained_models?tags=cooking_time_prediction" \
  | jq -r '.trained_model_configs[0].model_id')

if [ -z "$MODEL_ID" ] || [ "$MODEL_ID" = "null" ]; then
  echo "No trained model found for cooking_time_prediction"
  exit 1
fi

curl -H "Authorization: ApiKey $ELASTICSEARCH_APIKEY" \
     -H "Content-Type: application/json" \
     -X PUT "http://elasticsearch-es-http.default.svc:9200/_ingest/pipeline/cooking_time_inference" \
     -d @- <<EOF
{
  "description": "Predict cooking time using DFA regression model $MODEL_ID",
  "processors": [
    {
      "inference": {
        "model_id": "$MODEL_ID",
        "ignore_failure": false,
        "target_field": "ml.inference.total_duration_minutes_prediction",
        "inference_config": {
          "regression": {
            "results_field": "total_duration_minutes_prediction",
            "num_top_feature_importance_values": 0
          }
        }
      }
    }
  ]
}
EOF


####prepare for live data #####
curl -H "Authorization: ApiKey $ELASTICSEARCH_APIKEY" \
     -H "Content-Type: application/json" \
     -X PUT "http://elasticsearch-es-http.default.svc:9200/_index_template/my-livecooking-index-template" \
     -d '
{
  "index_patterns": [
    "live-cooking"
  ],
  "data_stream": {
    "hidden": false,
    "allow_custom_routing": false
  },
  "priority": 500,
  "composed_of": [],
  "template": {
    "settings": {
    "index": {
              "default_pipeline": "cooking_time_inference"
            }
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


curl -u "elastic:changeme" -H "kbn-xsrf: true" -H "x-elastic-internal-origin: Kibana" -XPOST "http://kubernetes-vm:30001/api/saved_objects/_import?overwrite=true" -F "file=@dashboards/bbq.ndjson"






