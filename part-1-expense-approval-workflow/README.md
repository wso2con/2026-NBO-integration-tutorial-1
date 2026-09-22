# Part 1 - Expense Approval Workflow

This tutorial shows how to build a durable, human-in-the-loop business process with WSO2 Integrator's workflow capabilities, using an insurance expense-claim approval scenario for **Amani General Insurance**.

## Scenario

A customer submits an insurance expense claim (amount, currency, category, description). The claim is validated automatically:

- If the claim amount is **at or below $500**, it is **auto-approved** and reimbursed immediately.
- If the claim amount is **above $500**, the process pauses and waits for a **manager to review and approve or reject** it. Once the manager decides, the process resumes — approving triggers reimbursement, rejecting ends the claim with the manager's comment.

Because this is a *durable* process, the workflow/agent state survives restarts — a claim waiting on a manager's decision can sit for hours or days and will resume exactly where it left off once a decision is made.

## Components

| Component | Description |
|---|---|
| [`webui`](./webui) | A React + Vite single-page app — the claims portal used by customers and managers. |
| [`claimprocessor`](./claimprocessor) | A Ballerina workspace containing two alternative backend integrations that implement the *same* claim approval policy. |
| [`claimprocessor/approvalworkflow`](./claimprocessor/approvalworkflow) | Integration 1 — a **durable workflow** built with explicit workflow/activity code. |
| [`claimprocessor/approvalagent`](./claimprocessor/approvalagent) | Integration 2 — a **durable agent** that implements the same policy conversationally, driven by an LLM with tools. |

Both integrations expose the same REST contract (`POST /expenses`, `GET /expenses/{workflowId}`) and register under the same workflow type name (`expenseApproval`), so the web UI works against either one unchanged. They are two different implementation approaches to the same problem, not two stages of one pipeline — run one at a time.

### Integration 1: Durable Workflow (`approvalworkflow`)

1. `validateClaim` activity — rejects claims with a non-positive amount.
2. If `amount > 500`, awaits a human task (`approveExpense`) restricted to users with the `MANAGER` role.
3. `reimburse` activity — issues a reimbursement reference once approved (or auto-approved).

### Integration 2: Durable Agent (`approvalagent`)

The same policy, but implemented as a conversational `workflow:DurableAgent` (`workflow.bal`) backed by an LLM (via WSO2's default model provider). Instead of hardcoded control flow, the agent is given a system prompt describing the policy plus three tools — `validateClaim`, `reimburse`, and the `approveExpense` human task — and decides at runtime which to call, based on the claim it receives.

## Who uses the system

Two demo users are hardcoded in the web UI ([`webui/src/users.js`](./webui/src/users.js)) — there's no real identity provider, just a stand-in login:

| User | Email | Role | Can do |
|---|---|---|---|
| Chris | chris@gmail.com / chris@123 | `CUSTOMER` | Submit new claims, track the status of their own claims. |
| Matt | matt@amani.com / matt@123 | `MANAGER` | Review and approve/reject claims routed to the approvals inbox, track *all* claims. |

## Running the tutorial

### Prerequisites

- WSO2 Integrator — see the [root README](../README.md) for setup.
- [Temporal CLI](https://docs.temporal.io/cli) — durable workflows/agents run on Temporal under the hood.
- Node.js and npm (for the web UI).

### 1. Start the local Temporal server

```bash
temporal server start-dev
```

This starts a local Temporal server (and its Web UI, typically at `http://localhost:8233`), which both integrations rely on to durably orchestrate the claim approval process. Leave it running for the rest of this tutorial.

### 2. Run the web UI

```bash
cd webui
npm install
npm run dev
```

Open the printed local URL (typically `http://localhost:5173`) in a browser.

### 3. Run one of the backend integrations

Open the `claimprocessor` workspace in WSO2 Integrator / VS Code and run **either**:

- `approvalworkflow` — the durable workflow, **or**
- `approvalagent` — the durable agent (requires the WSO2 model provider access token configured in `approvalagent/Config.toml`).

This starts:
- The `/expenses` REST API on `http://localhost:9090`.
- The workflow management API on `http://localhost:8234` (used by the UI to list claims and human tasks).

> Run only one integration at a time — both bind the same default ports.

### 4. Try it out

1. Log in as **Chris** (customer) and submit a claim.
   - A claim of **$500 or less** is reimbursed immediately — check the **Track claims** tab.
   - A claim **over $500** shows as *Awaiting approval*.
2. Log out and log in as **Matt** (manager).
3. Open the **Approvals** tab, review the pending claim, and **Approve** or **Reject** it (optionally with a comment).
4. Log back in as Chris and confirm the claim in **Track claims** now shows the final outcome.

### 5. Inspect it in ICP

Enable ICP for the running integration and start it. ICP opens at [`https://localhost:9446/`](https://localhost:9446/) — log in with `admin` / `admin`. From there you can see the workflow execution details and the human tasks created during the approval process.
