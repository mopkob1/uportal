// src/publications/useLinkReport.js

import { h, reactive } from 'vue'
import { activityList } from '../api/uportalApi'
import { NBadge, NTag, NTooltip, useMessage } from 'naive-ui'

const reportCache = reactive({})
const REPORT_EVENT_WINDOW_MS = 2000
const DEBUG_REPORTS_KEY = 'uportal_debug_reports'

function useLinkReport(captions = {}) {
  const message = useMessage()

  async function loadLinkReport(row) {
    try {
      const events = await loadReportEvents(row)

      return setLinkReport(row, events)
    } catch (error) {
      debugReport('loadLinkReport:error', { row: describeRow(row), error })
      return setLinkReportError(row, error)
    }
  }

  async function loadPublicationLinkReports(links) {
    const rows = Array.isArray(links) ? links : []
    const publicationId = getRowsPublication(rows)

    for (const row of rows) {
      setLinkReportLoading(row)
    }

    if (!publicationId || !rows.length) {
      return rows.map(row => getCachedReport(row)).filter(Boolean)
    }

    const payload = await activityList(cleanRequest({
      publication_id: publicationId,
      token: getRowsTokenFilter(rows),
      page: 1,
      limit: 500
    }))
    const events = extractActivityItems(payload)
    debugReport('loadPublicationLinkReports:payload', {
      publicationId,
      rows: rows.map(describeRow),
      events: events.map(describeEvent)
    })

    const reports = []

    for (const row of rows) {
      try {
        let rowEvents = events.filter(event => isSameLinkEvent(row, event))

        if (!rowEvents.length && rows.length > 1) {
          rowEvents = await loadReportEvents(row)
        }

        const report = setLinkReport(row, rowEvents)
        debugReport('loadPublicationLinkReports:row', {
          row: describeRow(row),
          matched: rowEvents.map(describeEvent),
          summary: report.summary
        })
        reports.push(report)
      } catch (error) {
        debugReport('loadPublicationLinkReports:row:error', { row: describeRow(row), error })
        reports.push(setLinkReportError(row, error))
      }
    }

    return reports
  }

  function setLinkReport(row, events) {
    const key = getRowKey(row)
    const summary = buildSummary(row, events, captions)
    const value = {
      loaded: true,
      loading: false,
      events,
      summary,
      report: buildLinkReport(row, events, captions)
    }

    reportCache[key] = value

    for (const alias of getRowReportAliases(row)) {
      reportCache[alias] = value
    }

    return value
  }

  function setLinkReportError(row, error) {
    const key = getRowKey(row)
    const value = {
      loaded: true,
      loading: false,
      error,
      events: [],
      summary: buildSummary(row, [], captions),
      report: ''
    }

    reportCache[key] = value

    for (const alias of getRowReportAliases(row)) {
      reportCache[alias] = value
    }

    return value
  }

  function setLinkReportLoading(row) {
    const key = getRowKey(row)
    const value = {
      loaded: false,
      loading: true,
      events: [],
      summary: null,
      report: ''
    }

    reportCache[key] = value

    for (const alias of getRowReportAliases(row)) {
      reportCache[alias] = value
    }

    return value
  }

  async function copyLinkReport(row) {
    const key = getRowKey(row)

    try {
      reportCache[key] = {
        ...(reportCache[key] || {}),
        loading: true
      }

      const cached = await loadLinkReport(row)

      await navigator.clipboard.writeText(cached.report)

      message.success(captions.reportCopied)
    } catch (error) {
      reportCache[key] = {
        ...(reportCache[key] || {}),
        loading: false
      }

      message.error(captions.reportLoadError)
    }
  }

  function renderTypeBadge(row) {
    const cached = getCachedReport(row)
    const label = row.type || '—'

    const tag = h(NTag, {
      size: 'small',
      style: 'cursor: pointer;',
      onClick: () => copyLinkReport(row)
    }, {
      default: () => label
    })

    const content = cached?.loaded && cached.summary
        ? h(NBadge, {
          value: `${cached.summary.views}/${cached.summary.users}`,
          type: cached.summary.views > 0 ? 'success' : 'default',
          processing: cached.loading
        }, {
          default: () => tag
        })
        : cached?.loading
            ? h(NBadge, {
              dot: true,
              processing: true
            }, {
              default: () => tag
            })
        : tag

    return h(NTooltip, {
      placement: 'right',
      trigger: 'hover'
    }, {
      trigger: () => content,
      default: () => cached?.loaded && cached.summary
          ? renderTooltipRows(cached.summary.userRows, captions)
          : captions.reportTooltipHint
    })
  }

  return {
    copyLinkReport,
    renderTypeBadge,
    loadLinkReport,
    loadPublicationLinkReports,
    reportCache
  }
}

