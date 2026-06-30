<template>
  <n-space vertical size="large">
    <div
        ref="activityFilterDockRef"
        class="activity-filter-dock"
        :style="activityFilterDockStyle"
    >
      <div
          ref="activityFilterPanelRef"
          class="activity-filter-panel"
          :class="{ 'is-fixed': activityFilterFixed }"
          :style="activityFilterPanelStyle"
      >
        <n-card>
          <div class="activity-filter-bar">
          <n-button
              circle
              quaternary
              class="activity-refresh-button"
              :loading="loading"
              :title="statsCaps.refresh"
              @click="applyFilters"
          >
            <template #icon>
              <RefreshCw :size="15" :stroke-width="1.8" />
            </template>
          </n-button>
          <n-input
              v-model:value="filters.publication_id"
              clearable
              placeholder="publication_id"
          />
          <n-input
              v-model:value="filters.token"
              clearable
              placeholder="token"
          />
          <n-input
              v-model:value="filters.uid"
              clearable
              placeholder="uid"
          />
          <n-select
              v-model:value="filters.events"
              multiple
              clearable
              :placeholder="statsCaps.events"
              :options="eventOptions"
              :render-tag="renderEventSelectTag"
          />
          <n-select
              v-model:value="filters.linkTypes"
              multiple
              clearable
              :placeholder="statsCaps.linkTypes"
              :options="linkTypeOptions"
              :render-tag="renderLinkTypeSelectTag"
          />
          </div>
        </n-card>
      </div>
    </div>

    <n-grid :cols="5" :x-gap="16">
      <n-card>
        <n-statistic :label="statsCaps.total" :value="activityRows.length" />
      </n-card>

      <n-card>
        <n-statistic label="open" :value="countByEvent.open || 0" />
      </n-card>

      <n-card>
        <n-statistic label="click" :value="countByEvent.click || 0" />
      </n-card>

      <n-card>
        <n-statistic label="download" :value="countByEvent.download || 0" />
      </n-card>

      <n-card>
        <n-statistic label="content" :value="countByEvent.content || 0" />
      </n-card>
    </n-grid>

    <n-data-table
        :columns="columns"
        :data="activityRows"
        :pagination="tablePagination"
        :remote="true"
        :loading="loading"
        :row-key="activityRowKey"
        :expanded-row-keys="expandedRowKeys"
        :row-props="activityRowProps"
        @update:expanded-row-keys="expandedRowKeys = $event"
        @update:sorter="handleSorter"
    />
  </n-space>
</template>

<script setup>
import { computed, h, nextTick, onBeforeUnmount, onMounted, reactive, ref, watch } from 'vue'
import { useStore } from 'vuex'
import { NIcon, NTag, NTooltip, useMessage } from 'naive-ui'
import { CopyOutline } from '@vicons/ionicons5'
import { RefreshCw } from 'lucide-vue-next'
import { activityList } from '../api/uportalApi'
import { formatCaption, getCaptions } from '../captions'
import { normalizeServerUrl } from '../store'

const store = useStore()
const message = useMessage()
const statsCaps = getCaptions('statistics')

const loading = ref(false)
const expandedRowKeys = ref([])
const tsSortOrder = ref('descend')
const activityFilterDockRef = ref(null)
const activityFilterPanelRef = ref(null)
const activityFilterFixed = ref(false)
const activityFilterDockStyle = reactive({})
const activityFilterPanelStyle = reactive({})
const ACTIVITY_GROUP_WINDOW_MS = 30000
const FILTER_LOAD_DELAY_MS = 1400
const activityPageSizes = [10, 20, 50, 100]
let filterLoadTimer = null
let activityFilterResizeObserver = null
let activityFilterScrollParents = []

const filters = reactive({
  publication_id: '',
  token: '',
  uid: '',
  events: [],
  linkTypes: [],
  page: 1,
  limit: 50
})

applyStatisticsQueryToFilters()

const eventOptions = [
  'open',
  'click',
  'page_view',
  'content',
  'pixel',
  'download'
].map(value => ({ label: value, value }))

const linkTypeOptions = [
  { label: statsCaps.linkTypesMap.redirect.title, value: 'redirect' },
  { label: statsCaps.linkTypesMap.download.title, value: 'download' },
  { label: statsCaps.linkTypesMap.page.title, value: 'page' },
  { label: statsCaps.linkTypesMap.pixel.title, value: 'pixel' }
]

const activity = computed(() => store.state.activity)

const sortedActivity = computed(() => {
  const direction = tsSortOrder.value === 'ascend' ? 1 : -1

  return [...groupActivityItems(activity.value)].sort((left, right) => (
      getEventTime(left) - getEventTime(right)
  ) * direction)
})

