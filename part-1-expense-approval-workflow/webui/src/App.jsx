import { useEffect, useState, useCallback } from 'react'
import { submitExpense, listAllClaims, listPendingApprovals, completeApproval } from './api.js'
import { findUser, loadStoredUser, storeUser, clearStoredUser } from './users.js'

const STATUS_LABEL = {
  SUBMITTED: 'Submitted',
  RUNNING: 'Awaiting approval',
  COMPLETED: 'Completed',
  FAILED: 'Failed',
}

function StatusBadge({ status }) {
  return <span className={`badge badge-${status}`}>{STATUS_LABEL[status] || status}</span>
}

function Logo() {
  return (
    <svg className="logo" width="30" height="30" viewBox="0 0 24 24" aria-hidden="true">
      <path fill="#1f6feb" d="M12 1L3 5v6c0 5.55 3.84 10.74 9 12 5.16-1.26 9-6.45 9-12V5l-9-4z" />
      <path fill="#ffffff" d="M10.4 14.6 7.8 12l1.1-1.1 1.5 1.5 4.3-4.3L15.8 9.2z" />
    </svg>
  )
}

function LoginScreen({ onLogin }) {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState(null)

  function handleSubmit(event) {
    event.preventDefault()
    const match = findUser(email, password)
    if (!match) {
      setError('Invalid username or password')
      return
    }
    setError(null)
    onLogin(match)
  }

  return (
    <div className="app">
      <header className="app-header">
        <div className="brand">
          <Logo />
          <h1>Acme Insurance — Claims Portal</h1>
        </div>
        <p className="muted">Sign in to continue.</p>
      </header>
      <div className="panel login-panel">
        <form className="form login-form" onSubmit={handleSubmit}>
          <label className="full-width">
            Email
            <input
              required
              type="email"
              autoComplete="username"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="you@example.com"
            />
          </label>
          <label className="full-width">
            Password
            <input
              required
              type="password"
              autoComplete="current-password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
            />
          </label>
          <button type="submit">Log in</button>
        </form>
        {error && <p className="error">{error}</p>}
      </div>
    </div>
  )
}

const CLAIM_CATEGORIES = ['Motor', 'Health', 'Travel', 'Property', 'Dental', 'Life', 'Other']

const EMPTY_SUBMIT_FORM = { amount: '', currency: 'USD', category: '', customCategory: '', description: '' }