function getRowKey(row) {
  return `${getRowPublication(row)}:${getRowToken(row)}`
}

function getCachedReport(row) {
  const keys = [
    getRowKey(row),
    ...getRowReportAliases(row)
  ]

  for (const key of keys) {
    if (reportCache[key]) return reportCache[key]
  }

  return null
}

function getRowReportAliases(row) {
  const publicationId = getRowPublication(row)
  if (!publicationId) return []

  return getRowShortIds(row)
      .map(shortId => `${publicationId}:short:${shortId}`)
}

function getRowsPublication(rows) {
  const publications = uniqueNonEmpty(rows.map(getRowPublication))
  return publications.length === 1 ? publications[0] : ''
}

function getRowsTokenFilter(rows) {
  return uniqueNonEmpty(rows.map(getRowToken)).join(',')
}

async function loadReportEvents(row) {
  const publicationId = getRowPublication(row)
  const token = getRowToken(row)
  const attempts = [
    {
      publication_id: publicationId,
      token,
      page: 1,
      limit: 500
    }
  ].map(cleanRequest)

  let lastError = null

  for (const request of attempts) {
    try {
      const payload = await activityList(request)
      const events = extractActivityItems(payload)
          .filter(event => isSameLinkEvent(row, event))

      if (events.length || request === attempts[attempts.length - 1]) {
        return events
      }
    } catch (error) {
      lastError = error
    }
  }

  if (lastError) throw lastError
  return []
}

function cleanRequest(request) {
  return Object.fromEntries(
      Object.entries(request).filter(([, value]) => value !== '')
  )
}

function isSameLinkEvent(row, event) {
  const publicationId = getRowPublication(row)
  const token = getRowToken(row)
  const rowShortIds = getRowShortIds(row)
  const eventShortIds = getEventShortIds(event)
  const hasSameShort = rowShortIds.some(value => eventShortIds.includes(value))

  return (
      (!publicationId || getEventPublication(event) === publicationId) &&
      (
        !token ||
        getEventToken(event) === token ||
        hasSameShort
      )
  )
}

function getRowPublication(row) {
  return row.publication_id || row.publication || row.raw?.publication_id || row.raw?.publication || ''
}

function getRowToken(row) {
  return row.token || row.raw?.token || ''
}

function getRowType(row) {
  return String(row.type || row.raw?.type || row.meta?.type || '').trim().toLowerCase()
}

function getEventPublication(event) {
  return event.publication || event.publication_id || ''
}

function getEventToken(event) {
  return event.token || ''
}

function getRowShortIds(row) {
  return uniqueNonEmpty([
    row.short_id,
    row.short,
    row.short_url,
    row.shortlink,
    row.raw?.short_id,
    row.raw?.short,
    row.raw?.short_url,
    row.raw?.shortlink,
    row.meta?.short_id,
    row.meta?.short,
    row.meta?.short_url,
    row.meta?.shortlink
  ].flatMap(extractShortIds))
}

function getEventShortIds(event) {
  return uniqueNonEmpty([
    event.short_id,
    event.short,
    event.short_url,
    event.shortlink,
    event.meta?.short_id,
    event.meta?.short,
    event.meta?.short_url,
    event.meta?.shortlink,
    event.request?.original_uri
  ].flatMap(extractShortIds))
}

