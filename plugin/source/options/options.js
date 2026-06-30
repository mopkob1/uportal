const ids = [
  'apiBase',
  'pixelBaseUrl',
  'userToken',
  'clientUid',
  'dictionaryUrl',
  'defaultMailFrom',
  'pixelTokenPrefix'
]
const saveIds = ids.filter(id => id !== 'clientUid')

const statusEl = document.getElementById('status')
const versionBadge = document.getElementById('versionBadge')
let captions = null
let loadedApiBase = ''

updateVersionBadge('')

document.getElementById('save').addEventListener('click', save)
document.getElementById('testDictionary').addEventListener('click', testDictionary)
document.getElementById('copyClientUid').addEventListener('click', copyClientUid)
document.getElementById('apiBase').addEventListener('input', syncDomainDerivedFields)

async function load() {
  const data = await browser.runtime.sendMessage({ type: 'settings:get' })
  if (!data.clientUid) {
    data.clientUid = makeClientUid()
    await browser.storage.local.set({ clientUid: data.clientUid })
  }

  for (const id of ids) {
    const el = document.getElementById(id)
    if (el.type === 'checkbox') el.checked = !!data[id]
    else el.value = data[id] || ''
  }

  loadedApiBase = data.apiBase || ''
  syncDomainDerivedFields()
  updateVersionBadge(data.apiBase)
}

async function save() {
  const data = {}

  for (const id of saveIds) {
    const el = document.getElementById(id)
    data[id] = el.type === 'checkbox' ? el.checked : el.value.trim()
  }

  if (!data.dictionaryUrl && data.apiBase) {
    data.dictionaryUrl = `${data.apiBase.replace(/\/+$/g, '')}/api/admin/dictionary`
  }
  if (!data.defaultMailFrom || isLegacyDefaultMailFrom(data.defaultMailFrom)) {
    data.defaultMailFrom = defaultMailFromForBase(data.apiBase)
  }

  await browser.storage.local.set(data)
  loadedApiBase = data.apiBase || ''
  updateVersionBadge(data.apiBase)
  statusEl.textContent = captions.saved
}

async function copyClientUid() {
  const value = document.getElementById('clientUid').value
  await navigator.clipboard.writeText(value)
  statusEl.textContent = captions.uidCopied
}

function makeClientUid() {
  const random = globalThis.crypto?.randomUUID
    ? globalThis.crypto.randomUUID()
    : `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 12)}`
  return `plugin-${random}`.replace(/[^A-Za-z0-9._:-]/g, '-').slice(0, 128)
}

async function testDictionary() {
  await save()
  const dictionary = await browser.runtime.sendMessage({ type: 'dictionary:refresh' })
  statusEl.textContent = JSON.stringify({
    items: dictionary.length,
    redirect: dictionary.filter(item => item.type === 'redirect').length,
    pixel: dictionary.filter(item => item.type === 'pixel').length,
    source: captions.serverSource
  }, null, 2)
}

function updateVersionBadge(apiBase) {
  const domain = domainFromUrl(apiBase)
  versionBadge.textContent = `v${browser.runtime.getManifest().version}${domain ? ` (${domain})` : ''}`
}

function syncDomainDerivedFields() {
  const apiBase = document.getElementById('apiBase').value.trim()
  const defaultMailFrom = document.getElementById('defaultMailFrom')
  const currentMail = defaultMailFrom.value.trim()
  const previousDefault = defaultMailFromForBase(loadedApiBase)

  if (!currentMail || isLegacyDefaultMailFrom(currentMail) || currentMail === previousDefault) {
    defaultMailFrom.value = defaultMailFromForBase(apiBase)
  }

  updateVersionBadge(apiBase)
}

function domainFromUrl(value) {
  try {
    return new URL(String(value || '')).hostname || ''
  } catch (_) {
    return ''
  }
}

function defaultMailFromForBase(apiBase) {
  return `no-reply@${secondLevelDomain(domainFromUrl(apiBase) || 'localhost')}`
}

function isLegacyDefaultMailFrom(value) {
  return String(value || '') === ['no-reply', '1qr.org'].join('@')
}

function secondLevelDomain(hostname) {
  const host = String(hostname || '').toLowerCase().replace(/\.$/, '')
  if (!host || host === 'localhost' || /^[0-9.]+$/.test(host)) return 'localhost'
  const parts = host.split('.').filter(Boolean)
  if (parts.length <= 2) return parts.join('.')
  return parts.slice(-2).join('.')
}

function setText(id, value) {
  const element = document.getElementById(id)
  if (element) element.textContent = value
}

function setPlaceholder(id, value) {
  const element = document.getElementById(id)
  if (element) element.placeholder = value
}

function applyCaptions() {
  document.title = captions.title
  setText('headingText', captions.heading)
  setText('apiBaseLabel', captions.apiBase)
  setText('userTokenLabel', captions.userToken)
  setText('clientUidLabel', captions.clientUid)
  setText('pixelBaseUrlLabel', captions.pixelBaseUrl)
  setText('dictionaryUrlLabel', captions.dictionaryUrl)
  setText('defaultMailFromLabel', captions.defaultMailFrom)
  setText('pixelTokenPrefixLabel', captions.pixelTokenPrefix)
  setText('save', captions.save)
  setText('testDictionary', captions.testDictionary)

  document.getElementById('copyClientUid').title = captions.copyClientUidTitle
  setPlaceholder('apiBase', captions.apiBasePlaceholder)
  setPlaceholder('userToken', captions.userTokenPlaceholder)
  setPlaceholder('pixelBaseUrl', captions.pixelBaseUrlPlaceholder)
  setPlaceholder('dictionaryUrl', captions.dictionaryUrlPlaceholder)
  setPlaceholder('defaultMailFrom', captions.defaultMailFromPlaceholder)
  setPlaceholder('pixelTokenPrefix', captions.pixelTokenPrefixPlaceholder)
}

async function init() {
  captions = await UPortalCaptions.get('options')
  applyCaptions()
  await load()
}

init().catch(error => {
  statusEl.textContent = String(error.message || error)
})