const activityRows = computed(() => sortedActivity.value.map((item, index) => ({
  ...item,
  _rowKey: [
    item.file?.name || '',
    item.ts || item.created_at || '',
    item.event || '',
    item.publication || item.publication_id || '',
    item.token || '',
    item.uid || '',
    index
  ].join(':')
})))

const countByEvent = computed(() => {
  const result = {}

  for (const item of activity.value) {
    const event = item.event || 'unknown'
    result[event] = (result[event] || 0) + 1
  }

  return result
})

onMounted(() => {
  if (!activity.value.length) {
    load()
  }
  setupActivityFixedFilter()
})

onBeforeUnmount(() => {
  clearFilterLoadTimer()
  teardownActivityFixedFilter()
})

watch(
    () => [
      filters.publication_id,
      filters.token,
      filters.uid,
      filters.events.join(','),
      filters.linkTypes.join(',')
    ],
    () => scheduleFilterLoad()
)

const pager = computed(() => store.state.activityPager)
const activityPageSizeOptions = computed(() => {
  const total = pager.value.total || 0

  return activityPageSizes.map(value => ({
    label: total ? `${value}/${total}` : String(value),
    value
  }))
})

const tablePagination = computed(() => ({
  page: pager.value.page,
  pageSize: pager.value.limit,
  itemCount: pager.value.total,
  showSizePicker: true,
  pageSizes: activityPageSizeOptions.value,
  onChange: async (page) => {
    filters.page = page
    updateStatisticsRouteQuery()
    await load()
  },
  onUpdatePageSize: async (pageSize) => {
    filters.limit = pageSize
    filters.page = 1
    updateStatisticsRouteQuery()
    await load()
  }
}))

const columns = computed(() => [
  {
    type: 'expand',
    renderExpand(row) {
      return renderActivityDetails(row)
    }
  },
  {
    title: () => headerTooltip(statsCaps.columns.eventDate, statsCaps.columns.eventDateTip),
    key: 'ts',
    sorter: true,
    sortOrder: tsSortOrder.value,
    width: 190,
    render(row) {
      return h(NTooltip, { trigger: 'hover', placement: 'right' }, {
        trigger: () => h('span', { class: 'mono activity-date' }, formatDate(getEventDate(row))),
        default: () => renderDateTooltip(row)
      })
    }
  },
  {
    title: () => headerTooltip(statsCaps.columns.type, statsCaps.columns.typeTip),
    key: 'link_type',
    width: 76,
    render(row) {
      return renderLinkTypeBadge(row)
    }
  },
  {
    title: () => headerTooltip(statsCaps.columns.preAnchorPost, statsCaps.columns.preAnchorPostTip),
    key: 'anchor',
    minWidth: 260,
    render(row) {
      const meta = row.meta || {}
      return copyCell({
        text: buildAnchorText(row),
        copy: buildActivityMarkdown(row)
      })
    }
  },
  {
    title: () => headerTooltip(statsCaps.columns.publication, statsCaps.columns.publicationTip),
    key: 'publication',
    minWidth: 150,
    render(row) {
      const value = row.publication || row.publication_id || '—'
      return copyCell({ text: value, copy: value, mono: true })
    }
  },
  {
    title: () => headerTooltip(statsCaps.columns.token, statsCaps.columns.tokenTip),
    key: 'token',
    minWidth: 140,
    render(row) {
      const value = row.token || '—'
      return copyCell({ text: value, copy: value, mono: true })
    }
  },
  {
    title: () => headerTooltip(statsCaps.columns.uid, statsCaps.columns.uidTip),
    key: 'uid',
    minWidth: 130,
    render(row) {
      const value = row.uid || '—'
      return copyCell({ text: value, copy: value, mono: true })
    }
  }
])

function handleSorter(sorter) {
  if (!sorter || sorter.columnKey !== 'ts') {
    tsSortOrder.value = 'descend'
  } else {
    tsSortOrder.value = normalizeDateSortOrder(sorter.order)
  }

  filters.page = 1
  expandedRowKeys.value = []
  updateStatisticsRouteQuery()
  load({ notify: false })
}

function applyFilters({ notify = true } = {}) {
  clearFilterLoadTimer()
  filters.page = 1
  expandedRowKeys.value = []
  updateStatisticsRouteQuery()
  load({ notify })
}

function scheduleFilterLoad() {
  clearFilterLoadTimer()
  filterLoadTimer = window.setTimeout(() => {
    updateStatisticsRouteQuery()
    applyFilters({ notify: false })
  }, FILTER_LOAD_DELAY_MS)
}

function clearFilterLoadTimer() {
  if (!filterLoadTimer) return
  window.clearTimeout(filterLoadTimer)
  filterLoadTimer = null
}

