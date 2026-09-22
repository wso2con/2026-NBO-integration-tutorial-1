// RAG retrieval over Amani's company knowledge base (company information,
// claims process, policy wording), served by the rag-service-api on Choreo.
//
// All settings are simple-typed configurables, so Agent Manager can supply them
// at deploy time as BAL_CONFIG_VAR_<NAME IN UPPERCASE>, e.g.
// BAL_CONFIG_VAR_RAGSERVICEURL / BAL_CONFIG_VAR_RAGAPIKEY.

import ballerina/ai;
import ballerina/http;
import ballerina/mime;

configurable string ragServiceUrl = "https://b48cc93e-fa33-4420-a155-bc653b4d46be-my-env.e1-us-east-azure.choreoapis.dev/lashan-wso2con-prep/rag-service-api/rag-api-service-fc3/1.0.0";
// "Test-Key" for a Choreo console test key; "api-key" for a subscription API key.
configurable string ragApiKeyHeader = "Test-Key";
configurable string ragApiKey = ?;

configurable string ragEmbeddingModelProvider = "openai";
configurable string ragEmbeddingModel = "text-embedding-3-small";
// Left empty, the chat model's openAiApiKey is used for embeddings too.
configurable string ragEmbeddingModelApiKey = "";

configurable string ragVectorDbProvider = "pinecone";
configurable string ragCollectionName = "integration-lab-pinecone-index";
configurable string ragPineconeApiKey = ?;

configurable int ragMaxRetrieveChunks = 2;
configurable decimal ragMinSimilarityThreshold = 0.2;
configurable int ragRerankerTopN = 5;

final http:Client ragClient = check new (ragServiceUrl, {timeout: 60});

type RetrievedChunk record {
    string text;
    string 'source?;
};

type RetrieveResponse record {
    RetrievedChunk[] retrieved_chunks;
};

# Searches Amani General Insurance's knowledge base - company information, the
# claims process and its timelines, and policy wording - for passages relevant
# to the query. Use it for general questions about Amani or its processes that
# are not about a specific claim.
#
# + query - A natural-language question, e.g. "How long does a claim payout take?"
# + return - The most relevant passages, each with the document it came from
@ai:AgentTool
isolated function searchAmaniKnowledgeBase(string query) returns RetrievedChunk[]|error {
    map<string> form = {
        user_query: query,
        embedding_model_provider: ragEmbeddingModelProvider,
        embedding_model: ragEmbeddingModel,
        embedding_model_apikey: ragEmbeddingModelApiKey == "" ? openAiApiKey : ragEmbeddingModelApiKey,
        vectordb_provider: ragVectorDbProvider,
        collection_name: ragCollectionName,
        pinecone_apikey: ragPineconeApiKey,
        max_retrieve_chunks: ragMaxRetrieveChunks.toString(),
        min_similarity_threshold: ragMinSimilarityThreshold.toString(),
        reranker_top_n: ragRerankerTopN.toString()
    };
    RetrieveResponse response = check ragClient->post("/retrieve", form,
        {[ragApiKeyHeader]: ragApiKey, "accept": "application/json"}, mime:APPLICATION_FORM_URLENCODED);
    return response.retrieved_chunks;
}
