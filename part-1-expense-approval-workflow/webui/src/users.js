// Hardcoded demo directory — stands in for a real IAM/SSO integration.
// The password is checked client-side, in plaintext, against this list.
// Fine for a demo with no external identity provider; never do this in a
// real app (passwords belong behind a real auth service, hashed, server-side).
// One shape for both roles: id, name, email, role. `id` doubles as the claim
// owner's userId when a customer submits, and as the approver's x-user-id
// when a manager completes a task — no role-specific fields needed.
export const DEMO_USERS = [
  { id: 'chris', name: 'Chris', email: 'chris@gmail.com', password: 'chris@123', role: 'CUSTOMER' },
  { id: 'matt', name: 'Matt', email: 'matt@acme.com', password: 'matt@123', role: 'MANAGER' },
]

const STORAGE_KEY = 'expense-workflow-demo-user'

export function findUser(email, password) {
  const normalizedEmail = email.trim().toLowerCase()
  return DEMO_USERS.find((u) => u.email.toLowerCase() === normalizedEmail && u.password === password) || null
}

export function loadStoredUser() {
  try {
    const raw = sessionStorage.getItem(STORAGE_KEY)
    if (!raw) return null
    const userId = JSON.parse(raw)?.id
    return DEMO_USERS.find((u) => u.id === userId) || null
  } catch {
    return null
  }
}

export function storeUser(user) {
  try {
    sessionStorage.setItem(STORAGE_KEY, JSON.stringify({ id: user.id }))
  } catch {
    // ignore - falls back to in-memory state only
  }
}

export function clearStoredUser() {
  try {
    sessionStorage.removeItem(STORAGE_KEY)
  } catch {
    // ignore
  }
}