function setupActivityFixedFilter() {
  nextTick(() => {
    updateActivityFixedFilter()
    window.addEventListener('scroll', updateActivityFixedFilter, { passive: true })
    document.addEventListener('scroll', updateActivityFixedFilter, { passive: true, capture: true })
    window.addEventListener('resize', updateActivityFixedFilter)
    activityFilterScrollParents = getActivityFilterScrollParents(activityFilterDockRef.value)
    activityFilterScrollParents.forEach((element) => {
      element.addEventListener('scroll', updateActivityFixedFilter, { passive: true })
    })

    if (typeof ResizeObserver !== 'undefined') {
      activityFilterResizeObserver = new ResizeObserver(updateActivityFixedFilter)
      if (activityFilterDockRef.value) activityFilterResizeObserver.observe(activityFilterDockRef.value)
      if (activityFilterPanelRef.value) activityFilterResizeObserver.observe(activityFilterPanelRef.value)
    }
  })
}

function teardownActivityFixedFilter() {
  window.removeEventListener('scroll', updateActivityFixedFilter)
  document.removeEventListener('scroll', updateActivityFixedFilter, { capture: true })
  window.removeEventListener('resize', updateActivityFixedFilter)
  activityFilterScrollParents.forEach((element) => {
    element.removeEventListener('scroll', updateActivityFixedFilter)
  })
  activityFilterScrollParents = []
  activityFilterResizeObserver?.disconnect()
  activityFilterResizeObserver = null
}

function updateActivityFixedFilter() {
  const dock = activityFilterDockRef.value
  const panel = activityFilterPanelRef.value
  if (!dock || !panel) return

  const rect = dock.getBoundingClientRect()
  const shouldFix = rect.top <= 0
  const height = panel.offsetHeight

  activityFilterFixed.value = shouldFix

  if (shouldFix) {
    activityFilterDockStyle.height = `${height}px`
    activityFilterPanelStyle.position = 'fixed'
    activityFilterPanelStyle.top = '0'
    activityFilterPanelStyle.left = `${rect.left}px`
    activityFilterPanelStyle.width = `${rect.width}px`
    activityFilterPanelStyle.zIndex = '100'
    return
  }

  activityFilterDockStyle.height = ''
  activityFilterPanelStyle.position = ''
  activityFilterPanelStyle.top = ''
  activityFilterPanelStyle.left = ''
  activityFilterPanelStyle.width = ''
  activityFilterPanelStyle.zIndex = ''
}

function getActivityFilterScrollParents(element) {
  const parents = []
  let current = element?.parentElement || null

  while (current && current !== document.body && current !== document.documentElement) {
    const style = window.getComputedStyle(current)
    const overflow = `${style.overflow} ${style.overflowY}`

    if (/(auto|scroll|overlay)/.test(overflow)) {
      parents.push(current)
    }

    current = current.parentElement
  }

  return parents
}

function activityRowKey(row) {
  return row._rowKey
}

function activityRowProps(row) {
  return {
    style: 'cursor: pointer;',
    onClick: (event) => {
      if (shouldIgnoreActivityRowClick(event)) return
      toggleExpandedRow(row)
    }
  }
}

function shouldIgnoreActivityRowClick(event) {
  const target = event.target
  if (!target?.closest) return false

  return !!target.closest([
    '.n-data-table-expand-trigger',
    '.activity-copy-button',
    '.activity-event-cloud',
    '.activity-device-guess',
    'button',
    'a',
    'input',
    'textarea',
    'select'
  ].join(','))
}

function toggleExpandedRow(row) {
  const key = activityRowKey(row)
  expandedRowKeys.value = expandedRowKeys.value.includes(key)
      ? expandedRowKeys.value.filter(item => item !== key)
      : [...expandedRowKeys.value, key]
}

function headerTooltip(label, description) {
  return h(NTooltip, { trigger: 'hover' }, {
    trigger: () => h('span', { class: 'activity-header-title' }, label),
    default: () => description
  })
}

function renderDateTooltip(row) {
  const meta = row.meta || {}

  return h('div', { class: 'activity-date-tooltip' }, [
    h('div', [
      h('strong', statsCaps.details.publishedAt),
      h('span', formatDate(meta.published_at || row.published_at))
    ]),
    h('div', [
      h('strong', statsCaps.details.subject),
      h('span', meta.subj || row.subj || '—')
    ]),
    h('div', [
      h('strong', statsCaps.details.recipients),
      h('span', formatMails(meta.mails || row.mails))
    ])
  ])
}

function copyCell({ text, copy, mono = false, className = '', textClassName = '' }) {
  const displayText = text || '—'
  const copyValue = copy || displayText

  return h('span', {
    class: ['activity-copy-cell', mono ? 'mono' : '', className].filter(Boolean).join(' ')
  }, [
    h(NTooltip, { trigger: 'hover' }, {
      trigger: () => h('button', {
        type: 'button',
        class: 'activity-copy-button',
        onClick: (event) => {
          event.stopPropagation()
          copyText(copyValue)
        }
      }, [
        h(NIcon, { size: 14 }, { default: () => h(CopyOutline) })
      ]),
      default: () => formatCaption(statsCaps.copy || 'Copy: {value}', { value: copyValue })
    }),
    h('span', { class: ['activity-copy-text', textClassName].filter(Boolean).join(' ') }, displayText)
  ])
}

