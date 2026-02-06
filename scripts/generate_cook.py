import json
import random
import math
import os
from datetime import datetime, timedelta

def generate_year_of_cooks():
    # Create an output directory for the 52 files
    output_dir = "cooks_2025"
    if not os.path.exists(output_dir):
        os.makedirs(output_dir)

    # Start from the first Saturday of 2025
    # Jan 1, 2025 was a Wednesday. First Sat is Jan 4th.
    current_date = datetime(2025, 1, 4, 10, 0, 0) 
    
    for week in range(1, 53):
        recipe = random.choice(['pulled_pork', 'chicken'])
        cook_id = f"cook-W{week:02d}"
        filename = os.path.join(output_dir, f"{cook_id}_{recipe}.ndjson")
        
        # Configuration
        if recipe == "pulled_pork":
            duration_min = random.randint(480, 600)  # 8-10 hours variation
            ambient_base = 110.0
        else:
            duration_min = random.randint(75, 105)   # 1.25-1.75 hours variation
            ambient_base = 180.0

        points = 1000
        data = []

        for i in range(points):
            p = i / points
            timestamp = current_date + timedelta(minutes=p * duration_min)
            
            # Meat Temperature Logic
            if recipe == "pulled_pork":
                if p < 0.3: meat_temp = 10 + (60 * (p / 0.3))
                elif p < 0.65: meat_temp = 70 + random.uniform(-0.3, 0.5)
                else: meat_temp = 70 + (25 * ((p - 0.65) / 0.35))
                ambient = (125 if p > 0.7 else ambient_base) + random.uniform(-4, 4)
            else:
                meat_temp = 10 + 65 * (1 - math.exp(-3 * p))
                ambient = ambient_base + random.uniform(-2, 2)

            data.append(json.dumps({ "create": { } }))
            data.append(json.dumps({
                "@timestamp": timestamp.strftime("%Y-%m-%dT%H:%M:%S.000Z"),
                "cook_id": cook_id,
                "recipe": recipe,
                "ambient_temperature_c": round(ambient, 1),
                "meat_temperature_c": round(meat_temp, 1)
            }))

        with open(filename, "w") as f:
            f.write("\n".join(data) + "\n")
        
        # Advance to the next Saturday
        current_date += timedelta(days=7)

    print(f"Done! Generated 52 files in the '{output_dir}' directory.")

if __name__ == "__main__":
    generate_year_of_cooks()