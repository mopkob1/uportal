import axios from 'axios'
import store, { normalizeServerUrl } from '../store'
import { getDraftAsset } from '../services/draftAssetStore'

const api = axios.create({
  timeout: 30000
})

const UPLOAD_TIMEOUT_MS = 10 * 60 * 1000

api.interceptors.request.use((config) => {
  const serverUrl = normalizeServerUrl(store.state.serverUrl)
  const authHeader = store.state.authHeader || 'X-User-Token'
  const authToken = store.state.token || ''
  const adminAuth = config.uportalAdminAuth

  config.baseURL = serverUrl
  config.headers = config.headers || {}

  if (adminAuth?.token) {
    config.headers[adminAuth.header || 'X-Admin-Key'] = adminAuth.token

    if (store.state.authMode === 'site-session') {
      config.withCredentials = true
      config.url = toSiteRuntimeProxyPath(config.url || '')
    }

    return config
  }

  if (store.state.authMode === 'site-session') {
    config.withCredentials = true
    config.url = toSiteRuntimeProxyPath(config.url || '')
    if (store.state.clientUid) {
      config.headers['X-UPortal-Client-Uid'] = store.state.clientUid
      config.headers['X-UPortal-Client-Type'] = 'web'
    }
    return config
  }

  if (authToken) {
    config.headers[authHeader] = authToken
    if (store.state.clientUid) {
      config.headers['X-UPortal-Client-Uid'] = store.state.clientUid
      config.headers['X-UPortal-Client-Type'] = 'web'
    }
  }

  return config
})

function toSiteRuntimeProxyPath(url) {
  const value = String(url || '')
  if (value.startsWith('/api/site/runtime/')) return value
  if (value.startsWith('/api/admin/')) return `/api/site/runtime${value}`
  return value
}

function withAdminAuth(adminHeader, adminToken, config = {}) {
  return {
    ...config,
    uportalAdminAuth: {
      header: adminHeader || 'X-Admin-Key',
      token: adminToken || ''
    }
  }
}

export async function linksList(filters = {}) {
  const { data } = await api.post('/api/admin/links/list', filters)
  return data
}

export async function publishDraftRequest(draft) {
  const payload = buildPublishPayload(draft)
  validatePublishPayload(payload)
  const uploads = await collectDraftUploads(draft)

  if (
    store.state.authMode === 'site-session' &&
    store.state.siteBackendAvailable &&
    uploads.length &&
    ['page', 'download'].includes(payload.type)
  ) {
    const data = await publishDraftWithBlobWorkflow(payload, uploads)
    assertSuccessResponse(data)
    return data
  }

  await uploadDraftAssets(draft, uploads)
  const { data } = await api.post(`/api/admin/publish/${payload.type}`, payload)
  assertSuccessResponse(data)
  return data
}

function assertSuccessResponse(data) {
  if (data?.status !== 'error') return

  const text = errorText(data?.message?.[0]?.text) ||
      errorText(data?.message) ||
      errorText(data?.error) ||
      'publish failed'

  throw new Error(text)
}

async function uploadDraftAssets(draft, knownUploads = null) {
  const uniqueUploads = knownUploads || await collectDraftUploads(draft)
  const [firstUpload, ...remainingUploads] = uniqueUploads
  if (!firstUpload) return

  if (store.state.authMode === 'site-session' && store.state.siteBackendAvailable) {
    await uploadPublicationFilesWithGrant(draft.publication_id, draft.token, uniqueUploads)
    return
  }

  await uploadPublicationFile(draft.publication_id, draft.token, firstUpload.name, firstUpload.file)

  await Promise.all(
    remainingUploads.map(({ name, file }) =>
      uploadPublicationFile(draft.publication_id, draft.token, name, file)
    )
  )
}

async function collectDraftUploads(draft) {
  const uploads = []

  if (draft.publication_id && draft.token && draft.image) {
    const imageDataUrl = draft.imageDataUrl || await getDraftAsset(draft.imageDataKey)
    const imageFile = draft.imageFile || dataUrlToFile(imageDataUrl, draft.image)

    if (imageFile) {
      uploads.push({
        name: draft.image,
        file: imageFile
      })
    }
  }

  if (draft.publication_id && draft.token) {
    const sourceName = draft.fileName || draft.file?.name || draft.filename || draft.form?.filename || 'download.bin'
    const fileDataUrl = draft.fileDataUrl || await getDraftAsset(draft.fileDataKey)
    const file = draft.file || dataUrlToFile(fileDataUrl, sourceName)
    const name = draft.fileName || file?.name || ''

    if (file && name) {
      uploads.push({
        name,
        file
      })
    }
  }

  if (Array.isArray(draft.form?.files)) {
    const pageFiles = await Promise.all(
      draft.form.files.map(async (item) => {
        if (!draft.publication_id || !draft.token) return null

        const name = item?.name || item?.file?.name || ''
        const fileDataUrl = item?.fileDataUrl || await getDraftAsset(item?.fileDataKey)
        const file = item?.file instanceof File
            ? item.file
            : dataUrlToFile(fileDataUrl, name)

        return file && name ? { name, file } : null
      })
    )

    uploads.push(...pageFiles.filter(Boolean))
  }

  return Array.from(
    uploads.reduce((map, item) => map.set(item.name, item), new Map()).values()
  )
}