function renderActivityDetails(row) {
  const meta = row.meta || {}
  const subject = meta.subj || row.subj || '—'
  const mails = normalizeMails(meta.mails || row.mails)

  return h('div', { class: 'activity-details-row' }, [
    h(NTooltip, { trigger: 'hover' }, {
      trigger: () => h('span', { class: 'mono activity-published-date' }, formatDate(meta.published_at || row.published_at)),
      default: () => statsCaps.details.publishedAtTooltip
    }),
    renderRelatedEvents(row),
    renderDeviceGuess(row),
    h(NTooltip, { trigger: 'hover' }, {
      trigger: () => copyCell({
        text: subject,
        copy: subject,
        className: 'activity-subject-copy',
        textClassName: 'activity-subject-fade'
      }),
      default: () => subject
    }),
    h('div', { class: 'activity-mails-column' }, mails.map(mail =>
        copyCell({ text: mail, copy: mail, className: 'activity-mail-item' })
    ))
  ])
}

function renderRelatedEvents(row) {
  const events = row._events?.length ? row._events : [row]
  const isComplete = isActivityEventChainComplete(row, events)

  return h(NTooltip, { trigger: 'hover' }, {
    trigger: () => h('div', {
      class: [
        'activity-event-cloud',
        isComplete ? 'is-complete' : 'is-pending'
      ].join(' '),
      onClick: (event) => {
        event.stopPropagation()
        copyText(buildActivityLog(row))
      }
    }, getCollapsedEventBadges(events).map(item => renderEventBadge(item.event, item.count))),
    default: () => renderEventsTooltip(events)
  })
}

function renderDeviceGuess(row) {
  const guess = getPrimaryDeviceGuess(row)

  if (!guess?.key) {
    return h('span', { class: 'activity-device-guess is-unknown' }, statsCaps.device.unknownBadge)
  }

  const className = `activity-device-guess is-${guess.confidence || 'unknown'}`
  const label = guess.confidence === 'high'
      ? statsCaps.device.highBadge
      : guess.confidence === 'low'
          ? statsCaps.device.lowBadge
          : statsCaps.device.unknownBadge

  return h(NTooltip, { trigger: 'hover' }, {
    trigger: () => h('span', {
      class: className,
      onClick: (event) => {
        event.stopPropagation()
        copyText(buildDeviceGuessText(row))
      }
    }, label),
    default: () => renderDeviceGuessTooltip(row)
  })
}

function renderEventBadge(event, count = 1) {
  const info = getEventInfo(event)

  return h('span', {
    class: `activity-event-circle ${info.class}`
  }, count > 1 ? `${info.label}×${count}` : info.label)
}

function getCollapsedEventBadges(events) {
  const ordered = []
  const indexByEvent = new Map()

  for (const item of events) {
    const event = item.event || 'unknown'
    const existingIndex = indexByEvent.get(event)

    if (existingIndex !== undefined) {
      ordered[existingIndex].count += 1
      continue
    }

    indexByEvent.set(event, ordered.length)
    ordered.push({ event, count: 1 })
  }

  return ordered
}

function isActivityEventChainComplete(row, events) {
  const type = row.meta?.type || row.type || ''
  const eventNames = new Set(events.map(item => item.event))

  if (type === 'redirect') return eventNames.has('click')
  if (type === 'download') return eventNames.has('download')
  if (type === 'page') return eventNames.has('content')
  if (type === 'pixel') return eventNames.has('pixel')

  return events.length > 0
}

function renderLinkTypeBadge(row) {
  const meta = row.meta || {}
  const info = getLinkTypeInfo(meta.type || row.type)

  return h(NTooltip, { trigger: 'hover' }, {
    trigger: () => h(NTag, {
      size: 'small',
      class: 'activity-publication-type-tag'
    }, {
      default: () => meta.type || row.type || '—'
    }),
    default: () => info.title
  })
}

function renderEventSelectTag({ option, handleClose }) {
  const info = getEventInfo(option.value)
  return renderCompactSelectTag(info.label, handleClose)
}

function renderLinkTypeSelectTag({ option, handleClose }) {
  const info = getLinkTypeInfo(option.value)
  return renderCompactSelectTag(info.code, handleClose)
}

function renderCompactSelectTag(label, handleClose) {
  return h(NTag, {
    size: 'small',
    closable: true,
    round: true,
    class: 'activity-select-compact-tag',
    onClose: (event) => {
      event.stopPropagation()
      handleClose()
    }
  }, {
    default: () => label
  })
}

