const content = document.getElementById('content')
const refresh = document.getElementById('refresh')
const tagFilter = document.getElementById('tagFilter')
const insertSelected = document.getElementById('insertSelected')
const copyClientUid = document.getElementById('copyClientUid')
const versionBadge = document.getElementById('versionBadge')
const popupLogoLink = document.getElementById('popupLogoLink')
const switchOff = document.getElementById('switchOff')
const switchOn = document.getElementById('switchOn')

let dictionary = []
let captions = null
let pluginEnabled = true

updateVersionBadge('')

refresh.addEventListener('click', () => load(true))
tagFilter.addEventListener('input', () => render())
insertSelected.addEventListener('click', () => insertChecked())
copyClientUid.addEventListener('click', () => copyPluginUid())
switchOff.addEventListener('click', () => savePluginEnabled(false))
switchOn.addEventListener('click', () => savePluginEnabled(true))
async function getActiveTab() {
  const [tab] = await browser.tabs.query({ active: true, currentWindow: true })
  return tab || null
}

async function copyPluginUid() {
  const settings = await browser.runtime.sendMessage({ type: 'settings:get' })
  await navigator.clipboard.writeText(settings.clientUid || '')
  copyClientUid.textContent = captions.uidCopiedButton
  setTimeout(() => {
    copyClientUid.textContent = captions.uidButton
  }, 900)
}

function updateVersionBadge(apiBase) {
  const domain = domainFromUrl(apiBase)
  versionBadge.textContent = `v${browser.runtime.getManifest().version}${domain ? ` (${domain})` : ''}`
}

async function savePluginEnabled(enabled) {
  const state = await browser.runtime.sendMessage({
    type: 'plugin:enabled:set',
    enabled
  })

  pluginEnabled = state?.enabled !== false
  updateUiState()
  if (pluginEnabled) {
    await load(false)
  } else {
    render()
  }
}

function updateUiState() {
  document.body.classList.toggle('is-disabled', !pluginEnabled)
  switchOn.classList.toggle('is-active', pluginEnabled)
  switchOff.classList.toggle('is-active', !pluginEnabled)
  switchOn.setAttribute('aria-pressed', String(pluginEnabled))
  switchOff.setAttribute('aria-pressed', String(!pluginEnabled))
  tagFilter.disabled = !pluginEnabled
  refresh.disabled = !pluginEnabled
  insertSelected.disabled = !pluginEnabled
}

function domainFromUrl(value) {
  try {
    return new URL(String(value || '')).hostname || ''
  } catch (_) {
    return ''
  }
}

async function load(force = false) {
  if (!pluginEnabled) {
    render()
    return
  }

  content.innerHTML = muted(captions.loading)

  try {
    dictionary = await browser.runtime.sendMessage({ type: 'dictionary:get', force })
    render()
  } catch (error) {
    content.innerHTML = `<div class="error">${escapeHtml(error.message || error)}</div>`
  }
}

function render() {
  if (!pluginEnabled) {
    content.innerHTML = muted(captions.disabled)
    return
  }

  const items = filteredItems()
  content.innerHTML = ''

  if (!items.length) {
    content.innerHTML = muted(captions.empty)
    return
  }

  for (const item of items) {
    const row = document.createElement('div')
    row.className = 'item'

    const checkbox = document.createElement('input')
    checkbox.type = 'checkbox'
    checkbox.value = item.id
    row.appendChild(checkbox)

    const main = document.createElement('div')
    main.className = 'item-main'
    main.innerHTML = `
      <div class="item-title">${escapeHtml(item.anchor || item.url || item.id)}</div>
      <div class="item-preview">${escapeHtml((item.pre || '') + (item.anchor || '') + (item.post || ''))}</div>
      <div class="item-url">${escapeHtml(item.url || '')}</div>
      <div class="item-tags">${escapeHtml(item.tags || '')}</div>
      <div class="item-actions"><button type="button" data-id="${escapeHtml(item.id)}">${escapeHtml(captions.insert)}</button></div>
    `
    row.appendChild(main)

    const type = document.createElement('div')
    type.className = 'item-type'
    type.textContent = item.type
    row.appendChild(type)

    main.querySelector('button').addEventListener('click', () => insertItems([item.id]))
    content.appendChild(row)
  }
}

function filteredItems() {
  const filter = tagFilter.value.trim().toLowerCase()
  const tags = filter
    .split(',')
    .map(item => item.trim())
    .filter(Boolean)

  return dictionary.filter(item => {
    if (item.type !== 'redirect') return false
    if (!tags.length) return true

    const haystack = String(item.tags || '').toLowerCase()
    return tags.every(tag => haystack.includes(tag))
  })
}

function insertChecked() {
  if (!pluginEnabled) return
  const ids = [...content.querySelectorAll('input[type="checkbox"]:checked')].map(item => item.value)
  if (!ids.length) return
  insertItems(ids)
}

async function insertItems(ids) {
  if (!pluginEnabled) return

  const selected = ids
    .map(id => dictionary.find(item => item.id === id))
    .filter(Boolean)

  if (!selected.length) return

  const html = selected.map(buildInsertHtml).join('<br>')
  const tab = await getActiveTab()

  if (tab?.id) {
    await browser.tabs.sendMessage(tab.id, {
      type: 'uportal:insert-html',
      html
    })
  }

  window.close()
}

function buildInsertHtml(item) {
  const placeholder = `[[uportal:${item.id}]]`
  const anchor = item.anchor || item.url || captions.defaultAnchor
  return `${escapeHtml(item.pre || '')}<a href="${escapeHtml(placeholder)}" data-uportal-id="${escapeHtml(item.id)}">${escapeHtml(anchor)}</a>${escapeHtml(item.post || '')}`
}

function muted(value) {
  return `<div class="muted">${escapeHtml(value)}</div>`
}

function escapeHtml(value) {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;')
}

async function init() {
  captions = await UPortalCaptions.get('popup')
  const settings = await browser.runtime.sendMessage({ type: 'settings:get' })
  pluginEnabled = settings.enabled !== false

  document.title = captions.title
  updateVersionBadge(settings.apiBase)
  popupLogoLink.href = settings.apiBase || '#'
  tagFilter.placeholder = captions.tagFilterPlaceholder
  refresh.title = captions.refreshTitle
  copyClientUid.title = captions.copyClientUidTitle
  copyClientUid.textContent = captions.uidButton
  insertSelected.textContent = captions.insertSelected

  updateUiState()
  await load(false)
}

init().catch(error => {
  content.innerHTML = `<div class="error">${escapeHtml(error.message || error)}</div>`
})