async function publishDraftWithBlobWorkflow(payload, uploads) {
  const files = await Promise.all(
    uploads.map(async ({ name, file }) => ({
      name,
      size: file.size,
      sha256: await sha256File(file),
      content_type: file.type || 'application/octet-stream',
      file
    }))
  )

  const { data: draftData } = await api.post('/api/site/publish/draft', {
    payload,
    files: files.map(({ name, size, sha256, content_type }) => ({
      name,
      size,
      sha256,
      content_type
    }))
  })

  const draftId = draftData?.data?.draft_id || draftData?.draft_id || ''
  if (!draftId) {
    throw new Error(errorText(draftData?.error) || 'publish draft was not created')
  }

  try {
    const missing = Array.isArray(draftData?.data?.missing) ? draftData.data.missing : []
    const missingHashes = new Set(missing.map((item) => item.sha256))
    await Promise.all(
      files
        .filter((item) => missingHashes.has(item.sha256))
        .map((item) => uploadBlobFile(draftId, item))
    )

    const { data } = await api.post(`/api/site/publish/draft/${encodeURIComponent(draftId)}/commit`)
    return data
  } catch (error) {
    await cancelPublishDraft(draftId, 'client_error').catch(() => {})
    throw error
  }
}

async function uploadPublicationFilesWithGrant(publicationId, token, uploads) {
  const grant = await createUploadGrant(publicationId, token, uploads)

  try {
    await Promise.all(
      uploads.map(({ name, file }) =>
        uploadPublicationFile(publicationId, token, name, file, grant.grant)
      )
    )
  } finally {
    await revokeUploadGrant(grant.grant).catch(() => {})
  }
}

async function sha256File(file) {
  const buffer = await file.arrayBuffer()
  const digest = await crypto.subtle.digest('SHA-256', buffer)
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('')
}

async function uploadBlobFile(draftId, item) {
  try {
    await api.put(`/api/site/blob/${item.sha256}`, item.file, {
      timeout: UPLOAD_TIMEOUT_MS,
      headers: {
        'Content-Type': 'application/octet-stream',
        'X-UPORTAL-Draft-Id': draftId
      }
    })
  } catch (error) {
    throw new Error(uploadErrorText(error, item.name))
  }
}

async function cancelPublishDraft(draftId, reason) {
  if (!draftId) return
  await api.post(`/api/site/publish/draft/${encodeURIComponent(draftId)}/cancel`, { reason })
}

function dataUrlToFile(dataUrl, filename) {
  if (!dataUrl || typeof dataUrl !== 'string' || !dataUrl.startsWith('data:')) return null

  const parts = dataUrl.split(',')
  if (parts.length < 2) return null

  const meta = parts[0]
  const base64 = parts.slice(1).join(',')
  const mimeMatch = meta.match(/^data:([^;]+);base64$/)
  const mime = mimeMatch?.[1] || 'application/octet-stream'

  try {
    const binary = atob(base64)
    const bytes = new Uint8Array(binary.length)

    for (let index = 0; index < binary.length; index += 1) {
      bytes[index] = binary.charCodeAt(index)
    }

    return new File([bytes], filename, { type: mime })
  } catch {
    return null
  }
}

async function createUploadGrant(publicationId, token, uploads) {
  const { data } = await api.post('/api/site/upload/grant', {
    publication_id: publicationId,
    token,
    files: uploads.map(({ name, file }) => ({
      name,
      size: file.size
    }))
  })

  const grant = data?.data?.grant || data?.grant || ''
  if (!grant) {
    throw new Error(errorText(data?.error) || 'upload grant was not issued')
  }

  return {
    grant,
    expiresAt: data?.data?.expires_at || ''
  }
}

async function revokeUploadGrant(grant) {
  if (!grant) return
  await api.post('/api/site/upload/grant/revoke', { grant })
}

async function uploadPublicationFile(publicationId, token, filename, file, uploadGrant = '') {
  try {
    const headers = {
      'Content-Type': file.type || 'application/octet-stream'
    }

    if (uploadGrant) {
      headers['X-UPORTAL-Upload-Grant'] = uploadGrant
    }

    await api.put(
      `/upload/${encodeURIComponent(publicationId)}/${encodeURIComponent(token)}/${encodeURIComponent(filename)}`,
      file,
      {
        timeout: UPLOAD_TIMEOUT_MS,
        headers
      }
    )
  } catch (error) {
    throw new Error(uploadErrorText(error, filename))
  }
}