function renderEventsTooltip(events) {
  const counts = events.reduce((acc, item) => {
    const event = item.event || 'unknown'
    acc[event] = (acc[event] || 0) + 1
    return acc
  }, {})

  return h('div', { class: 'activity-events-tooltip' }, [
    ...Object.entries(counts).map(([event, count]) => {
      const info = getEventInfo(event)
      return h('div', [
        h('span', { class: `activity-event-dot ${info.class}` }, info.label),
        h('span', `${info.title}: ${count}`)
      ])
    }),
    h('div', { class: 'activity-device-tooltip-line' }, buildDeviceGuessText({ _events: events }))
  ])
}

function buildAnchorText(row) {
  const meta = row.meta || {}
  return [meta.pre, meta.link, meta.post].filter(Boolean).join(' ').replace(/\s+/g, ' ').trim() || '—'
}

function buildActivityMarkdown(row) {
  const meta = row.meta || {}
  const anchor = meta.link || row.link || buildAnchorText(row)
  const short = getShortUrl(row)
  const middle = short
      ? `[${escapeMarkdownLinkText(anchor)}](${escapeMarkdownUrl(short)})`
      : anchor

  return [
    meta.pre || '',
    middle,
    meta.post || ''
  ].filter(Boolean).join(' ').replace(/\s+/g, ' ').trim()
}

function buildActivityLog(row) {
  const meta = row.meta || {}
  const events = row._events?.length ? row._events : [row]
  const eventText = events.map(item => {
    const info = getEventInfo(item.event)
    return `${formatDate(item.ts || item.created_at)} ${info.label} ${info.title}`
  }).join('\n')

  return [
    formatCaption(statsCaps.log.eventDate, { value: formatDate(getEventDate(row)) }),
    formatCaption(statsCaps.log.publishedAt, { value: formatDate(meta.published_at || row.published_at) }),
    formatCaption(statsCaps.log.linkType, { value: getLinkTypeInfo(meta.type || row.type).title }),
    formatCaption(statsCaps.log.publication, { value: row.publication || row.publication_id || '—' }),
    formatCaption(statsCaps.log.token, { value: row.token || '—' }),
    `UID: ${row.uid || '—'}`,
    formatCaption(statsCaps.log.device, { value: buildDeviceGuessText(row) }),
    formatCaption(statsCaps.log.subject, { value: meta.subj || row.subj || '—' }),
    formatCaption(statsCaps.log.recipients, { value: formatMails(meta.mails || row.mails) }),
    formatCaption(statsCaps.log.link, { value: buildAnchorText(row) }),
    statsCaps.log.events,
    eventText || '—'
  ].join('\n')
}

function getPrimaryDeviceGuess(row) {
  const events = row._events?.length ? row._events : [row]
  return events.find(item => item.device_guess?.key)?.device_guess || row.device_guess || null
}

function buildDeviceGuessText(row) {
  const guess = getPrimaryDeviceGuess(row)
  if (!guess?.key) return statsCaps.device.unavailable

  const confidence = formatDeviceGuessConfidence(guess.confidence)
  const source = formatDeviceGuessSource(guess.source)

  return [
    `${confidence}, ${source}`,
    `key: ${guess.key}`,
    guess.network_key ? `network: ${guess.network_key}` : '',
    guess.ip_prefix ? `ip: ${guess.ip_prefix}` : '',
    guess.ua ? `ua: ${guess.ua}` : '',
    guess.language ? `lang: ${guess.language}` : ''
  ].filter(Boolean).join('; ')
}

function renderDeviceGuessTooltip(row) {
  const guess = getPrimaryDeviceGuess(row)
  if (!guess?.key) return statsCaps.device.notEnough

  return h('div', { class: 'activity-device-tooltip' }, [
    h('div', [
      h('strong', statsCaps.details.device),
      h('span', formatDeviceGuessConfidence(guess.confidence))
    ]),
    h('div', [
      h('strong', statsCaps.details.reason),
      h('span', guess.hint || formatDeviceGuessSource(guess.source))
    ]),
    h('div', [
      h('strong', statsCaps.details.key),
      h('span', { class: 'mono' }, guess.key)
    ]),
    h('div', [
      h('strong', statsCaps.details.networkKey),
      h('span', { class: 'mono' }, guess.network_key || '—')
    ]),
    h('div', [
      h('strong', 'IP prefix: '),
      h('span', guess.ip_prefix || '—')
    ]),
    h('div', [
      h('strong', 'UA: '),
      h('span', guess.ua || '—')
    ])
  ])
}

function formatDeviceGuessConfidence(value) {
  if (value === 'high') return statsCaps.device.high
  if (value === 'low') return statsCaps.device.low
  return statsCaps.device.unknownConfidence
}

