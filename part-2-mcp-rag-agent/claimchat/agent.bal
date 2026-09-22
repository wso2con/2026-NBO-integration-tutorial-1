// Amani General Insurance - Claims Chat Agent.
//
// A conversational agent fronting the Amani-Insurance-Claim-MCP-Tools (claimtools)
// toolset: getClaimAssessment, getCustomerProfile, requestMissingDocuments,
// recordDocumentsReceived, decideClaim, escalateToAdjuster, and settleClaim.

import ballerina/ai;
import ballerinax/ai.openai;
import ballerinax/amp as _;

configurable string claimsToolsServerUrl = "http://localhost:9091/mcp";

// The model is OpenAI reached with a plain API key, rather than the WSO2
// provider: Agent Manager's egress gateway expects an OAuth2 client-credentials
// token (AMP_AGENTID_*), which ai:Wso2ModelProvider has no way to obtain since
// init() accepts only a static access token.
//
// All three settings are simple-typed configurables, so Agent Manager can
// supply them at deploy time as BAL_CONFIG_VAR_OPENAIAPIKEY /
// BAL_CONFIG_VAR_OPENAIMODEL / BAL_CONFIG_VAR_OPENAISERVICEURL.
configurable string openAiApiKey = ?;
configurable openai:OPEN_AI_MODEL_NAMES openAiModel = openai:GPT_4O_MINI;
configurable string openAiServiceUrl = "https://api.openai.com/v1";

final openai:ModelProvider claimsChatModel = check new (openAiApiKey, openAiModel, openAiServiceUrl);

final ai:McpToolKit claimsToolKit = check new (claimsToolsServerUrl);

final ai:Agent claimsChatAgent = check new (
    systemPrompt = {
        role: string `Amani General Insurance Claims Assistant`,
        instructions: string `You help handle household insurance claims for Amani General Insurance.
Call getClaimAssessment first for any claim you are asked about; it returns the claim, the policy,
the coverage finding, the claimant's history, and any blockers in one call.
Call getCustomerProfile before deciding or escalating to see the claimant's other claims, open and closed.
Tools refuse with a status of REFUSED and a remedy rather than failing - read the remedy and follow it.
Never decide a claim that still has outstanding documents.
Always explain your reasoning and cite the coverage basis or policy clause when you approve, reject, or escalate a claim.
For general questions about Amani - the company, the claims process and its timelines, or policy wording -
call searchAmaniKnowledgeBase and answer from the passages it returns, naming the source document.`
    },
    model = claimsChatModel,
    tools = [claimsToolKit, searchAmaniKnowledgeBase]
);
