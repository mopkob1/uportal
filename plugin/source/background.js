const DEFAULTS = {
  apiBase: 'http://localhost:8080',
  pixelBaseUrl: '',
  userToken: '',
  dictionaryUrl: '',
  defaultMailFrom: '',
  defaultLinkText: '',
  pixelTokenPrefix: 'mail-pixel',
  clientUid: ''
}

const PLACEHOLDER_RE = /\[\[uportal:([a-zA-Z0-9_-]+)\]\]/g
const API_TIMEOUT_MS = 7000
const USER_DECISION_TIMEOUT_MS = 120000

let dictionaryCache = null
const pendingDecisions = new Map()
const composeNoUportal = new Map()
let backgroundCaptionsPromise = null

function getBackgroundCaptions() {
  if (!backgroundCaptionsPromise) {
    backgroundCaptionsPromise = UPortalCaptions.get('background')
  }
  return backgroundCaptionsPromise
}

async function backgroundMessage(key, values = {}) {
  const captions = await getBackgroundCaptions()
  return UPortalCaptions.format(captions[key], values)
}

async function init() {
  await ensureDefaults()

  if (browser.composeScripts && browser.composeScripts.register) {
    await browser.composeScripts.register({
      js: [{ file: 'compose-script.js' }]
    })
  }
}

async function ensureDefaults() {
  const current = await browser.storage.local.get(Object.keys(DEFAULTS))
  const patch = {}
  const apiBase = current.apiBase || DEFAULTS.apiBase

  for (const [key, value] of Object.entries(DEFAULTS)) {
    if (current[key] === undefined) {
      if (key === 'pixelBaseUrl') {
        patch[key] = current.apiBase || DEFAULTS.apiBase
      } else if (key === 'dictionaryUrl') {
        patch[key] = `${current.apiBase || DEFAULTS.apiBase}/api/admin/dictionary`
      } else if (key === 'defaultMailFrom') {
        patch[key] = defaultMailFromForBase(apiBase)
      } else {
        patch[key] = value
      }
    }
  }

  if (!current.defaultMailFrom || isLegacyDefaultMailFrom(current.defaultMailFrom)) {
    patch.defaultMailFrom = defaultMailFromForBase(apiBase)
  }

  if (Object.keys(patch).length) {
    await browser.storage.local.set(patch)
  }

  if (!current.clientUid) {
    await browser.storage.local.set({ clientUid: makeClientUid() })
  }
}

async function getSettings() {
  const settings = await browser.storage.local.get(Object.keys(DEFAULTS))
  const merged = { ...DEFAULTS, ...settings }
  if (!merged.defaultMailFrom) {
    merged.defaultMailFrom = defaultMailFromForBase(merged.apiBase)
  }
  return merged
}

async function loadDictionary(force = false) {
  if (dictionaryCache && !force) return dictionaryCache

  const settings = await getSettings()

  if (!settings.userToken) {
    dictionaryCache = []
    return dictionaryCache
  }

  const res = await fetchWithTimeout(settings.dictionaryUrl, {
    method: 'GET',
    headers: {
      Accept: 'application/json',
      'X-User-Token': settings.userToken || ''
    }
  })

  if (!res.ok) throw new Error(`dictionary http ${res.status}`)

  dictionaryCache = await normalizeDictionary(await res.json())
  return dictionaryCache
}

function defaultMailFromForBase(apiBase) {
  return `no-reply@${secondLevelDomain(domainFromUrl(apiBase) || 'localhost')}`
}

function isLegacyDefaultMailFrom(value) {
  return String(value || '') === ['no-reply', '1qr.org'].join('@')
}

function domainFromUrl(value) {
  try {
    return new URL(String(value || '')).hostname || ''
  } catch (_) {
    return ''
  }
}

function secondLevelDomain(hostname) {
  const host = String(hostname || '').toLowerCase().replace(/\.$/, '')
  if (!host || host === 'localhost' || /^[0-9.]+$/.test(host)) return 'localhost'
  const parts = host.split('.').filter(Boolean)
  if (parts.length <= 2) return parts.join('.')
  return parts.slice(-2).join('.')
}

