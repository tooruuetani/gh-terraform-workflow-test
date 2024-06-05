import json


def lambda_handler(event, context):
    return {
        "statusCode": 200,
        "body": json.dumps({"test": 123456, "test_message": "Hello, World!"}),
    }
