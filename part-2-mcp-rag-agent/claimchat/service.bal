import ballerina/http;

// WSO2 Agent Manager deployment contract: a plain HTTP endpoint on port 8000
// speaking the standard chat interface below, rather than ai:ChatReqMessage /
// ai:ChatRespMessage's sessionId/message shape. "context" is accepted as
// opaque JSON and is not currently forwarded into the agent run - the claims
// tools reach all the state they need (claim, policy, coverage) themselves.
type AgentManagerChatRequest record {|
    string message;
    string session_id;
    json context;
|};

type AgentManagerChatResponse record {|
    string response;
|};

listener http:Listener claimsChatHttpListener = check new (8000);

service /chat on claimsChatHttpListener {
    resource function post .(@http:Payload AgentManagerChatRequest request) returns AgentManagerChatResponse|error {
        string stringResult = check claimsChatAgent.run(request.message, request.session_id);
        return {response: stringResult};
    }
}