async function normalizeDictionary(payload) {
  const captions = await getBackgroundCaptions()
  let items = []

  if (Array.isArray(payload)) {
    items = payload
  } else if (Array.isArray(payload?.message?.[0])) {
    items = payload.message[0]
  } else if (Array.isArray(payload?.message?.[0]?.items)) {
    items = payload.message[0].items
  } else if (Array.isArray(payload?.items)) {
    items = payload.items
  } else if (Array.isArray(payload?.links)) {
    items = payload.links
  }

  return items
    .map((item, index) => normalizeDictionaryItem(item, index, captions))
    .filter(item => item.type === 'redirect' || item.type === 'pixel')
}

function normalizeDictionaryItem(item, index, captions) {
  const type = String(item?.type || 'redirect').toLowerCase()
  const anchor = String(item?.anchor || item?.link_text || item?.title || item?.url || UPortalCaptions.format(captions.defaultDictionaryAnchor, { index: index + 1 }))
  const url = String(item?.url || item?.target_url || '')
  const stableSource = `${type}|${url}|${anchor}|${index}`

  return {
    id: safeTokenPart(item?.id || item?.key || hashCode(stableSource)),
    pre: String(item?.pre ?? item?.before_text ?? ''),
    post: String(item?.post ?? item?.after_text ?? ''),
    url,
    anchor,
    type,
    tags: String(item?.tags || ''),
    payload: item?.payload && typeof item.payload === 'object' ? item.payload : {}
  }
}

function findDictionaryItem(dictionary, id) {
  return dictionary.find(item => item.id === id) || null
}


async function fetchWithTimeout(url, options = {}, timeoutMs = API_TIMEOUT_MS) {
  const controller = new AbortController()
  const timer = setTimeout(() => controller.abort(), timeoutMs)

  try {
    return await fetch(url, {
      ...options,
      signal: controller.signal
    })
  } catch (error) {
    if (error?.name === 'AbortError') {
      throw new Error(await backgroundMessage('timeout', { seconds: Math.round(timeoutMs / 1000) }))
    }
    throw error
  } finally {
    clearTimeout(timer)
  }
}