function extractShortIds(value) {
  const text = String(value || '')
  if (!text) return []

  const values = []
  const direct = text.match(/^[A-Za-z0-9]{9}$/)
  if (direct) values.push(direct[0])

  const path = text.match(/\/s\/([A-Za-z0-9]{9})(?:[^A-Za-z0-9]|$)/)
  if (path) values.push(path[1])

  return values
}

function uniqueNonEmpty(values) {
  return Array.from(new Set(values.filter(Boolean)))
}

function extractActivityItems(payload) {
  if (Array.isArray(payload)) return payload
  if (Array.isArray(payload?.items)) return payload.items
  if (Array.isArray(payload?.data)) return payload.data
  if (Array.isArray(payload?.events)) return payload.events

  if (Array.isArray(payload?.message)) {
    if (Array.isArray(payload.message[0]?.items)) return payload.message[0].items
    return payload.message.filter(item => item && item.event)
  }

  return []
}

function buildLinkReport(row, events, t) {
  const eventRows = buildReportEventRows(row, events, t)

  return [
    `${row.publication_id}:${row.token}`,
    extractEmails(row.mails).join(', '),
    row.subj || '',
    row.type === 'pixel' ? '' : buildShortMarkdown(row),
    ...eventRows
  ].join('\n')
}

function buildReportEventRows(row, events, t) {
  const seenVisitors = new Set()

  return getViewedEvents(row, events)
      .map(event => {
        const visitorKey = getEventVisitorKey(event)
        const visitorLabel = getEventVisitorLabel(event, t)
        const isNew = !seenVisitors.has(visitorKey)

        seenVisitors.add(visitorKey)

        return formatReportEvent(row, event, visitorLabel, isNew, t)
      })
      .filter(Boolean)
}

function formatReportEvent(row, event, visitorLabel, isNew, t) {
  const date = formatClientDateTime(getEventDate(event))
  if (!date) return ''

  const browser = getClientBrowser(event)
  const visitLabel = isNew ? t.visitNew : t.visitRepeat

  return `${date} ${visitLabel} ${browser || ''} (${visitorLabel})`
      .replace(/\s+/g, ' ')
      .trim()
}

function buildSummary(row, events, t) {
  const viewedEvents = getViewedEvents(row, events)
  const usersMap = new Map()

  for (const event of viewedEvents) {
    const visitorKey = getEventVisitorKey(event)
    const date = getEventDate(event)

    if (!usersMap.has(visitorKey)) {
      usersMap.set(visitorKey, {
        uid: event.uid || '',
        visitorKey,
        visitorLabel: getEventVisitorLabel(event, t),
        deviceConfidence: event.device_guess?.confidence || '',
        count: 0,
        latest: '',
        browser: ''
      })
    }

    const item = usersMap.get(visitorKey)

    item.count += 1

    if (date && (!item.latest || new Date(date) > new Date(item.latest))) {
      item.latest = date
    }

    const browser = getClientBrowser(event)
    if (browser && !item.browser) {
      item.browser = browser
    }
  }

  const userRows = Array.from(usersMap.values())
      .sort((a, b) => new Date(b.latest || 0) - new Date(a.latest || 0))

  for (const item of userRows) {
    item.relative = relativeFromPublicationToView(row, item.latest, t)
  }

  return {
    views: viewedEvents.length,
    users: userRows.length,
    userRows
  }
}

function collapseEvents(row, events) {
  const priority = {
    click: 5,
    download: 5,
    content: 5,
    page_view: 4,
    pixel: 5,
    open: 1
  }

  const groups = []
  const activeGroups = new Map()

  const ordered = events
      .filter(event => isViewEvent(row, event))
      .sort((a, b) => getRawEventTime(a) - getRawEventTime(b))

  for (const event of ordered) {
    const visitorKey = getEventVisitorKey(event)
    const time = getRawEventTime(event)

    if (!time) continue

    const previous = activeGroups.get(visitorKey)

    if (previous && time - previous._lastEventTime <= REPORT_EVENT_WINDOW_MS) {
      previous._lastEventTime = time
      if ((priority[getEventName(event)] || 0) > (priority[getEventName(previous)] || 0)) {
        Object.assign(previous, event, {
          _firstEventTime: previous._firstEventTime,
          _lastEventTime: time
        })
      }
      continue
    }

    const group = {
      ...event,
      _firstEventTime: time,
      _lastEventTime: time
    }

    groups.push(group)
    activeGroups.set(visitorKey, group)
  }

  return groups
      .sort((a, b) => new Date(getEventDate(a)) - new Date(getEventDate(b)))
}