function uploadErrorText(error, filename = '') {
  const headers = error?.response?.headers || {}
  const quotaCode = headerValue(headers, 'x-uportal-quota-error-code')
  const quotaStatus = headerValue(headers, 'x-uportal-quota-error-status')
  const responseText = errorText(error?.response?.data?.error) ||
      errorText(error?.response?.data?.message?.[0]?.text) ||
      errorText(error?.response?.data?.message) ||
      errorText(error?.response?.data)
  const quotaText = quotaMessage(quotaCode)
  const text = quotaText || responseText || error?.message || 'upload failed'
  const details = [
    filename ? `file: ${filename}` : '',
    quotaCode || '',
    quotaStatus ? `status: ${quotaStatus}` : ''
  ].filter(Boolean).join(', ')

  return details ? `${text} (${details})` : text
}

function headerValue(headers, name) {
  const target = name.toLowerCase()
  const entry = Object.entries(headers || {}).find(([key]) => key.toLowerCase() === target)
  return entry ? String(entry[1] || '') : ''
}

function errorText(value) {
  if (!value) return ''
  if (typeof value === 'string') return value
  if (Array.isArray(value)) {
    return value.map(errorText).filter(Boolean).join('; ')
  }
  if (typeof value === 'object') {
    return value.message || value.text || value.code || JSON.stringify(value)
  }
  return String(value)
}

function quotaMessage(code) {
  const messages = {
    storage_quota_exceeded: 'Storage quota exceeded',
    publication_quota_exceeded: 'Publication payload quota exceeded',
    publication_file_count_exceeded: 'Publication file count quota exceeded',
    file_too_large: 'File is larger than the tariff limit',
    content_length_required: 'Upload size is required',
    publication_owner_mismatch: 'Publication belongs to another account',
    session_required: 'Login is required',
    session_expired: 'Session token is inactive'
  }

  return messages[code] || ''
}

export async function activityList(filters = {}) {
  const { data } = await api.post('/api/admin/activity/list', filters)
  return data
}

export async function setFreshness(publicationId, token, freshUntil) {
  const { data } = await api.post('/api/admin/admin/set-freshness', {
    publication_id: publicationId,
    token,
    fresh_until: freshUntil || ''
  })
  return data
}

export async function setClicks(publicationId, token, remainingClicks) {
  const clicks = normalizeClicksLimit(remainingClicks)
  const { data } = await api.post('/api/admin/admin/set-clicks', {
    publication_id: publicationId,
    token,
    remaining_clicks: String(clicks)
  })
  return data
}

export async function setLinkStatus(publicationId, token, status) {
  const { data } = await api.post('/api/admin/admin/set-status', {
    publication_id: publicationId,
    token,
    status: status === 'hold' ? 'hold' : 'active'
  })
  return data
}

export async function setLinkSticky(publicationId, token, sticky) {
  const { data } = await api.post('/api/admin/admin/set-sticky', {
    publication_id: publicationId,
    token,
    sticky: sticky ? '1' : ''
  })
  return data
}

export async function setLinkTelegramNotify(publicationId, token, enabled) {
  const { data } = await api.post('/api/admin/admin/set-telegram-notify', {
    publication_id: publicationId,
    token,
    telegram_notify: enabled ? '1' : ''
  })
  return data
}

export async function setLinkDelay(publicationId, token, delay) {
  const { data } = await api.post('/api/admin/admin/set-delay', {
    publication_id: publicationId,
    token,
    delay: String(normalizeNonNegativeInteger(delay))
  })
  return data
}

export async function setLinkPassword(publicationId, token, password, passwordHint = '', passwordTtlSec = 1800) {
  const { data } = await api.post('/api/admin/admin/set-password', {
    publication_id: publicationId,
    token,
    password: password || '',
    password_hint: passwordHint || '',
    password_ttl_sec: String(passwordTtlSec || 1800)
  })
  return data
}

export async function dictionaryList() {
  const { data } = await api.get('/api/admin/dictionary')
  return data
}

export async function dictionaryUpsert(item) {
  const { data } = await api.post('/api/admin/dictionary', {
    id: item.id || '',
    pre: item.pre || '',
    post: item.post || '',
    url: item.url || '',
    anchor: item.anchor || '',
    type: item.type || 'redirect',
    tags: item.tags || ''
  })
  return data
}

export async function dictionaryDelete(id) {
  const { data } = await api.delete('/api/admin/dictionary', {
    data: { id }
  })
  return data
}

export async function tokensList(params = {}, adminHeader, adminToken) {
  const { data } = await api.get(
    '/api/admin/tokens',
    withAdminAuth(adminHeader, adminToken, { params })
  )
  return data
}