async function apiPost(path, payload) {
  const settings = await getSettings()
  const res = await fetchWithTimeout(`${settings.apiBase}${path}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Accept: 'application/json',
      'X-User-Token': settings.userToken || '',
      'X-UPortal-Client-Uid': settings.clientUid || '',
      'X-UPortal-Client-Type': 'plugin'
    },
    body: JSON.stringify(payload)
  })

  const data = await res.json().catch(() => ({}))

  if (!res.ok || data.status === 'error') {
    const msg = data?.message?.[0]?.text || data?.message || `http ${res.status}`
    throw new Error(String(msg))
  }

  return data
}

async function extractShortUrl(payload, apiBase) {
  const candidates = []

  function walk(value) {
    if (!value) return

    if (typeof value === 'string') {
      candidates.push(value)
      return
    }

    if (Array.isArray(value)) {
      value.forEach(walk)
      return
    }

    if (typeof value === 'object') {
      for (const key of ['short_url', 'shortlink', 'shortUrl', 'url', 'href', 'short', 'short_id', 'html']) {
        if (value[key]) walk(value[key])
      }

      for (const item of Object.values(value)) {
        if (item && typeof item === 'object') walk(item)
      }
    }
  }

  walk(payload)

  const url = candidates.find(item => /^https?:\/\/[^\s"']+\/s\/[A-Za-z0-9]+/.test(item))
  if (url) return url.match(/https?:\/\/[^\s"']+\/s\/[A-Za-z0-9]+/)?.[0] || url

  const short = candidates.find(item => /^[A-Za-z0-9]{9}$/.test(item))
  if (short) return `${apiBase}/s/${short}`

  throw new Error(await backgroundMessage('shortUrlExtractFailed'))
}

function normalizeShortBaseUrl(url, baseUrl) {
  const rawUrl = String(url || '')
  const rawBase = String(baseUrl || '').replace(/\/+$/g, '')

  if (!rawBase) return rawUrl

  const match = rawUrl.match(/\/s\/([A-Za-z0-9]{9})(?:[^A-Za-z0-9]|$)/)
  if (!match) return rawUrl

  return `${rawBase}/s/${match[1]}`
}

function safeTokenPart(value) {
  return String(value || '')
    .toLowerCase()
    .replace(/[^a-z0-9_-]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 48) || 'link'
}

function uniqueToken(itemId, index) {
  return `${safeTokenPart(itemId)}-${index + 1}`
}

function pixelToken(prefix) {
  return `${safeTokenPart(prefix)}-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`
}

function makeClientUid() {
  const random = globalThis.crypto?.randomUUID
    ? globalThis.crypto.randomUUID()
    : `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 12)}`
  return `plugin-${random}`.replace(/[^A-Za-z0-9._:-]/g, '-').slice(0, 128)
}

function hashCode(value) {
  let hash = 0
  const text = String(value)
  for (let index = 0; index < text.length; index += 1) {
    hash = ((hash << 5) - hash + text.charCodeAt(index)) | 0
  }
  return `link-${Math.abs(hash)}`
}

function getRecipients(details) {
  const all = []
  for (const key of ['to', 'cc', 'bcc']) {
    const value = details[key]
    if (Array.isArray(value)) all.push(...value)
  }
  return all.map(String).filter(Boolean)
}

function getSubject(details, captions) {
  return String(details.subject || '').trim() || captions.defaultSubject
}

async function buildCommonPayload(details, publicationId, token, linkText) {
  const settings = await getSettings()
  const captions = await getBackgroundCaptions()
  const recipients = getRecipients(details)

  return {
    publication_id: publicationId,
    token,
    subj: getSubject(details, captions),
    mails: recipients.length ? recipients : [settings.defaultMailFrom],
    link: linkText || settings.defaultLinkText || captions.defaultLinkText,
    fresh_until: -1,
    remaining_clicks: -1,
    fallback_url: `${settings.apiBase}/link-fallback`
  }
}

async function publishRedirect(details, publicationId, token, linkConfig) {
  if (!linkConfig.url) throw new Error(await backgroundMessage('redirectUrlMissing', { id: linkConfig.id }))

  const common = await buildCommonPayload(details, publicationId, token, linkConfig.anchor)
  const payload = {
    ...common,
    ...linkConfig.payload,
    target_url: linkConfig.url,
    title: linkConfig.payload.title || linkConfig.anchor,
    description: linkConfig.payload.description || '',
  }

  return apiPost('/api/admin/publish/redirect', payload)
}

async function publishPixel(details, publicationId) {
  const settings = await getSettings()
  const token = pixelToken(settings.pixelTokenPrefix)
  const common = await buildCommonPayload(details, publicationId, token, 'pixel')
  const data = await apiPost('/api/admin/publish/pixel', common)
  const shortUrl = await extractShortUrl(data, settings.apiBase)
  return normalizeShortBaseUrl(shortUrl, settings.pixelBaseUrl || settings.apiBase)
}

function buildPixelImg(url) {
  return `<img src="${escapeHtml(url)}" width="1" height="1" alt="" style="width:1px;height:1px;border:0;" data-uportal-pixel="1">`
}

function escapeHtml(value) {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;')
}

function appendToBodyHtml(body, html) {
  if (/<\/body>/i.test(body)) {
    return body.replace(/<\/body>/i, `${html}</body>`)
  }
  return `${body}${html}`
}


function makeDecisionId() {
  return `decision-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`
}

async function askServerFailureDecision(error) {
  const decisionId = makeDecisionId()

  const promise = new Promise((resolve) => {
    const timer = setTimeout(() => {
      pendingDecisions.delete(decisionId)
      resolve('cancel')
    }, USER_DECISION_TIMEOUT_MS)

    pendingDecisions.set(decisionId, {
      resolve: (choice) => {
        clearTimeout(timer)
        resolve(choice)
      }
    })
  })

  try {
    await browser.windows.create({
      url: browser.runtime.getURL(`confirm/confirm.html?id=${encodeURIComponent(decisionId)}&error=${encodeURIComponent(error?.message || String(error || ''))}`),
      type: 'popup',
      width: 520,
      height: 280
    })
  } catch (openError) {
    console.error('UPORTAL confirm window error', openError)
    pendingDecisions.delete(decisionId)
    return 'cancel'
  }

  return promise
}

function resolveDecision(id, choice) {
  const pending = pendingDecisions.get(id)
  if (!pending) return

  pendingDecisions.delete(id)
  pending.resolve(choice === 'send_plain' ? 'send_plain' : 'cancel')
}

function buildPlainBody(body) {
  let result = String(body || '')
  const dictionary = Array.isArray(dictionaryCache) ? dictionaryCache : []

  result = result.replace(PLACEHOLDER_RE, (full, itemId) => {
    const item = findDictionaryItem(dictionary, itemId)
    return item?.url || ''
  })

  // Remove a stale hidden pixel from a previous send attempt.
  result = result.replace(/<img\b[^>]*data-uportal-pixel=["']1["'][^>]*>/gi, '')

  return result
}

async function trySaveDraft(tab) {
  try {
    if (browser.compose?.beginSave && tab?.id) {
      await browser.compose.beginSave(tab.id, { mode: 'draft' })
    }
  } catch (error) {
    console.error('UPORTAL draft save error', error)
  }
}

browser.runtime.onMessage.addListener((message) => {
  if (message?.type === 'dictionary:get') return loadDictionary(!!message.force)
  if (message?.type === 'dictionary:refresh') {
    dictionaryCache = null
    return loadDictionary(true)
  }
  if (message?.type === 'settings:get') return getSettings()
  if (message?.type === 'compose:no-uportal:get') {
    return Promise.resolve({ enabled: !!composeNoUportal.get(Number(message.tabId)) })
  }
  if (message?.type === 'compose:no-uportal:set') {
    const tabId = Number(message.tabId)
    if (message.enabled) composeNoUportal.set(tabId, true)
    else composeNoUportal.delete(tabId)
    return Promise.resolve({ ok: true })
  }
  if (message?.type === 'server-failure-decision') {
    resolveDecision(message.id, message.choice)
    return Promise.resolve({ ok: true })
  }
})

browser.compose.onBeforeSend.addListener(async (tab, details) => {
  const body = String(details.body || '')
  const tabId = Number(tab?.id)

  if (composeNoUportal.get(tabId)) {
    composeNoUportal.delete(tabId)
    return {
      details: {
        body: buildPlainBody(body)
      }
    }
  }

  try {
    const matches = [...body.matchAll(PLACEHOLDER_RE)]
    const settings = await getSettings()
    const publicationId = `mail-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`

    let dictionary = Array.isArray(dictionaryCache) ? dictionaryCache : []
    if (matches.length) {
      dictionary = await loadDictionary(false)
    }

    let newBody = body

    for (let index = 0; index < matches.length; index += 1) {
      const match = matches[index]
      const itemId = match[1]
      const item = findDictionaryItem(dictionary, itemId)

      if (!item) {
        throw new Error(await backgroundMessage('dictionaryLinkMissing', { id: itemId }))
      }

      if (item.type !== 'redirect') {
        continue
      }

      const token = uniqueToken(item.id, index)
      const data = await publishRedirect(details, publicationId, token, item)
      const shortUrl = await extractShortUrl(data, settings.apiBase)

      newBody = newBody.split(match[0]).join(shortUrl)
    }

    const pixelUrl = await publishPixel(details, publicationId)
    newBody = appendToBodyHtml(newBody, buildPixelImg(pixelUrl))

    return { details: { body: newBody } }
  } catch (error) {
    console.error('UPORTAL send preparation failed', error)

    const decision = await askServerFailureDecision(error)

    if (decision === 'send_plain') {
      return {
        details: {
          body: buildPlainBody(body)
        }
      }
    }

    await trySaveDraft(tab)
    return { cancel: true }
  }
})

init().catch(error => console.error('UPORTAL init error', error))
