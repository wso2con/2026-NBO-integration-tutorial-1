const EXPENSES_API = 'http://localhost:9090/expenses'
const MANAGEMENT_API = 'http://localhost:8234/workflow'
// Both ../backend's plain workflow and ../agent's durable agent are named
// `expenseApproval`, so they register under the same Temporal workflow type.
const CLAIM_WORKFLOW_TYPE = 'expenseApproval'

// The workflow module filters human tasks by role and records who completed
// them from these headers - it does not authenticate the caller. In a real
// app a backend or gateway would set these from the logged-in user; here they
// come straight from the hardcoded demo login.
function identityHeaders(user) {
  return { 'x-user-roles': user.role, 'x-user-id': user.id }
}

async function requestJson(url, options = {}) {
  const response = await fetch(url, {
    ...options,
    headers: { 'Content-Type': 'application/json', ...(options.headers || {}) },
  })
  const data = await response.json().catch(() => null)
  if (!response.ok) {
    throw new Error(data?.error?.message || data?.message || `Request failed with status ${response.status}`)
  }
  return data
}

export function submitExpense(payload) {
  return requestJson(EXPENSES_API, { method: 'POST', body: JSON.stringify(payload) })
}

export function getExpenseStatus(workflowId) {
  return requestJson(`${EXPENSES_API}/${encodeURIComponent(workflowId)}`)
}

export async function listPendingApprovals(manager) {
  const headers = identityHeaders(manager)
  const list = await requestJson(`${MANAGEMENT_API}/human-tasks?status=PENDING`, { headers })
  const items = list.items || []
  return Promise.all(
    items.map((item) => requestJson(`${MANAGEMENT_API}/human-tasks/${encodeURIComponent(item.taskId)}`, { headers })),
  )
}

export function completeApproval(manager, taskId, approved, comment) {
  return requestJson(`${MANAGEMENT_API}/human-tasks/${encodeURIComponent(taskId)}/complete`, {
    method: 'POST',
    headers: identityHeaders(manager),
    body: JSON.stringify({ result: { approved, comment } }),
  })
}

// The claim's own fields (userId, userName, amount, currency, category,
// description) only exist in Temporal's workflow history - the business
// service never stores them anywhere else - so reading them back means
// decoding the JSON payload recorded on the workflow's start event.
function decodeStartInput(events) {
  try {
    const started = (events || []).find((e) => e.eventType === 'WORKFLOW_EXECUTION_STARTED')
    const payloads = started?.attributes?.input?.payloads || []
    const decoded = payloads.map((p) => JSON.parse(atob(p.data)))
    if (decoded.length !== 1) return null
    let value = decoded[0]
    // A DurableAgent (../agent) wraps its start input as {input, query, agentName},
    // where `query` is the claim JSON re-encoded as a string - unwrap it. The
    // plain workflow (../backend) records the claim object directly, so this
    // is a no-op there.
    if (value && typeof value === 'object' && typeof value.query === 'string') {
      try {
        value = JSON.parse(value.query)
      } catch {
        // leave as-is if query isn't JSON
      }
    }
    return value
  } catch {
    return null
  }
}

// Lists every claim workflow instance from the management API - this is the
// real source of truth, unlike a per-tab list of "claims I happened to submit
// in this browser session". A customer sees their own claims; a manager sees
// everyone's.
export async function listAllClaims(user) {
  const headers = identityHeaders(user)
  const list = await requestJson(`${MANAGEMENT_API}/workflows?limit=50`, { headers })
  const items = (list.items || []).filter((w) => w.workflowType === CLAIM_WORKFLOW_TYPE)

  const claims = await Promise.all(
    items.map(async (w) => {
      const history = await requestJson(`${MANAGEMENT_API}/workflows/${encodeURIComponent(w.workflowId)}/history`, {
        headers,
      })
      const submitted = decodeStartInput(history.events) || {}
      let result = null
      if (w.status === 'COMPLETED') {
        const info = await getExpenseStatus(w.workflowId).catch(() => null)
        result = info?.result || null
      }
      return {
        workflowId: w.workflowId,
        userId: submitted.userId,
        userName: submitted.userName,
        amount: submitted.amount,
        currency: submitted.currency,
        category: submitted.category,
        description: submitted.description,
        status: w.status,
        result,
      }
    }),
  )

  return claims.sort((a, b) => (a.workflowId < b.workflowId ? 1 : -1))
}