export async function tokenSelfGet() {
  const { data } = await api.get('/api/admin/tokens/self')
  return data
}

export async function tokenUpsert(item, adminHeader, adminToken) {
  const payload = {
    user: item.user || '',
    scope: item.scope || [],
    status: item.status || 'active',
    tags: item.tags || [],
    profile: item.profile || {},
    active_clients: {
      web: item.active_clients?.web || '',
      plugin: item.active_clients?.plugin || ''
    }
  }

  const payload_b64 = btoa(unescape(encodeURIComponent(JSON.stringify(payload))))

  const { data } = await api.post(
    '/api/admin/tokens',
    {
      token: item.token || '',
      payload_b64
    },
    withAdminAuth(adminHeader, adminToken)
  )

  return data
}

export async function tokenSelfUpsert(item) {
  const payload = {
    user: item.user || '',
    tags: item.tags || [],
    profile: item.profile || {},
    active_clients: {
      web: item.active_clients?.web || '',
      plugin: item.active_clients?.plugin || ''
    }
  }

  const payload_b64 = btoa(unescape(encodeURIComponent(JSON.stringify(payload))))
  const { data } = await api.post('/api/admin/tokens/self', { payload_b64 })
  return data
}

export async function tokenDelete(token, adminHeader, adminToken) {
  const { data } = await api.delete(
    '/api/admin/tokens',
    withAdminAuth(adminHeader, adminToken, {
      data: { token }
    })
  )

  return data
}

function buildPublishPayload(draft) {
  const type = draft.type || 'redirect'

  return {
    type,
    status: 'active',
    publication_id: draft.publication_id || '',
    token: draft.token || '',
    short: draft.short || '',
    subj: draft.subj || '',
    mails: Array.isArray(draft.mails) ? draft.mails : normalizeMails(draft.mails),
    link: normalizePublishLink(draft, type),
    pre: draft.pre || '',
    post: draft.post || '',
    target_url: draft.form?.target_url || draft.target_url || '',
    entry_md: draft.form?.entry_md || 'page.md',
    file: draft.fileName || draft.file?.name || draft.filename || draft.form?.filename || '',
    filename: draft.form?.filename || draft.filename || '',
    image: draft.image || '',
    title: draft.form?.title || draft.title || '',
    description: draft.form?.description || draft.description || '',
    delay: String(normalizeNonNegativeInteger(draft.form?.delay ?? draft.delay ?? 0)),
    template_set: normalizeTemplateSet(draft.form?.template_set ?? draft.template_set ?? draft.templateSet),
    fresh_until: normalizeLimit(draft.fresh_until),
    remaining_clicks: String(normalizeClicksLimit(draft.remaining_clicks)),
    fallback_url: draft.fallback_url || '',
    lang: normalizeTemplateLanguage(draft.lang),
    password: draft.form?.password || draft.password || '',
    password_hint: draft.form?.password_hint || draft.password_hint || '',
    sticky: draft.sticky ? '1' : ''
  }
}

function normalizePublishLink(draft, type) {
  const direct = draft.link || draft.form?.link || draft.form?.anchor || ''
  if (direct) return direct
  if (type === 'redirect') return draft.form?.target_url || draft.target_url || ''
  return ''
}

function validatePublishPayload(payload) {
  const required = ['publication_id', 'token', 'subj']
  if (payload.type !== 'pixel') required.push('link')
  if (payload.type === 'redirect') required.push('target_url')

  const missing = required.find(field => {
    const value = payload[field]
    return value === undefined || value === null || String(value).trim() === ''
  })

  if (missing) {
    throw new Error(`missing required field: ${missing}`)
  }
}

function normalizeNonNegativeInteger(value) {
  const numeric = Number(value)
  if (!Number.isFinite(numeric) || numeric < 0) return 0
  return Math.floor(numeric)
}

function normalizeLimit(value) {
  if (value === '' || value == null || value === -1 || value === '-1') return '-1'

  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return '-1'

  return date.toISOString()
}

function normalizeClicksLimit(value) {
  const number = Number(value)
  if (!Number.isFinite(number) || number < 0) return -1
  return Math.trunc(number)
}

function normalizeTemplateLanguage(value) {
  const lang = String(value || '').trim().toLowerCase().split('-')[0]
  if (lang === 'auto') return 'auto'
  return ['en', 'ru', 'es'].includes(lang) ? lang : 'en'
}

function normalizeTemplateSet(value) {
  const templateSet = String(value || 'default').trim()
  return /^[A-Za-z0-9._-]{1,64}$/.test(templateSet) ? templateSet : 'default'
}

function normalizeMails(value) {
  if (!value) return []
  if (Array.isArray(value)) return value
  return String(value)
      .split(',')
      .map(item => item.trim())
      .filter(Boolean)
}
