const configuredServerUrl = (
  import.meta.env.VITE_UPORTAL_DEFAULT_SERVER_URL ||
  '__UPORTAL_BASE_URL__'
).replace(/\/+$/, '')

export const DEFAULT_SERVER_URL = configuredServerUrl.includes('__UPORTAL_')
  ? 'http://localhost:8080'
  : configuredServerUrl

export const LEGACY_DEFAULT_SERVER_URLS = [
  'https://example.com',
  '__UPORTAL_BASE_URL__'
]

export function normalizeServerUrl(value) {
  const serverUrl = String(value || '').trim().replace(/\/+$/, '')
  return !serverUrl || LEGACY_DEFAULT_SERVER_URLS.includes(serverUrl)
    ? DEFAULT_SERVER_URL
    : serverUrl
}