function formatDeviceGuessSource(value) {
  if (value === 'cookie') return statsCaps.device.cookie
  if (value === 'weak') return 'IP prefix + User-Agent'
  if (value === 'missing') return statsCaps.device.missing
  return value || statsCaps.device.unknownSource
}

function getShortUrl(row) {
  const meta = row.meta || {}
  const short = row.short_url || row.shortlink || row.short || row.url || meta.short_url || meta.shortlink || meta.short || meta.url || ''
  if (!short) {
    const token = row.token || ''
    if (!token) return ''

    const serverUrl = normalizeServerUrl(store.state.serverUrl)
    return `${serverUrl}/s/${token}`
  }

  if (/^https?:\/\//.test(short)) return short

  const serverUrl = normalizeServerUrl(store.state.serverUrl)
  return `${serverUrl}/s/${short}`
}

function escapeMarkdownLinkText(value) {
  return String(value || '').replace(/([\\[\]])/g, '\\$1')
}

function escapeMarkdownUrl(value) {
  return String(value || '').replace(/\)/g, '%29')
}

async function copyText(value) {
  const text = String(value || '')
  if (!text || text === '—') return

  await navigator.clipboard.writeText(text)
  message.success(statsCaps.messages.copied)
}

function getLinkTypeInfo(type) {
  const map = {
    redirect: { ...statsCaps.linkTypesMap.redirect, class: 'is-redirect' },
    download: { ...statsCaps.linkTypesMap.download, class: 'is-download' },
    page: { ...statsCaps.linkTypesMap.page, class: 'is-page' },
    pixel: { ...statsCaps.linkTypesMap.pixel, class: 'is-pixel' }
  }

  const fallback = String(type || '?').slice(0, 2).toUpperCase()
  return map[type] || { code: fallback, label: fallback, title: type || statsCaps.linkTypesMap.unknown, class: 'is-unknown' }
}

function getEventInfo(event) {
  const map = {
    open: { ...statsCaps.eventsMap.open, class: 'is-open' },
    click: { ...statsCaps.eventsMap.click, class: 'is-click' },
    page_view: { ...statsCaps.eventsMap.page_view, class: 'is-page' },
    content: { ...statsCaps.eventsMap.content, class: 'is-content' },
    pixel: { ...statsCaps.eventsMap.pixel, class: 'is-pixel' },
    download: { ...statsCaps.eventsMap.download, class: 'is-download' }
  }

  return map[event] || { label: String(event || '?').slice(0, 2).toUpperCase(), title: event || statsCaps.eventsMap.unknown, class: 'is-unknown' }
}

function formatMails(value) {
  if (Array.isArray(value)) return value.length ? value.join(', ') : '—'
  return value || '—'
}

function normalizeMails(value) {
  if (Array.isArray(value)) return value.length ? value : ['—']
  if (!value) return ['—']
  return String(value).split(/[,;\n]+/).map(item => item.trim()).filter(Boolean)
}

function formatDate(value) {
  if (!value) return '—'

  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return '—'

  return date.toLocaleString()
}

function getEventTime(row) {
  const date = new Date(getEventDate(row) || 0)
  return Number.isNaN(date.getTime()) ? 0 : date.getTime()
}

function getEventDate(row) {
  return row._eventTs || row.ts || row.created_at
}

function groupActivityItems(items) {
  const ordered = [...items].sort((left, right) => getRawEventTime(left) - getRawEventTime(right))
  const groups = []
  const activeGroups = new Map()

  for (const item of ordered) {
    const identity = getActivityIdentity(item)
    const time = getRawEventTime(item)
    const previousGroup = activeGroups.get(identity)

    if (previousGroup && time - previousGroup._lastEventTime <= ACTIVITY_GROUP_WINDOW_MS) {
      previousGroup._events.push(item)
      previousGroup._lastEventTime = time
      previousGroup._eventTs = item.ts || item.created_at || previousGroup._eventTs
      continue
    }

    const group = {
      ...item,
      _events: [item],
      _eventTs: item.ts || item.created_at,
      _firstEventTime: time,
      _lastEventTime: time
    }

    groups.push(group)
    activeGroups.set(identity, group)
  }

  return groups
}

function getActivityIdentity(row) {
  return [
    row.publication || row.publication_id || '',
    row.token || '',
    getActivityVisitorGroupKey(row)
  ].join(':')
}

function getActivityVisitorGroupKey(row) {
  const request = row.request || {}
  const softDevice = [
    request.ua_normalized || request.ua || row.device_guess?.ua || '',
    request.language_normalized || request.accept_language || row.device_guess?.language || ''
  ].join('|').trim()

  if (softDevice.replace('|', '')) return `soft:${softDevice}`

  if (row.uid && row.uid !== 'nouid') return `uid:${row.uid}`
  if (row.device_guess?.key) return `guess:${row.device_guess.key}`

  return 'unknown'
}