function SubmitTab({ user, onSubmitted }) {
  const [form, setForm] = useState(EMPTY_SUBMIT_FORM)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState(null)

  function updateField(field, value) {
    setForm((current) => ({ ...current, [field]: value }))
  }

  async function handleSubmit(event) {
    event.preventDefault()
    setBusy(true)
    setError(null)
    try {
      const { customCategory, ...rest } = form
      const submission = {
        claimId: crypto.randomUUID(),
        userId: user.id,
        userName: user.name,
        ...rest,
        category: form.category === 'Other' ? form.customCategory : form.category,
        amount: Number(form.amount),
      }
      await submitExpense(submission)
      onSubmitted()
      setForm(EMPTY_SUBMIT_FORM)
    } catch (submitError) {
      setError(submitError.message)
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="panel">
      <h2>Submit an insurance claim</h2>
      <p className="muted small">
        Submitting as <strong>{user.name}</strong> ({user.email})
      </p>
      <form className="form" onSubmit={handleSubmit}>
        <label>
          Amount
          <input
            required
            type="number"
            min="0.01"
            step="0.01"
            value={form.amount}
            onChange={(e) => updateField('amount', e.target.value)}
          />
        </label>
        <label>
          Currency
          <input required value={form.currency} onChange={(e) => updateField('currency', e.target.value)} />
        </label>
        <label>
          Category
          <select required value={form.category} onChange={(e) => updateField('category', e.target.value)}>
            <option value="" disabled>
              Select a category…
            </option>
            {CLAIM_CATEGORIES.map((option) => (
              <option key={option} value={option}>
                {option}
              </option>
            ))}
          </select>
        </label>
        {form.category === 'Other' && (
          <label>
            Specify category
            <input
              required
              value={form.customCategory}
              onChange={(e) => updateField('customCategory', e.target.value)}
            />
          </label>
        )}
        <label className="full-width">
          Description
          <textarea required value={form.description} onChange={(e) => updateField('description', e.target.value)} />
        </label>
        <button type="submit" disabled={busy}>
          {busy ? 'Submitting…' : 'Submit claim'}
        </button>
      </form>
      {error && <p className="error">{error}</p>}
      <p className="muted small">
        Your claim is submitted for processing right away. Track its progress in the <strong>Track claims</strong>{' '}
        tab.
      </p>
    </div>
  )
}

function TrackTab({ claims, error }) {
  return (
    <div className="panel">
      <h2>Track claims ({claims.length})</h2>
      {error && <p className="error">Could not reach the workflow management API at localhost:8234 — {error}</p>}
      {!error && claims.length === 0 && <p className="muted">No claims to show yet.</p>}
      <div className="task-list">
        {claims.map((claim) => (
          <div className="task-card" key={claim.workflowId}>
            <div className="task-card-header">
              <strong>{claim.userName || 'Unknown'}</strong>
              <span>
                {(claim.amount ?? 0).toFixed(2)} {claim.currency}
              </span>
            </div>
            <p className="muted">
              {claim.category} · {claim.description}
            </p>
            <p className="muted small">Workflow ID: {claim.workflowId}</p>
            <StatusBadge status={claim.status} />
            {claim.result && <p className="result-text">{claim.result}</p>}
          </div>
        ))}
      </div>
    </div>
  )
}

function ApprovalsTab({ manager, tasks, onDecided, error }) {
  const [drafts, setDrafts] = useState({})
  const [busyId, setBusyId] = useState(null)
  const [decisionError, setDecisionError] = useState(null)

  function draftFor(taskId) {
    return drafts[taskId] || ''
  }

  async function decide(task, approved) {
    setBusyId(task.taskId)
    setDecisionError(null)
    try {
      await completeApproval(manager, task.taskId, approved, draftFor(task.taskId))
      onDecided()
    } catch (err) {
      setDecisionError(err.message)
    } finally {
      setBusyId(null)
    }
  }

  return (
    <div className="panel">
      <h2>Approvals inbox ({tasks.length})</h2>
      <p className="muted small">
        Signed in as <strong>{manager.name}</strong> — decisions are recorded under user id{' '}
        <code>{manager.id}</code>.
      </p>
      {error && <p className="error">Could not reach the workflow management API at localhost:8234 — {error}</p>}
      {decisionError && <p className="error">{decisionError}</p>}
      {!error && tasks.length === 0 && <p className="muted">No claims are waiting on a manager decision.</p>}
      <div className="task-list">
        {tasks.map((task) => {
          const payload = task.payload || {}
          return (
            <div className="task-card" key={task.taskId}>
              <div className="task-card-header">
                <strong>{payload.userName}</strong>
                <span>
                  {payload.amount} {payload.currency}
                </span>
              </div>
              <p className="muted">
                {payload.category} · {payload.description}
              </p>
              <p className="muted small">{task.description}</p>
              <div className="decision-row">
                <input
                  placeholder="Comment (optional)"
                  value={draftFor(task.taskId)}
                  onChange={(e) => setDrafts((current) => ({ ...current, [task.taskId]: e.target.value }))}
                />
              </div>
              <div className="decision-buttons">
                <button className="approve" disabled={busyId === task.taskId} onClick={() => decide(task, true)}>
                  Approve
                </button>
                <button className="reject" disabled={busyId === task.taskId} onClick={() => decide(task, false)}>
                  Reject
                </button>
              </div>
            </div>
          )
        })}
      </div>
    </div>
  )
}

export default function App() {
  const [user, setUser] = useState(() => loadStoredUser())
  const [tab, setTab] = useState(() => {
    const stored = loadStoredUser()
    return stored ? (stored.role === 'MANAGER' ? 'approvals' : 'submit') : null
  })
  const [claims, setClaims] = useState([])
  const [claimsError, setClaimsError] = useState(null)
  const [pendingTasks, setPendingTasks] = useState([])
  const [approvalsError, setApprovalsError] = useState(null)

  function handleLogin(selectedUser) {
    storeUser(selectedUser)
    setUser(selectedUser)
    setTab(selectedUser.role === 'MANAGER' ? 'approvals' : 'submit')
  }

  function handleLogout() {
    clearStoredUser()
    setUser(null)
    setTab(null)
    setClaims([])
    setPendingTasks([])
  }

  const refreshApprovals = useCallback(async () => {
    if (!user || user.role !== 'MANAGER') return
    try {
      const tasks = await listPendingApprovals(user)
      setPendingTasks(tasks)
      setApprovalsError(null)
    } catch (err) {
      setApprovalsError(err.message)
    }
  }, [user])

  // The source of truth is the workflow management API, not anything tracked
  // locally - so a manager who just logged in still sees every claim, not
  // just ones submitted from this browser tab.
  const refreshClaims = useCallback(async () => {
    if (!user) return
    try {
      const allClaims = await listAllClaims(user)
      setClaims(user.role === 'MANAGER' ? allClaims : allClaims.filter((c) => c.userId === user.id))
      setClaimsError(null)
    } catch (err) {
      setClaimsError(err.message)
    }
  }, [user])

  useEffect(() => {
    if (!user) return
    refreshApprovals()
    refreshClaims()
    const interval = setInterval(() => {
      refreshApprovals()
      refreshClaims()
    }, 4000)
    return () => clearInterval(interval)
  }, [user, refreshApprovals, refreshClaims])

  if (!user) {
    return <LoginScreen onLogin={handleLogin} />
  }

  const isManager = user.role === 'MANAGER'

  return (
    <div className="app">
      <header className="app-header app-header-row">
        <div>
          <div className="brand">
            <Logo />
            <h1>Acme Insurance — Claims Portal</h1>
          </div>
          <p className="muted">
            Claims at or below the auto-approve threshold are reimbursed immediately. Larger claims are routed to a
            manager for review before being settled.
          </p>
        </div>
        <div className="user-chip">
          <span>
            {user.name} <span className={`badge role-badge role-badge-${user.role}`}>{user.role}</span>
          </span>
          <button className="logout" onClick={handleLogout}>
            Log out
          </button>
        </div>
      </header>

      <nav className="tabs">
        {!isManager && (
          <button className={tab === 'submit' ? 'active' : ''} onClick={() => setTab('submit')}>
            Submit
          </button>
        )}
        {isManager && (
          <button className={tab === 'approvals' ? 'active' : ''} onClick={() => setTab('approvals')}>
            Approvals{pendingTasks.length > 0 ? ` (${pendingTasks.length})` : ''}
          </button>
        )}
        <button className={tab === 'track' ? 'active' : ''} onClick={() => setTab('track')}>
          Track claims
        </button>
      </nav>

      {tab === 'submit' && !isManager && <SubmitTab user={user} onSubmitted={refreshClaims} />}
      {tab === 'approvals' && isManager && (
        <ApprovalsTab
          manager={user}
          tasks={pendingTasks}
          onDecided={() => {
            refreshApprovals()
            refreshClaims()
          }}
          error={approvalsError}
        />
      )}
      {tab === 'track' && <TrackTab claims={claims} error={claimsError} />}
    </div>
  )
}
