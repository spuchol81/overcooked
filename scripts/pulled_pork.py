import json
import random
import argparse
import os
import requests
from datetime import datetime, timedelta

ES_URL = "http://elasticsearch-es-http.default.svc:9200"
INDEX_NAME = "live-cooking"
ENV_FILE = "/home/kubernetes-vm/env"


def load_apikey():
    with open(ENV_FILE) as f:
        for line in f:
            if line.startswith("ELASTICSEARCH_APIKEY"):
                return line.strip().split("=", 1)[1]
    raise Exception("ELASTICSEARCH_APIKEY not found in env file")


def generate_all_phases(cook_id):
    total_points = 1000
    duration_min = 540  # 9 hours total
    start_dt = datetime.utcnow() - timedelta(hours=5)

    for phase in [1, 2]:
        start_idx, end_idx = (0, 500) if phase == 1 else (500, 1000)
        data = []

        for i in range(start_idx, end_idx):
            p = i / total_points
            curr_time = start_dt + timedelta(minutes=p * duration_min)

            # Pulled Pork logic
            if p < 0.3:
                meat_temp = 10 + (60 * (p / 0.3))
            elif p < 0.65:
                meat_temp = 70 + random.uniform(-0.2, 0.4)
            else:
                meat_temp = 70 + (25 * ((p - 0.65) / 0.35))

            ambient = (125 if p > 0.7 else 110.0) + random.uniform(-3, 3)

            data.append(json.dumps({ "create": {} }))
            data.append(json.dumps({
                "@timestamp": curr_time.strftime("%Y-%m-%dT%H:%M:%S.000Z"),
                "cook_id": cook_id,
                "recipe": "pulled_pork",
                "ambient_temperature_c": round(ambient, 1),
                "meat_temperature_c": round(meat_temp, 1)
            }))

        filename = f"{cook_id}_phase_{phase}.ndjson"
        with open(filename, "w") as f:
            f.write("\n".join(data) + "\n")

        print(f"Generated {filename}")


def ingest_phase(cook_id, phase):
    filename = f"{cook_id}_phase_{phase}.ndjson"