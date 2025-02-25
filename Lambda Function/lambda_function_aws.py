import json
import boto3
import pandas as pd
import psycopg2
import os
import logging

#Add 'Pandas' and 'psycopg2' as a layer in the lambda function
# Source: https://youtu.be/5WsOvLr-0Yk

# Initialize Logger
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize S3 client
s3_client = boto3.client("s3")

# Database Credentials (From Lambda Environment Variables)
DB_HOST = os.environ["RDS_HOST"]
DB_NAME = os.environ["RDS_DB"]
DB_USER = os.environ["RDS_USER"]
DB_PASS = os.environ["RDS_PASS"]

def lambda_handler(event, context):
    try:
        logger.info("Lambda execution started")
        
        # Extract bucket and file name from S3 event
        bucket_name = event["Records"][0]["s3"]["bucket"]["name"]
        file_key = event["Records"][0]["s3"]["object"]["key"]
        logger.info(f"Bucket: {bucket_name}, File: {file_key}")

        # Download file from S3
        local_file_path = f"/tmp/{os.path.basename(file_key)}"
        s3_client.download_file(bucket_name, file_key, local_file_path)
        logger.info(f"File downloaded to {local_file_path}")

        # Load CSV into Pandas DataFrame
        df = pd.read_csv(local_file_path)
        logger.info(f"Rows fetched from CSV: {len(df)}")

        # Transform - Filter Valid Transactions
        valid_transactions = df[
            ((df["oldbalanceorg"] - df["newbalanceorig"]).round(2) >= df["amount"]) |
            ((df["oldbalancedest"] + df["amount"]).round(2) >= df["newbalancedest"])
        ]
        logger.info(f"Valid transactions count: {len(valid_transactions)}")

        # Identify Fraud Transactions
        fraud_transactions = valid_transactions[
            (valid_transactions["isFraud"] == 1) | (valid_transactions["isFlaggedFraud"] == 1)
        ]
        logger.info(f"Fraud transactions count: {len(fraud_transactions)}")

        if fraud_transactions.empty:
            logger.info("No fraud transactions found.")
            return {
                "statusCode": 200,
                "body": json.dumps("No fraud transactions found.")
            }

        # Connect to PostgreSQL
        conn = psycopg2.connect(
            host=DB_HOST, dbname=DB_NAME, user=DB_USER, password=DB_PASS
        )
        cur = conn.cursor()
        logger.info("Database connection established")

        # Create Table (If Not Exists)
        create_table_query = """
        CREATE TABLE IF NOT EXISTS fraud_transactions (
            id SERIAL PRIMARY KEY,
            step INT,
            type VARCHAR(20),
            amount FLOAT,
            nameOrig VARCHAR(50),
            oldbalanceOrg FLOAT,
            newbalanceOrig FLOAT,
            nameDest VARCHAR(50),
            oldbalanceDest FLOAT,
            newbalanceDest FLOAT,
            isFraud INT,
            isFlaggedFraud INT
        );
        """
        cur.execute(create_table_query)
        logger.info("Ensured table exists")

        # Batch Insert Data
        insert_query = """
        INSERT INTO fraud_transactions 
        (step, type, amount, nameOrig, oldbalanceOrg, newbalanceOrig, nameDest, oldbalanceDest, newbalanceDest, isFraud, isFlaggedFraud)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s);
        """

        data_to_insert = [tuple(row) for _, row in fraud_transactions.iterrows()]
        cur.executemany(insert_query, data_to_insert)

        conn.commit()
        logger.info(f"{len(fraud_transactions)} fraud transactions inserted into RDS")

        cur.close()
        conn.close()
        logger.info("Database connection closed")

        return {
            "statusCode": 200,
            "body": json.dumps(f"{len(fraud_transactions)} fraud transactions processed and stored in RDS!")
        }

    except Exception as e:
        logger.error(f"Error encountered: {str(e)}")
        return {"statusCode": 500, "body": json.dumps(str(e))}
