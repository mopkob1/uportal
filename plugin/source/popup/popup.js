const content = document.getElementById('content')
const refresh = document.getElementById('refresh')
const tagFilter = document.getElementById('tagFilter')
const insertSelected = document.getElementById('insertSelected')
const noUportal = document.getElementById('noUportal')
const copyClientUid = document.getElementById('copyClientUid')
const versionBadge = document.getElementById('versionBadge')
const noUportalLabel = document.getElementById('noUportalLabel')

let dictionary = []
let captions = null

updateVersionBadge('')

refresh.addEventListener('click', () => load(true))
tagFilter.addEventListener('input', () => render())
insertSelected.addEventListener('click', () => insertChecked())
noUportal.addEventListener('change', () => saveNoUportalFlag())
copyClientUid.addEventListener('click', () => copyPluginUid())
async function getActiveTab() {
  const [tab] = await browser.tabs.query({ active: true, currentWindow: true })
  return tab || null
}

async function loadNoUportalFlag() {
  const tab = await getActiveTab()
  if (!tab?.id) return

  const state = await browser.runtime.sendMessage({
    type: 'compose:no-uportal:get',
    tabId: tab.id
  })

  noUportal.checked = !!state?.enabled
}

async function saveNoUportalFlag() {
  const tab = await getActiveTab()
  if (!tab?.id) return

  await browser.runtime.sendMessage({
    type: 'compose:no-uportal:set',
    tabId: tab.id,
    enabled: noUportal.checked
  })
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

function domainFromUrl(value) {
  try {
    return new URL(String(value || '')).hostname || ''
  } catch (_) {
    return ''
  }
}

async function load(force = false) {
  content.innerHTML = muted(captions.loading)

  try {
    dictionary = await browser.runtime.sendMessage({ type: 'dictionary:get', force })
    render()
  } catch (error) {
    content.innerHTML = `<div class="error">${escapeHtml(error.message || error)}</div>`
  }
}

function render() {
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
  const ids = [...content.querySelectorAll('input[type="checkbox"]:checked')].map(item => item.value)
  if (!ids.length) return
  insertItems(ids)
}

async function insertItems(ids) {
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

  document.title = captions.title
  updateVersionBadge(settings.apiBase)
  tagFilter.placeholder = captions.tagFilterPlaceholder
  refresh.title = captions.refreshTitle
  noUportalLabel.textContent = captions.noUportal
  copyClientUid.title = captions.copyClientUidTitle
  copyClientUid.textContent = captions.uidButton
  insertSelected.textContent = captions.insertSelected

  await loadNoUportalFlag().catch(() => {})
  await load(false)
}

init().catch(error => {
  content.innerHTML = `<div class="error">${escapeHtml(error.message || error)}</div>`
})
