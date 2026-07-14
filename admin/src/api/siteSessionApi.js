function normalizeBaseUrl(value) {
  return String(value || '').trim().replace(/\/+$/, '')
}

function sameOriginBaseUrl() {
  if (typeof window === 'undefined') return ''
  return window.location.origin.replace(/\/+$/, '')
}

export function siteSessionProbeCandidates(serverUrl) {
  const candidates = [
    sameOriginBaseUrl(),
    normalizeBaseUrl(serverUrl)
  ].filter(Boolean)

  return [...new Set(candidates)]
}

export async function fetchSiteSession(baseUrl) {
  const response = await fetch(`${normalizeBaseUrl(baseUrl)}/api/site/session`, {
    method: 'GET',
    headers: {
      Accept: 'application/json'
    },
    credentials: 'include'
  })

  const contentType = response.headers.get('content-type') || ''
  if (!contentType.includes('application/json')) {
    throw new Error('site-backend did not return JSON')
  }

  const data = await response.json()
  if (data?.status !== 'success' || !data?.data) {
    throw new Error('site-backend session response is invalid')
  }

  return data.data
}

export async function loginSiteSession(baseUrl, token) {
  const response = await fetch(`${normalizeBaseUrl(baseUrl)}/api/site/token/login`, {
    method: 'POST',
    headers: {
      Accept: 'application/json',
      'Content-Type': 'application/json'
    },
    credentials: 'include',
    body: JSON.stringify({ token })
  })

  const data = await response.json().catch(() => null)
  if (!response.ok || data?.status !== 'success') {
    const message = data?.error?.message || `site-backend login failed: ${response.status}`
    throw new Error(message)
  }

  return fetchSiteSession(baseUrl)
}

export async function logoutSiteSession(baseUrl) {
  await fetch(`${normalizeBaseUrl(baseUrl)}/api/site/token/logout`, {
    method: 'POST',
    headers: {
      Accept: 'application/json'
    },
    credentials: 'include'
  }).catch(() => null)
}
