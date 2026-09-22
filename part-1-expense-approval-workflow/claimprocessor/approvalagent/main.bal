import ballerina/http;
import ballerina/workflow;
import ballerina/workflow.management as _;
import ballerina/workflow.management.rest as _;
import ballerinax/metrics.logs as _;

import wso2/icp.runtime.bridge as _;

listener http:Listener httpDefaultListener = http:getDefaultListener();

@http:ServiceConfig {
    cors: {
        allowOrigins: ["*"],
        allowMethods: ["*"]
    }
}
service /expenses on httpDefaultListener {

    resource function post .(Claim claim) returns Response|error {
        string workflowId = check expenseApproval.run(claim.toJsonString());
        return {claimId: claim.claimId, workflowId, status: "SUBMITTED"};
    }

    resource function get [string workflowId]() returns Response|error {
        string|error result = expenseApproval.getResult(workflowId);
        if result is workflow:AgentBusyError {
            return {workflowId, status: "RUNNING"};
        }
        if result is error {
            return result;
        }
        return {workflowId, status: "COMPLETED", result};
    }
}

