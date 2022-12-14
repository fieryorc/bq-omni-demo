# BigQuery Omni AWS Demo
This demo script provides easy way to connect BigQuery Omni to the
AWS S3 dataset and run a query one it. This automates creating AWS roles/policies, 
Omni connection, dataset and external tables.

Using this script you will be able to create an external table to connect to AWS S3 dataset.


## Prerequisites to run the demo
1. AWS Account ID
2. AWS Access Key
3. AWS Access Secret
4. AWS Session ID (if applicable)
5. AWS S3 bucket name and Path to the data files (supported formats: PARQUET, JSON, AVRO)
6. GCP Project (with billing enabled and necessary permissions)


## Running the script
1. Open [cloud console shell](https://console.cloud.google.com/welcome?cloudshell=true)
2. Select the GCP project
3. Run the following command in the cloud shell:

```
curl -L https://raw.githubusercontent.com/fieryorc/bq-omni-demo/main/omni-aws-demo.sh -o /tmp/omni-aws-demo.sh && \
    chmod 755 /tmp/omni-aws-demo.sh && \
    /tmp/omni-aws-demo.sh
```

This script will do the following:

1. Connect to AWS and verify access
2. Enable BigQuery APIs in GCP
3. Create BigQuery connection
4. Create AWS Role, Policy
5. Create Omni dataset in aws-us-east-1 region
6. Create external table
7. Run a sample query

The script will print the progress as it executes. If for any reason the script fails, you can
rerun the script. User input is cached so you don't have to re-enter the values (instead press enter).


## Next steps
You can open cloud console, launch bigquery SQL page and run more queries on the external table created.
Also, you can create more external table using the same connection created by the demo script.

[BigQuery Omni Documentation](https://cloud.google.com/bigquery/docs/omni-aws-introduction)


## Cleanup
Script stores all the user inputs in the cache file `omni-aws-demo.info` in the current directory.
Delete this file if you no longer would like to cache the inputs.