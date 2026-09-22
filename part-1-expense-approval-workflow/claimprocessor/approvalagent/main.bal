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

    // Same request/response shape as ../backend's POST /expenses, so the same
    // web UI can submit a claim to either backend unmodified.
    resource function post .(Claim claim) returns json|error {
        string workflowId = check expenseApproval.run(claim.toJsonString());
        return {claimId: claim.claimId, workflowId, status: "SUBMITTED"};
    }

    // Same request/response shape as ../backend's GET /expenses/{workflowId}:
    // RUNNING while the agent is still working (including while it is
    // suspended on the approveExpense human task), COMPLETED with the
    // agent's final one-line summary once it is done.
    resource function get [string workflowId]() returns json|error {
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

