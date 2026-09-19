import ballerina/http;
import ballerina/workflow;
import ballerina/workflow.management;

listener http:Listener httpDefaultListener = http:getDefaultListener();

@http:ServiceConfig {
    cors: {
        allowOrigins: ["*"],
        allowMethods: ["*"]
    }
}
service /expenses on httpDefaultListener {

    resource function post .(Claim claim) returns json|error {
        string workflowId = check workflow:run(expenseApproval, claim);
        return {claimId: claim.claimId, workflowId, status: "SUBMITTED"};
    }

    resource function get [string workflowId]() returns json|error {
        // Check the status first instead of blocking on the result:
        // getWorkflowResult waits until the workflow completes.
        management:WorkflowExecutionInfo info = check management:getWorkflowInfo(workflowId);
        if info.status != "COMPLETED" {
            return {workflowId, status: info.status};
        }
        anydata result = check workflow:getWorkflowResult(workflowId);
        return {workflowId, status: info.status, result: check result.cloneWithType(json)};
    }
}
