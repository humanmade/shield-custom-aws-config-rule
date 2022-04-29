def lambda_handler(event, context):
    # import boto3 for AWS
    import boto3
    
    # Create boto3 client for AWS Shield
    shield_client = boto3.client('shield')
    
    # Retrieve resource ID from AWS Systems Manager Automation
    resourceID = event['ResourceID']
    
    # Retrieve CloudFront Resource Arn associated with Shield Resource
    resource = shield_client.describe_protection(ProtectionId=resourceID)
    cloudfrontResourceArn = resource['Protection']['ResourceArn']
    
    # Enable Application Layer Automatic Response
    response = shield_client.enable_application_layer_automatic_response(ResourceArn=cloudfrontResourceArn, Action={'Block': {}})
    
    # Return response to AWS Systems Manager Automation
    return response
