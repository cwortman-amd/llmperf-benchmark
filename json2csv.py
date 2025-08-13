import json
import csv
import sys

# Check if filename is provided as an argument
if len(sys.argv) != 2:
    print("Usage: python script_name.py <input_file.jsonl>")
    sys.exit(1)

# Input and output file paths
input_file = sys.argv[1]
output_file = input_file.rsplit('.', 1)[0] + '.csv'

# Open the JSONL file and read line by line
with open(input_file, 'r') as jsonl_file, open(output_file, 'w', newline='') as csv_file:
    writer = None
    for line in jsonl_file:
        data = json.loads(line.strip())

        # Initialize the CSV writer with headers from the first JSON object
        if writer is None:
            writer = csv.DictWriter(csv_file, fieldnames=data.keys())
            writer.writeheader()

        # Write each JSON object as a row in the CSV file
        writer.writerow(data)

print(f"Conversion complete. Output file: {output_file}")