function getRawEventTime(row) {
  const date = new Date(row.ts || row.created_at || 0)
  return Number.isNaN(date.getTime()) ? 0 : date.getTime()
}

function extractPaged(payload) {
  const fallback = {
    items: [],
    page: filters.page,
    limit: filters.limit,
    total: 0,
    has_next: false
  }

  if (Array.isArray(payload?.message) && payload.message[0]?.items) {
    return payload.message[0]
  }

  if (Array.isArray(payload?.items)) {
    return payload
  }

  return fallback
}


async function load({ notify = true } = {}) {
  updateStatisticsRouteQuery()
  loading.value = true

  const body = {
    page: filters.page,
    limit: filters.limit,
    sort_order: getActivitySortOrderParam()
  }

  if (filters.publication_id) body.publication_id = filters.publication_id
  if (filters.token) body.token = filters.token
  if (filters.uid) body.uid = filters.uid
  if (filters.events.length) body.event = filters.events.join(',')
  if (filters.linkTypes.length) body.type = filters.linkTypes.join(',')

  try {
    const data = await activityList(body)
    const paged = extractPaged(data)
    store.commit('setActivity', paged)
    if (notify) {
      message.success(formatCaption(statsCaps.messages.loaded, { count: paged.items.length }))
    }
  } catch (e) {
    message.error(statsCaps.messages.loadError)
    console.error(e)
  } finally {
    loading.value = false
  }
}

function applyStatisticsQueryToFilters() {
  const params = new URLSearchParams(window.location.search)

  filters.publication_id = params.get('pub') || ''
  filters.token = params.get('tok') || ''
  filters.uid = params.get('uid') || ''
  filters.events = splitRouteList(params.get('ev'))
  filters.linkTypes = splitRouteList(params.get('type'))
  filters.page = normalizePositiveInteger(params.get('p'), filters.page)
  filters.limit = normalizeAllowedPageSize(params.get('n'), filters.limit)
  tsSortOrder.value = normalizeDateSortOrder(params.get('sort') === 'asc' ? 'ascend' : 'descend')
}

function updateStatisticsRouteQuery() {
  if (!window.location.pathname.startsWith('/ui/stats')) return

  const params = new URLSearchParams()

  if (filters.publication_id) params.set('pub', filters.publication_id)
  if (filters.token) params.set('tok', filters.token)
  if (filters.uid) params.set('uid', filters.uid)
  if (filters.events.length) params.set('ev', filters.events.join(','))
  if (filters.linkTypes.length) params.set('type', filters.linkTypes.join(','))
  if (filters.page > 1) params.set('p', String(filters.page))
  if (filters.limit !== 50) params.set('n', String(filters.limit))
  if (tsSortOrder.value === 'ascend') params.set('sort', 'asc')

  const queryString = params.toString()
  const nextUrl = `${window.location.pathname}${queryString ? `?${queryString}` : ''}${window.location.hash}`

  if (nextUrl !== `${window.location.pathname}${window.location.search}${window.location.hash}`) {
    window.history.replaceState({}, '', nextUrl)
  }
}

function splitRouteList(value) {
  return String(value || '')
      .split(',')
      .map(item => item.trim())
      .filter(Boolean)
}

function normalizePositiveInteger(value, fallback) {
  const number = Number(value)
  if (!Number.isFinite(number) || number < 1) return fallback
  return Math.trunc(number)
}

function normalizeAllowedPageSize(value, fallback) {
  const number = normalizePositiveInteger(value, fallback)
  return activityPageSizes.includes(number) ? number : fallback
}

function normalizeDateSortOrder(value) {
  return value === 'ascend' ? 'ascend' : 'descend'
}

function getActivitySortOrderParam() {
  return tsSortOrder.value === 'ascend' ? 'asc' : 'desc'
}
</script>

<style>
.activity-filter-panel.is-fixed {
  background: #fff;
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.06);
}

.activity-filter-bar {
  display: grid;
  grid-template-columns: 28px 275px 207px 275px minmax(120px, 1fr) minmax(120px, 1fr);
  gap: 12px;
  align-items: center;
}

.activity-refresh-button {
  --n-border: 0 !important;
  --n-border-hover: 0 !important;
  --n-border-pressed: 0 !important;
  --n-border-focus: 0 !important;
  --n-color: transparent !important;
  --n-color-hover: transparent !important;
  --n-color-pressed: transparent !important;
  --n-color-focus: transparent !important;
  color: rgba(31, 34, 37, 0.82);
}

.activity-refresh-button:hover {
  color: #2080f0;
}

.activity-date {
  cursor: help;
  text-decoration: underline dotted;
}

.activity-header-title {
  cursor: help;
  text-decoration: underline dotted;
  text-underline-offset: 3px;
}

