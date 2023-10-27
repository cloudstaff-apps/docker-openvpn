#!/usr/bin/python3

import time
import boto3
import os

from botocore.config import Config

# Define default values
DEFAULT_DATABASE_NAME = "CSMonitoringDB"
DEFAULT_TABLE_NAME = "VpnUses"
DEFAULT_TIMESTREAM_REGION = "us-west-2"

# Get values from environment variables or use default values
DATABASE_NAME = os.environ.get('DATABASE_NAME', DEFAULT_DATABASE_NAME)
TABLE_NAME = os.environ.get('TABLE_NAME', DEFAULT_TABLE_NAME)
TIMESTREAM_REGION = os.environ.get('TABLE_NAME', DEFAULT_TIMESTREAM_REGION)

def prepare_common_attributes():
    common_attributes = {
        'Dimensions': [
            {'Name': 'domain_name', 'Value': os.environ['DOMAIN_NAME']},
            {'Name': 'common_name', 'Value': os.environ['common_name']}
        ]
    }
    return common_attributes

def prepare_record(current_time, name, localip, remoteip, bytesrec, bytessent, duration):
    record = {
        'Time': str(current_time),
        'MeasureValues': [
            prepare_measure('name', name),
            prepare_measure('localip', localip),
            prepare_measure('remoteip', remoteip),
            prepare_measure('bytes_received', bytesrec),
            prepare_measure('bytes_sent', bytessent),
            prepare_measure('time_duration', duration)
        ]
    }
    return record

def prepare_measure(measure_name, measure_value):
    measure_type = 'DOUBLE' if measure_value != 'TIMESTAMP' else 'TIMESTAMP'
    measure = {
        'Name': measure_name,
        'Value': str(measure_value),
        'Type': measure_type
    }
    return measure

def write_records(records, common_attributes):
    try:
        session = boto3.Session(region_name=TIMESTREAM_REGION)
        write_client = session.client('timestream-write', config=Config(
            read_timeout=20, max_pool_connections=5000, retries={'max_attempts': 10}))

        result = write_client.write_records(DatabaseName=DATABASE_NAME,
                                            TableName=TABLE_NAME,
                                            CommonAttributes=common_attributes,
                                            Records=records)
        status = result['ResponseMetadata']['HTTPStatusCode']
        print("Processed %d records. WriteRecords HTTPStatusCode: %s" %
              (len(records), status))
    except Exception as err:
        print("Error:", err)

if __name__ == '__main':
    print("writing data to database {} table {}".format(
        DATABASE_NAME, TABLE_NAME))

    common_attributes = prepare_common_attributes()
    records = []

    current_time = int(time.time() * 1000)
    name = os.environ['common_name']
    localip = os.environ['ifconfig_pool_remote_ip']
    remoteip = os.environ['untrusted_ip']
    bytesrec = os.environ['bytes_received']
    bytessent = os.environ['bytes_sent']
    duration = os.environ['time_duration']

    record = prepare_record(current_time, name, localip, remoteip, bytesrec, bytessent, duration)
    records.append(record)

    write_records(records, common_attributes)
