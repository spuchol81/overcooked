import json
import random
import argparse
import math
from datetime import datetime, timedelta

def generate_split_cook(cook_id):
    total_points = 1000
    duration_min = 105  # 1 hour 45 total
    start_dt = datetime.now() - timedelta(hours=3)
    
    all_data = []

    
        # Determine start/end indices for each phase
    start_idx, end_idx = (0, 1000)
    data = []

    for i in range(start_idx, end_idx):
        p = i / total_points
        curr_time = start_dt + timedelta(minutes=p * duration_min)
        
        meat_temp = 10 + 65 * (1 - math.exp(-3 * p))
        ambient = 180 + random.uniform(-2, 2)

        data.append(json.dumps({ "create": { } }))
        data.append(json.dumps({
            "@timestamp": curr_time.strftime("%Y-%m-%dT%H:%M:%S.000Z"),
            "cook_id": cook_id,
            "recipe": "chicken",
            "ambient_temperature_c": round(ambient, 1),
            "meat_temperature_c": round(meat_temp, 1)
        }))

    filename = f"{cook_id}.ndjson"
    with open(filename, "w") as f:
        f.write("\n".join(data) + "\n")
    print(f"Generated cook {cook_id} ({end_idx - start_idx} points).")
    all_data.extend(data)

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--cook_id", type=str, default="test-split-01")
    args = parser.parse_args()
    cook_id = args.cook_id
    generate_split_cook(cook_id)
