## Shield Custom AWS Config Rule and Remediation

This module creates a custom AWS config rule which ensures eligible Shield Protection resources will always have the Automatic application layer DDoS mitigation enabled.


### How it works

The module accomplishes this by detecting the shield protection instances which have the tag key `EnableShieldAutomaticMitigation` with the value `true`, 
checks if the resource has Automatic application layer DDoS mitigation enabled; If the setting is `ENABLED` then the resource is reported as `COMPLIANT` 
but if the setting is `DISABLED` the resource is reported as `NON_COMPLIANT` by AWS Config.


If the resource is reported as `NON_COMPLIANT` AWS Config remediates the compliance of the resource by using a SSM Document which invokes a Lambda function to set 
Automatic application layer DDoS mitigation to `ENABLED` for the given resource using the AWS Shield API.

The module creates the following resources

#### Custom AWS Config Rule

- **shield-automitigation-enabled**
  - The AWS Config rule checks for Shield Protection resources only and passes on the resource configuration to the Lambda function `shield-custom-aws-config-rule` associated to it.
  - Once the rule has gotten the compliance status it automatically triggers the SSM Document ` ` to remediate the resource by passing the Resource ID of the NON_COMPLIANT resource.
  - A check by the AWS Config rule is triggered when a configuration change is detected in a Shield Protection resource.

#### AWS SSM Document

- **shield-automitigation-enabled-remediation**
  - The SSM document is triggered by the AWS Config Rule, it receives a Resource ID from the config rule
  - It then invokes the lambda function `shield-custom-aws-config-rule` and passes the Resource ID as an input.
  - If the execution of the lamdba function is successful then the SSM Document is also marked as successful.

#### Lambda functions

- **shield-custom-aws-config-rule**
  - The lambda function receives resource configuration from AWS config for all Shield Protection Resources as an input.
  - For all the resources fed in by AWS config it also uses the AWS shield SDK to retrieve the tags on on each resource.
  - It then uses the resource configuration and retrieve tags to perform two checks 
    - It checks if the resource is indeed a Shield Protection Resource by using the identifier `AWS::Shield::Protection`
    - It also checks if the resource has a tag key `EnableShieldAutomaticMitigation` and associate tag value `true`
    - If both are checks passes then it considers the resource `APPLICABLE` but if any of the checks fail then it considers the resource `NOT_APPLICABLE`
  - Next the script uses the resource configuration information received from AWS config to check if the resource has `ApplicationLayerAutomaticResponseConfig` set to ENABLED, if this check passes then the resource is considered to be `COMPLAINT` but if this fails then the resource is considered to be `NON_COMPLIANT`
  - The lambda function returns a final value of either `NOT_COMPLIANT`, `NOT_SUPPORTED`, `NOT_APPLICABLE` or `COMPLIANT` back to AWS Config based on the execution of the lambda function.

- **shield-custom-aws-config-remediation**
  - This function is used only for resource remediation.
  - The lambda function is invoked by the SSM document `shield-automitigation-enabled-remediation` and passes the `ResourceID` of the `NON_COMPLIANT`Shield Protection resource as an input.
  - The lambda function then uses the resource ID to retrieve the ARN of the resource via AWS boto3 SDK  and finally uses the ARN to set `ApplicationLayerAutomaticResponse` to `ENABLED` for the resource



### Requirements

In order allow the Shield Custom AWS Config Rule detect a resource which you want to always have Automatic application layer DDoS mitigation enabled you must add the tag key `EnableShieldAutomaticMitigation` to the resource and set its value to `true`. 

### Things to note when making changes

The `shield-custom-aws-config-remediation` lambda function which is named `lambda_function.py` requires the latest boto3 dependencies in order to run successful, because of this fact the dependencies are added to the `shield-custom-aws-config-remediation.zip` file which is deployed to the lambda function.

After making changes to the `lambda_function.py` you need to perform the following steps
- Navigate to the ./files/lambda-functions/shield-custom-aws-config-remediation/ directory
- Remove the existing shield-custom-aws-remediation.zip file using `rm -f ../zip/shield-custom-aws-config-remediation.zip`
- Create a temp directory using `mkdir tmp`
- Download the boto3 package into the temp directory using `pip install --target ./tmp boto3`
- Create a zipped file using `zip -r ../zip/shield-custom-aws-config-remediation.zip ./tmp`
- Delete the tmp directory `rm -rf tmp`
- Add the lambda function to the zipped file using `zip -g ../zip/shield-custom-aws-config-remediation.zip lambda_function.py`
- If you have zip files added to your .gitignore you will need to force add the file when committing using `git add --force`
