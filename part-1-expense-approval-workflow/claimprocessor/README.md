# ClaimProcessor Project

`ClaimProcessor` is a WSO2 Integrator project — a Ballerina workspace ([`Ballerina.toml`](./Ballerina.toml)) containing two independent integrations. Both implement the same insurance expense-claim approval policy for Amani General Insurance, but take a different approach to building it. They expose the same REST contract and register under the same workflow type name, so either one can back the [web UI](../webui) unchanged.

The project has two integrations which are used to approve claim requests:

1. [`approvalworkflow`](./approvalworkflow) — **Durable Workflow**: the approval logic is written as explicit, code-first workflow and activity functions (`@workflow:Workflow`, `@workflow:Activity`). Control flow — validate, auto-approve or await a manager's decision, then reimburse — is defined directly in code.
2. [`approvalagent`](./approvalagent) — **Durable Agent**: the same policy is instead described to an LLM-backed `workflow:DurableAgent` as a system prompt, with `validateClaim`, `reimburse`, and the `approveExpense` human task exposed to it as tools. The agent decides at runtime which tool to call for a given claim.

Both integrations are durable — their execution state (including any claim paused on a pending manager decision) is persisted on Temporal and survives process restarts.

Run only one integration at a time, since both default to the same HTTP ports (`9090` for the `/expenses` API, `8234` for the workflow management API). See the [part 1 README](../README.md) for full setup and run instructions.
