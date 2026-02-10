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
curl -H "Content-Type: application/x-ndjson" -H "Authorization: ApiKey $ELASTICSEARCH_APIKEY" -XPOST "http://elasticsearch-es-http.default.svc:9200/metrics-cook_sensors-2025/_bulk" --data-binary "@$file"
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
              "script": "(params.end - params.start) / 60000"
          }
        }
  }
}'

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
      "ambient_temperature_c.avg",
      "cook_id",
      "meat_temperature_c.max",
      "meat_temperature_c.min",
      "recipe",
      "total_duration_minutes"
    ]
  },
  "model_memory_limit": "4mb",
  "max_num_threads": 1,
  "allow_lazy_start": false
}'





