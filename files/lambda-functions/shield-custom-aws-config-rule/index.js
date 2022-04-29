const aws = require('aws-sdk');

const config = new aws.ConfigService();

const shield = new aws.Shield();

// Helper function used to validate input
function checkDefined(reference, referenceName) {
	if (!reference) {
		throw new Error(`Error: ${referenceName} is not defined`);
	}
	return reference;
}

// Check whether the message is OversizedConfigurationItemChangeNotification or not
function isOverSizedChangeNotification(messageType) {
	checkDefined(messageType, 'messageType');
	return messageType === 'OversizedConfigurationItemChangeNotification';
}

// Get configurationItem using getResourceConfigHistory API.
function getConfiguration(resourceType, resourceId, configurationCaptureTime, callback) {
	config.getResourceConfigHistory({
		resourceType,
		resourceId,
		laterTime: new Date(configurationCaptureTime),
		limit: 1
	}, (err, data) => {
		if (err) {
			callback(err, null);
		}
		const configurationItem = data.configurationItems[0];
		callback(null, configurationItem);
	});
}

// Convert from the API model to the original invocation model
/*eslint no-param-reassign: ["error", { "props": false }]*/
function convertApiConfiguration(apiConfiguration) {
	apiConfiguration.awsAccountId = apiConfiguration.accountId;
	apiConfiguration.ARN = apiConfiguration.arn;
	apiConfiguration.configurationStateMd5Hash = apiConfiguration.configurationItemMD5Hash;
	apiConfiguration.configurationItemVersion = apiConfiguration.version;
	apiConfiguration.configuration = JSON.parse(apiConfiguration.configuration);
	if ({}.hasOwnProperty.call(apiConfiguration, 'relationships')) {
		for (let i = 0; i < apiConfiguration.relationships.length; i++) {
			apiConfiguration.relationships[i].name = apiConfiguration.relationships[i].relationshipName;
		}
	}
	return apiConfiguration;
}

// Based on the type of message get the configuration item either from configurationItem in the invoking event or using the getResourceConfigHistiry API in getConfiguration function.
function getConfigurationItem(invokingEvent, callback) {
	checkDefined(invokingEvent, 'invokingEvent');
	if (isOverSizedChangeNotification(invokingEvent.messageType)) {
		const configurationItemSummary = checkDefined(invokingEvent.configurationItemSummary, 'configurationItemSummary');
		getConfiguration(configurationItemSummary.resourceType, configurationItemSummary.resourceId, configurationItemSummary.configurationItemCaptureTime, (err, apiConfigurationItem) => {
			if (err) {
				callback(err);
			}
			const configurationItem = convertApiConfiguration(apiConfigurationItem);
			callback(null, configurationItem);
		});
	} else {
		checkDefined(invokingEvent.configurationItem, 'configurationItem');
		callback(null, invokingEvent.configurationItem);
	}
}

// Check whether the resource has been deleted. If it has, then the evaluation is unnecessary.
function isApplicable(configurationItem, event) {
	checkDefined(configurationItem, 'configurationItem');
	checkDefined(event, 'event');
	const status = configurationItem.configurationItemStatus;
	const eventLeftScope = event.eventLeftScope;
	return (status === 'OK' || status === 'ResourceDiscovered') && eventLeftScope === false;
}

// This is where it's determined whether the resource is compliant or not.
// We simply decide that the resource is compliant if it is a Shield Resource and its Application Layer Automatic Response Status is set to Enabled.
// If the resource is not a Shield resource, then we deem this resource to be not applicable.
function evaluateChangeNotificationCompliance(configurationItem, ruleParameters) {
	checkDefined(configurationItem, 'configurationItem');
	checkDefined(configurationItem.configuration, 'configurationItem.configuration');
	checkDefined(ruleParameters, 'ruleParameters');
	let params = {
		ResourceARN: `arn:aws:shield::${configurationItem.awsAccountId}:protection/${configurationItem.resourceId}`
	};

	// Promise which is only resolved when the tag value is retrieved
	let checkEnableShieldAutomaticMitigation = new Promise(function(resolve, reject) {
		shield.listTagsForResource(params, function(err, data) {
			if (err) {
				reject("FALSE");
			} // an error occurred
			else {
				let tag = data.Tags.find(t => t.Key === 'EnableShieldAutomaticMitigation');
				try {
					if (tag.Value == null) {
						resolve("FALSE");
					} else {
						resolve(tag.Value);
						// successful response
					}
				} catch {
					resolve("FALSE");
				}
			}
		});
	});

	// The resolution of the promise is stored in EnableShieldAutomaticMitigation and used to check if the resource is eligible to be checked for compliance
	return checkEnableShieldAutomaticMitigation.then(
		EnableShieldAutomaticMitigation => {
			if (configurationItem.resourceType !== 'AWS::Shield::Protection' || EnableShieldAutomaticMitigation !== "true") {
				return 'NOT_APPLICABLE';
				// Resource is only eligible if is it a shield resource and the tag value EnableShieldAutomaticMitigation is set to True 
			} else if (ruleParameters.ApplicationLayerAutomaticResponseConfiguration === configurationItem.configuration.ApplicationLayerAutomaticResponseConfig.Status) {
				return 'COMPLIANT';
				// The resource is COMPLIANT if ApplicationLayerAutomaticResponse is enabled
			}
			return 'NON_COMPLIANT';
				// If ApplicationLayerAutomaticResponse is not enabled then the resource is NON_COMPLIANT
		},
		rej => {
			return 'NOT_APPLICABLE';
				// If the all checks failed then the resource is not eligible.
		}
	).catch(err => console.err(err));
}

// This is the handler that's invoked by Lambda
exports.handler = (event, context, callback) => {
	checkDefined(event, 'event');
	const invokingEvent = JSON.parse(event.invokingEvent);
	const ruleParameters = JSON.parse(event.ruleParameters);

	getConfigurationItem(invokingEvent, (err, configurationItem) => {
		if (err) {
			callback(err);
		}
		let compliance = 'NOT_APPLICABLE';
		const putEvaluationsRequest = {};

		// Retrieves the return value (the compliance status) from the last .then and stores it in complianceResponse
		// complianceResponse is used to set compliance
		evaluateChangeNotificationCompliance(configurationItem, ruleParameters)
			.then( complianceResponse => {
				
				if (isApplicable(configurationItem, event)) {
					// Invoke the compliance checking function.
					compliance = complianceResponse;
				}

				// Put together the request that reports the evaluation status
				putEvaluationsRequest.Evaluations = [{
					ComplianceResourceType: configurationItem.resourceType,
					ComplianceResourceId: configurationItem.resourceId,
					ComplianceType: compliance,
					OrderingTimestamp: configurationItem.configurationItemCaptureTime,
				}];
				putEvaluationsRequest.ResultToken = event.resultToken;

				// Invoke the Config API to report the result of the evaluation
				config.putEvaluations(putEvaluationsRequest, (error, data) => {
					if (error) {
						callback(error, null);
					} else if (data.FailedEvaluations.length > 0) {
						// Ends the function execution if any evaluation results are not successfully reported.
						callback(JSON.stringify(data), null);
					} else {
						callback(null, data);
					}
				});
			});
	});
};
