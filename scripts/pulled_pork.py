import json
import random
import argparse
from datetime import datetime, timedelta

def generate_split_cook(cook_id):
    total_points = 1000
    duration_min = 540  # 9 hours total
    start_dt = datetime.now() - timedelta(hours=5)
    
    all_data = []

    for phase in [1, 2]:
        # Determine start/end indices for each phase
        start_idx, end_idx = (0, 500) if phase == 1 else (500, 1000)
        data = []

        for i in range(start_idx, end_idx):
            p = i / total_points
            curr_time = start_dt + timedelta(minutes=p * duration_min)
            
            # Pulled Pork Logic
            if p < 0.3:  # Initial rise
                meat_temp = 10 + (60 * (p / 0.3))
            elif p < 0.65:  # The Stall
                meat_temp = 70 + random.uniform(-0.2, 0.4)
            else:  # Final push
                meat_temp = 70 + (25 * ((p - 0.65) / 0.35))
            
            ambient = (125 if p > 0.7 else 110.0) + random.uniform(-3, 3)

            data.append(json.dumps({ "create": { } }))
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
        print(f"Generated Phase {phase} for {cook_id} ({end_idx - start_idx} points).")
        all_data.extend(data)

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--cook_id", type=str, default="test-split-01")
    args = parser.parse_args()
    cook_id = args.cook_id
    generate_split_cook(cook_id)
