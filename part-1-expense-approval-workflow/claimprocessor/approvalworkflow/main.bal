import ballerina/http;
import ballerina/workflow;
import ballerina/workflow.management;
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
        string workflowId = check workflow:run(expenseApproval, claim);
        return {claimId: claim.claimId, workflowId, status: "SUBMITTED"};
    }

    resource function get [string workflowId]() returns Response|error {
        management:WorkflowExecutionInfo info = check management:getWorkflowInfo(workflowId);
        if info.status != "COMPLETED" {
            return {workflowId, status: info.status};
        }
        anydata result = check workflow:getWorkflowResult(workflowId);
        return {workflowId, status: info.status, result: result.toString()};
    }
}