function getViewedEvents(row, events) {
  const collapsed = collapseEvents(row, events)
  if (collapsed.length || !events.length) return collapsed

  const type = getRowType(row)
  if (type === 'pixel') {
    return events
        .filter(event => ['pixel', 'open'].includes(getEventName(event)))
        .sort((a, b) => new Date(getEventDate(a)) - new Date(getEventDate(b)))
  }

  return collapsed
}

function getEventVisitorKey(event) {
  if (event.uid && event.uid !== 'nouid') return `uid:${event.uid}`
  if (event.device_guess?.key) return `guess:${event.device_guess.key}`
  return 'unknown'
}

function getEventVisitorLabel(event, t) {
  if (event.uid && event.uid !== 'nouid') return event.uid
  if (event.device_guess?.key) {
    const prefix = event.device_guess.confidence === 'high'
        ? t.deviceGuessHigh
        : t.deviceGuessLow
    return `${prefix}:${event.device_guess.key.slice(0, 8)}`
  }
  return 'unknown'
}

function isViewEvent(row, event) {
  const type = getRowType(row)
  const eventName = getEventName(event)

  if (type === 'pixel') return eventName === 'pixel' || eventName === 'open'
  if (type === 'redirect') return eventName === 'click'
  if (type === 'download') return eventName === 'download'
  if (type === 'page') return eventName === 'content'
  return true
}

function getEventName(event) {
  return String(event.event || event.type || '').trim().toLowerCase()
}

function getRawEventTime(event) {
  const date = new Date(getEventDate(event) || 0)
  return Number.isNaN(date.getTime()) ? 0 : date.getTime()
}

function renderTooltipRows(rows, t) {
  if (!rows.length) {
    return h('div', t.reportTooltipEmpty)
  }

  return h('div', {
    style: 'display: flex; flex-direction: column; gap: 4px;'
  }, [
    h('div', {
      style: 'font-weight: 600;'
    }, `${t.devices}: ${rows.length}`),

    ...rows.map(row =>
        h('div', {
          style: 'white-space: nowrap; font-family: monospace;'
        }, `${row.visitorLabel}: ${row.relative} / ${row.count}`)
    )
  ])
}

function getEventDate(event) {
  return event.ts || event.date || event.created_at || ''
}

function getPublicationDate(row) {
  return (
      row.last_action?.date ||
      row.raw?.last_action?.date ||
      row.date ||
      row.created_at ||
      ''
  )
}

function relativeFromPublicationToView(row, viewDate, t) {
  const pubDate = new Date(getPublicationDate(row))
  const eventDate = new Date(viewDate)

  if (Number.isNaN(pubDate.getTime()) || Number.isNaN(eventDate.getTime())) {
    return t.timeUnknown
  }

  const diffMs = Math.max(eventDate.getTime() - pubDate.getTime(), 0)

  const totalSeconds = Math.floor(diffMs / 1000)
  const totalMinutes = Math.floor(totalSeconds / 60)
  const totalHours = Math.floor(totalMinutes / 60)

  const days = Math.floor(totalHours / 24)
  const hours = totalHours % 24
  const minutes = totalMinutes % 60
  const seconds = totalSeconds % 60

  if (days > 0) {
    if (hours > 0) {
      return `+${days}${t.timeDays} ${hours}${t.timeHours}`
    }

    return `+${days}${t.timeDays}`
  }

  if (hours > 0) {
    if (minutes > 0) {
      return `+${hours}${t.timeHours} ${minutes}${t.timeMinutes}`
    }

    return `+${hours}${t.timeHours}`
  }

  if (minutes > 0) {
    return `+${minutes}${t.timeMinutes}`
  }

  return `+${seconds}${t.timeSeconds}`
}