.activity-date-tooltip {
  max-width: 360px;
  line-height: 1.5;
}

.activity-details-row {
  display: grid;
  grid-template-columns: 170px max-content 28px minmax(0, 1fr) 168px;
  gap: 10px;
  align-items: center;
  min-width: 0;
  padding: 8px 12px 8px 48px;
  background: rgba(128, 128, 128, 0.035);
  border-radius: 4px;
}

.activity-published-date {
  cursor: help;
  color: rgba(31, 34, 37, 0.78);
}

.activity-copy-cell {
  display: flex;
  align-items: center;
  width: 100%;
  min-width: 0;
  gap: 4px;
}

.activity-copy-text {
  flex: 1 1 auto;
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.activity-copy-button {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  flex: 0 0 auto;
  width: 16px;
  height: 16px;
  padding: 0;
  border: 0;
  color: rgba(31, 34, 37, 0.64);
  background: transparent;
  cursor: pointer;
  line-height: 1;
}

.activity-copy-button:hover {
  color: #2080f0;
  background: transparent;
}

.activity-select-compact-tag {
  --n-height: 20px;
  --n-padding: 0 6px;
  --n-font-size: 11px;
}

.activity-subject-fade {
  position: relative;
  display: block;
  flex: 1 1 auto;
  width: 100%;
  min-width: 0;
  overflow: hidden;
  white-space: nowrap;
  cursor: help;
}

.activity-subject-copy {
  width: 100%;
  min-width: 0;
}

.activity-subject-fade::after {
  position: absolute;
  top: 0;
  right: 0;
  bottom: 0;
  width: 42px;
  pointer-events: none;
  content: "";
  background: linear-gradient(90deg, rgba(255, 255, 255, 0), #fff 78%);
}

.activity-mails-column {
  display: flex;
  flex-direction: column;
  min-width: 0;
  gap: 2px;
  color: rgba(31, 34, 37, 0.78);
  font-size: 12px;
  line-height: 1.25;
}

.activity-mails-column .activity-copy-cell {
  width: 100%;
}

.activity-mail-item {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.activity-event-cloud {
  display: inline-flex;
  flex-wrap: wrap;
  gap: 4px;
  align-items: center;
  padding: 3px 5px;
  border-radius: 999px;
  cursor: help;
}

.activity-event-cloud.is-complete {
  background: rgba(24, 160, 88, 0.08);
}

.activity-event-cloud.is-pending {
  background: rgba(240, 160, 32, 0.1);
}

.activity-event-circle,
.activity-event-dot {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  flex: 0 0 auto;
  font-weight: 700;
}

.activity-event-circle {
  min-width: 12px;
  height: 18px;
  font-size: 10px;
  line-height: 1;
}

.activity-event-dot {
  width: 22px;
  height: 22px;
  margin-right: 8px;
  border-radius: 999px;
  font-size: 10px;
}

.activity-events-tooltip {
  display: grid;
  gap: 6px;
  line-height: 1.4;
}

.activity-device-guess {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 24px;
  height: 24px;
  border-radius: 999px;
  border: 1px solid rgba(224, 128, 32, 0.72);
  font-size: 10px;
  font-weight: 700;
  line-height: 1;
  cursor: help;
  background: rgba(240, 160, 32, 0.14);
}

.activity-device-guess.is-high {
  color: #1f7a4d;
}

.activity-device-guess.is-low {
  color: #b42318;
}

.activity-device-guess.is-unknown {
  color: rgba(31, 34, 37, 0.58);
}

.activity-device-tooltip,
.activity-device-tooltip-line {
  line-height: 1.45;
}

.activity-device-tooltip {
  display: grid;
  max-width: 520px;
  gap: 5px;
}

.activity-device-tooltip-line {
  max-width: 520px;
  padding-top: 4px;
  border-top: 1px solid rgba(128, 128, 128, 0.18);
  color: rgba(31, 34, 37, 0.72);
  font-size: 12px;
}

.activity-publication-type-tag {
  --n-height: 20px;
  --n-padding: 0 7px;
  --n-font-size: 11px;
}

.activity-event-circle.is-open,
.activity-event-dot.is-open {
  color: #1768a8;
}

.activity-event-circle.is-click,
.activity-event-dot.is-click {
  color: #1f7a4d;
}

.activity-event-circle.is-page,
.activity-event-dot.is-page {
  color: #8a5a00;
}

.activity-event-circle.is-content,
.activity-event-dot.is-content {
  color: #6750a4;
}

.activity-event-circle.is-pixel,
.activity-event-dot.is-pixel {
  color: #9b4d12;
}

.activity-event-circle.is-download,
.activity-event-dot.is-download {
  color: #b42318;
}

.activity-event-circle.is-unknown,
.activity-event-dot.is-unknown {
  color: rgba(31, 34, 37, 0.72);
}
</style>
