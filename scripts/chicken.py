import json
import random
import argparse
import math
import os
import requests
from datetime import datetime, timedelta

ES_URL = "http://elasticsearch-es-http.default.svc:9200"
INDEX_NAME = "live-cooking"
ENV_FILE = "/home/kubernetes-vm/env"
ORDERS_INDEX = "orders"


def load_apikey():
    with open(ENV_FILE) as f:
        for line in f:
            if line.startswith("ELASTICSEARCH_APIKEY"):
                return line.strip().split("=", 1)[1]
    raise Exception("ELASTICSEARCH_APIKEY not found in env file")


def generate_split_cook(cook_id):
    total_points = 1000
    duration_min = 105  # 1 hour 45 total
    start_dt = datetime.utcnow() - timedelta(hours=3)

    data = []

    for i in range(total_points):
        p = i / total_points
        curr_time = start_dt + timedelta(minutes=p * duration_min)

        meat_temp = 10 + 65 * (1 - math.exp(-3 * p))
        ambient = 180 + random.uniform(-2, 2)

        data.append(json.dumps({ "create": {} }))
        data.append(json.dumps({
            "@timestamp": curr_time.strftime("%Y-%m-%dT%H:%M:%S.000Z"),
            "cook_id": cook_id,
            "recipe": "chicken",
            "ambient_temperature_c": round(ambient, 1),
            "meat_temperature_c": round(meat_temp, 1)
        }))

    return "\n".join(data) + "\n"


def ingest_to_elasticsearch(ndjson_data):
    api_key = load_apikey()
    
    headers = {
        "Content-Type": "application/x-ndjson",
        "Authorization": f"ApiKey {api_key}"
    }

    response = requests.post(
        f"{ES_URL}/{INDEX_NAME}/_bulk",
        headers=headers,
        data=ndjson_data
    )

    if response.status_code >= 300:
        print("Bulk ingestion failed:")
        print(response.text)
    else:
        print("Bulk ingestion successful.")
        print(response.json())

def ack_order(cook_id):
    api_key = load_apikey()

    headers = {
        "Authorization": f"ApiKey {api_key}",
        "Content-Type": "application/json"
    }
    payload = {
        "query": {
            "term": {
                "order_id": cook_id 
            }
        },
        "script": {
            "source": "ctx._source.status = 'ongoing'", 
            "lang": "painless"
        }
    }

    response = requests.post(
        f"{ES_URL}/{ORDERS_INDEX}/_update_by_query",
        headers=headers,
        json=payload
    )

    if response.status_code >= 300:
        print("order ack failed:")
        print(response.text)
    else:
        print("order ack successful.")
        print(response.json())


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--cook_id", type=str, default="test-split-01")
    args = parser.parse_args()

    cook_id = args.cook_id

    print(f"Generating cook data for {cook_id}...")
    ndjson_payload = generate_split_cook(cook_id)

    print("Ingesting into Elasticsearch...")
    ingest_to_elasticsearch(ndjson_payload)

    print("acknowledging order...")
    ack_order(cook_id)