function getClientBrowser(event) {
  return (
      event.browser ||
      event.client_browser ||
      event.request?.browser ||
      parseBrowser(event.request?.ua || event.ua || event.user_agent || '')
  )
}

function parseBrowser(ua) {
  const value = String(ua || '')

  if (!value) return ''

  if (value.includes('iPhone')) return 'Iphone'
  if (value.includes('iPad')) return 'iPad'
  if (value.includes('Android')) return 'Android'
  if (value.includes('YaBrowser/')) return 'Yandex Browser'
  if (value.includes('Edg/')) return 'Edge'
  if (value.includes('OPR/') || value.includes('Opera')) return 'Opera'
  if (value.includes('Firefox/')) return 'Firefox'
  if (value.includes('Chrome/')) return 'Chrome'
  if (value.includes('Safari/') && !value.includes('Chrome/')) return 'Safari'

  return value.slice(0, 80)
}

function formatClientDateTime(value) {
  if (!value) return ''

  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return ''

  return date.toLocaleString()
}

function buildShortMarkdown(row) {
  const short = row.short || row.short_url || ''
  const anchor = row.link || row.raw?.link || row.raw?.meta?.link || getLatestActionDetail(row, 'link') || row.anchor || row.title || short
  const text = buildInlineText([
    getRowPre(row),
    anchor,
    getRowPost(row)
  ])

  if (!short) return text

  return buildInlineText([
    getRowPre(row),
    `[${escapeMarkdownLinkText(anchor)}](${escapeMarkdownUrl(short)})`,
    getRowPost(row)
  ])
}

function buildInlineText(parts) {
  return parts.filter(Boolean).join(' ').replace(/\s+/g, ' ').trim()
}

function getRowPre(row) {
  return row.pre || row.raw?.pre || row.raw?.meta?.pre || getLatestActionDetail(row, 'pre') || ''
}

function getRowPost(row) {
  return row.post || row.raw?.post || row.raw?.meta?.post || getLatestActionDetail(row, 'post') || ''
}

function getLatestActionDetail(row, key) {
  const actions = getActions(row)
      .filter(action => action.details?.[key])
      .sort((a, b) => new Date(b.date || 0) - new Date(a.date || 0))

  return actions[0]?.details?.[key] || ''
}

function getActions(row) {
  const actions = row.actions || row.raw?.actions || []
  return Array.isArray(actions) ? actions : []
}

function escapeMarkdownLinkText(value) {
  return String(value || '').replace(/([\\[\]])/g, '\\$1')
}

function escapeMarkdownUrl(value) {
  return String(value || '').replace(/\)/g, '%29')
}

function extractEmails(values) {
  if (!Array.isArray(values)) return []

  return values
      .map(extractEmail)
      .filter(Boolean)
}

function extractEmail(value) {
  const text = String(value || '')
  const match = text.match(/<([^>]+)>/)
  if (match?.[1]) return match[1].trim()

  const plain = text.match(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/i)
  return plain?.[0] || ''
}

function describeRow(row) {
  return {
    key: getRowKey(row),
    publication: getRowPublication(row),
    token: getRowToken(row),
    type: getRowType(row),
    shortIds: getRowShortIds(row),
    short_url: row.short_url || row.short || '',
    link: row.link || '',
    date: row.date || ''
  }
}

function describeEvent(event) {
  return {
    ts: getEventDate(event),
    event: getEventName(event),
    publication: getEventPublication(event),
    token: getEventToken(event),
    uid: event.uid || '',
    shortIds: getEventShortIds(event),
    deviceKey: event.device_guess?.key || ''
  }
}

function debugReport(label, payload) {
  try {
    if (globalThis.localStorage?.getItem(DEBUG_REPORTS_KEY) !== '1') return
    console.debug(`[uportal-report] ${label}`, payload)
  } catch {
    // Debug logging must not affect report rendering.
  }
}

export { useLinkReport }
export default useLinkReport
