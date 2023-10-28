#!/usr/bin/python3

import os, sys
from influxdb_client import InfluxDBClient, Point
from influxdb_client.client.write_api import SYNCHRONOUS

if len(sys.argv) < 3:
    print("Usage: python client-disconnect.py <InfluxDB Access Token> <VPN Name>")
    sys.exit(1)

# Command-line arguments
token = sys.argv[1]
vpn_name = sys.argv[2]

# InfluxDB connection details (modify as needed)
org = "cloudstaff"
bucket = "vpnuses"
url = "https://metrics.cloudstaff.com:8443"

# Create InfluxDB client
client = InfluxDBClient(url=url, token=token, org=org)

# Create a write API
write_api = client.write_api(write_options=SYNCHRONOUS)

try:
    # Get values from environment variables
    remoteip = os.environ.get('untrusted_ip', '')
    bytesrec = int(os.environ.get('bytes_received', '0'))
    bytessent = int(os.environ.get('bytes_sent', '0'))
    duration = int(os.environ.get('time_duration', '0'))
    common_name = os.environ.get('common_name', '')

    # Create a Point with tags and fields
    point = Point("vpnuses").tag("common_name", common_name).tag("vpn_name", vpn_name).field("remoteip", remoteip).field("bytes_received", bytesrec).field("bytes_sent", bytessent).field("time_duration", duration)

    # Write the point to InfluxDB
    write_api.write(bucket=bucket, record=point)

    print(f"common_name: {common_name}, duration: {duration}, remoteip: {remoteip}, bytesrec: {bytesrec}")

except Exception as e:
    print(f"Error writing data to InfluxDB: {e}")

finally:
    # Close the InfluxDB client
    client.close()