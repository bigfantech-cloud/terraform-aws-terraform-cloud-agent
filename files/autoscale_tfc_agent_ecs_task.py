import boto3
import hashlib
import hmac
import json
import os


ECS_CLUSTER_NAME                        = os.getenv("ECS_CLUSTER_NAME", None)
ECS_SERVICE_NAME                        = os.getenv("ECS_SERVICE_NAME", None)
REGION                                  = os.getenv("REGION", None)
MAX_AGENTS                              = os.getenv("MAX_AGENTS", None)
NOTIFICATION_TOKEN_SSM_PARAMETER_NAME   = os.getenv("NOTIFICATION_TOKEN_SSM_PARAMETER_NAME", None)
TFC_CURRENT_COUNT_SSM_PARAMETER_NAME    = os.getenv("TFC_CURRENT_COUNT_SSM_PARAMETER_NAME", None)


ADD_SERVICE_STATES = {'pending'}
SUB_SERVICE_STATES = {
    'errored',
    'canceled',
    'discarded',
    'planned_and_finished',
    'applied',
    'completed'
}


# Initialize boto3 client at global scope for connection reuse
session = boto3.Session(region_name=REGION)
ssm = session.client('ssm')
ecs = session.client('ecs')


def lambda_handler(event, context):
    print(event)
    message = bytes(event['body'], 'utf-8')
    secret = bytes(ssm.get_parameter(Name=NOTIFICATION_TOKEN_SSM_PARAMETER_NAME, WithDecryption=True)['Parameter']['Value'], 'utf-8')
    hash = hmac.new(secret, message, hashlib.sha512)
    if hash.hexdigest() == event['headers']['X-Tfe-Notification-Signature']:
        # HMAC verified
        if event['httpMethod'] == "POST":
            return post(event)
        return get()
    return 'Invalid HMAC'


def get():
    return {
        "statusCode": 200,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*"
        },
        "body": "I'm here!"
        }


def post(event):
    payload = json.loads(event['body'])
    post_response = "I'm here!"

    response = ecs.describe_services(
        cluster=ECS_CLUSTER_NAME,
        services=[
            ECS_SERVICE_NAME,
        ]
    )

    service_count = response['services'][0]['desiredCount']
    print("Current service count:", int(service_count))

    if payload and 'run_status' in payload['notifications'][0]:
        body = payload['notifications'][0]
        if body['run_status'] in ADD_SERVICE_STATES:
            post_response = update_service_count(ecs, 'add')
            print("Run status indicates add an agent.")
        elif body['run_status'] in SUB_SERVICE_STATES:
            post_response = update_service_count(ecs, 'sub')
            print("Run status indicates subtract an agent.")

    return {
        "statusCode": 200,
        "body": json.dumps(post_response)
    }


def update_service_count(client, operation):
    num_runs_queued = int(ssm.get_parameter(Name=TFC_CURRENT_COUNT_SSM_PARAMETER_NAME)['Parameter']['Value'])
    if operation is 'add':
        num_runs_queued = num_runs_queued + 1
    elif operation is 'sub':
        num_runs_queued=num_runs_queued - 1 if num_runs_queued > 0 else 0
    else:
        return
    response = ssm.put_parameter(Name=TFC_CURRENT_COUNT_SSM_PARAMETER_NAME, Value=str(num_runs_queued), Type='String', Overwrite=True)

    desired_count=int(MAX_AGENTS) if num_runs_queued > int(MAX_AGENTS) else num_runs_queued
    client.update_service(
        cluster=ECS_CLUSTER_NAME,
        service=ECS_SERVICE_NAME,
        desiredCount=desired_count
    )

    print("Updated service count:", desired_count)
    return("Updated service count:", desired_count)
