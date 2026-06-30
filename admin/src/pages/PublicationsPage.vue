<!--src/pages/PublicationsPage.vue-->
<template>
  <div class="app-page">
    <div class="page-header">
      <div>
        <h2>{{ pageCaps.title }}</h2>
        <div class="muted">
          {{ pageCaps.subtitle }}
        </div>
      </div>
    </div>

    <div
        ref="publicationsFilterDockRef"
        class="publications-filter-dock"
        :style="publicationsFilterDockStyle"
    >
      <div
          ref="publicationsFilterPanelRef"
          class="publications-filter-panel"
          :class="{ 'is-fixed': publicationsFilterFixed }"
          :style="publicationsFilterPanelStyle"
      >
        <n-card>
          <div class="publications-filter-bar">
          <n-form-item :label="pageCaps.searchLabel">
            <n-input
                v-model:value="filters.query"
                clearable
                :placeholder="pageCaps.searchPlaceholder"
                @keyup.enter="applyFilters"
            >
              <template #prefix>
                <n-button
                    circle
                    quaternary
                    size="small"
                    class="publications-refresh-button"
                    :loading="loading"
                    :title="tooltips.refresh"
                    @click.stop="load"
                >
                  <template #icon>
                    <n-icon>
                      <RefreshCw :size="15" :stroke-width="1.8" />
                    </n-icon>
                  </template>
                </n-button>
              </template>
            </n-input>
          </n-form-item>

          <n-form-item :label="pageCaps.dateRange">
            <n-date-picker
                v-model:value="filters.range"
                type="daterange"
                clearable
                style="width: 100%"
            />
          </n-form-item>

          <n-form-item :label="pageCaps.period" class="publications-period-unit">
            <n-select
                v-model:value="filters.periodUnit"
                :options="periodOptions"
            />
          </n-form-item>

          <n-form-item label=" " class="publications-pagination-item">
            <n-pagination
                v-if="linksPager.total > 0"
                :page="filters.page"
                :page-size="filters.limit"
                :item-count="linksPager.total"
                :page-sizes="publicationPageSizeOptions"
                show-size-picker
                class="publications-pagination"
                @update:page="handlePublicationPageChange"
                @update:page-size="handlePublicationPageSizeChange"
            />
          </n-form-item>

          <n-form-item label=" " class="publications-add-item">
            <n-button
                circle
                quaternary
                class="publications-add-button"
                :title="tooltips.addLink"
                @click="openCreate"
            >
              <template #icon>
                <n-icon>
                  <Plus :size="16" :stroke-width="1.8" />
                </n-icon>
              </template>
            </n-button>
          </n-form-item>
          </div>
        </n-card>
      </div>
    </div>

    <n-collapse v-model:expanded-names="expandedPeriodNames">
      <n-collapse-item
          v-for="period in periodGroups"
          :key="period.period"
          :name="period.period"
      >
        <template #header>
          <div class="period-collapse-header">
            <span>{{ period.period }}</span>
            <span class="period-collapse-count">{{ period.items.length }}</span>
          </div>
        </template>

        <n-data-table
            :columns="campaignColumns"
            :row-key="campaignRowKey"
            :row-class-name="campaignRowClassName"
            :data="period.items"
            :loading="loading"
            :pagination="false"
            :expanded-row-keys="getExpandedCampaignKeys(period.period)"
            @update:expanded-row-keys="keys => updateExpandedCampaignKeys(period.period, keys, period.items)"
        />
      </n-collapse-item>
    </n-collapse>

    <LinkEditorModal
        v-model:show="linkEditorVisible"
        :edit-draft="editingDraft"
    />

    <n-modal
        v-model:show="accessModalVisible"
        preset="card"
        :title="pageCaps.accessTitle"
        style="width: min(520px, calc(100vw - 32px))"
    >
      <n-space v-if="accessRow" vertical size="large">
        <div>
          <div class="mono">publication_id: {{ accessRow.publication_id }}</div>
          <div class="mono">token: {{ accessRow.token }}</div>
          <div class="mono">link: {{ getShortUrl(accessRow) || '—' }}</div>
          <div>{{ buildMarkdownText(accessRow) || '—' }}</div>
        </div>

        <n-form-item :label="pageCaps.password">
          <n-space vertical size="small" style="width: 100%">
            <n-tag :type="hasPassword(accessRow) ? 'warning' : 'default'" size="small">
              {{ hasPassword(accessRow) ? pageCaps.passwordSet : pageCaps.passwordUnset }}
            </n-tag>
            <n-input
                v-model:value="passwordForm.password"
                type="password"
                :placeholder="pageCaps.passwordPlaceholder"
                autocomplete="new-password"
                :input-props="{ autocomplete: 'new-password' }"
            />
            <n-button
                type="primary"
                size="small"
                :loading="passwordSaving"
                @click="savePassword"
            >
              {{ pageCaps.save }}
            </n-button>
          </n-space>
        </n-form-item>
      </n-space>
    </n-modal>
  </div>
</template>

<script setup>
import { CopyOutline } from '@vicons/ionicons5'
import { ExternalLink, FingerprintPattern, Lock, LockOpen, Plus, RefreshCw, Timer, Trash2 } from 'lucide-vue-next'
import { NIcon, NTooltip } from 'naive-ui'
import { computed, h, nextTick, onBeforeUnmount, onMounted, reactive, ref, watch } from 'vue'
import { useStore } from 'vuex'
import { normalizeServerUrl } from '../store'
import {
  NButton,
  NDatePicker,
  NDataTable,
  NFormItem,
  NInput,
  NInputNumber,
  NModal,
  NPagination,
  NPopover,
  NSpace,
  NTag,
  useMessage
} from 'naive-ui'

import LinkEditorModal from '../publications/LinkEditorModal.vue'
import useLinkReport from '../publications/useLinkReport'
import { deleteDraftAssetsForDraft } from '../services/draftAssetStore'
import { formatCaption, getCaptions } from '../captions'

const pageCaps = getCaptions('publications')
const columnLabels = pageCaps.columns
const captions = {
  timeSeconds: pageCaps.time.seconds,
  timeMinutes: pageCaps.time.minutes,
  timeHours: pageCaps.time.hours,
  timeDays: pageCaps.time.days,
  timeUnknown: pageCaps.time.unknown,
  ...pageCaps.messages
}

const tooltips = pageCaps.tooltips

const store = useStore()
const message = useMessage()

const { renderTypeBadge, loadLinkReport, loadPublicationLinkReports, reportCache } = useLinkReport(captions)

const loading = ref(false)
const linkEditorVisible = ref(false)
const editingDraft = ref(null)
const linkParamDrafts = reactive({})
const clicksPopoverShown = reactive({})
const freshPopoverShown = reactive({})
const delayPopoverShown = reactive({})
const expandedPeriodNames = ref([])
const expandedCampaignKeysByPeriod = reactive({})
const campaignReportsLoaded = reactive({})
const statusActionBusy = reactive({})
const periodPanelsInitialized = ref(false)
const publicationsFilterDockRef = ref(null)
const publicationsFilterPanelRef = ref(null)
const publicationsFilterFixed = ref(false)
const publicationsFilterDockStyle = reactive({})
const publicationsFilterPanelStyle = reactive({})
const accessModalVisible = ref(false)
const accessRow = ref(null)
const accessSaving = ref(false)
const passwordSaving = ref(false)
const passwordForm = reactive({
  password: ''
})
const PUBLICATIONS_FILTER_LOAD_DELAY_MS = 1400
let publicationFilterLoadTimer = null
let publicationsFilterResizeObserver = null
let publicationsFilterScrollParents = []

const filters = reactive({
  query: '',
  range: null,
  periodUnit: 'month',
  page: 1,
  limit: 25
})

const periodOptions = [
  { label: pageCaps.periods.day, value: 'day' },
  { label: pageCaps.periods.week, value: 'week' },
  { label: pageCaps.periods.month, value: 'month' },
  { label: pageCaps.periods.quarter, value: 'quarter' },
  { label: pageCaps.periods.year, value: 'year' }
]
const publicationPageSizes = [10, 25, 50, 100]

const links = computed(() => store.state.links || [])
const drafts = computed(() => store.state.drafts || [])
const linksPager = computed(() => store.state.linksPager || {})
const publicationPageSizeOptions = computed(() => {
  const total = linksPager.value.total || 0

  return publicationPageSizes.map(value => ({
    label: total ? `${value}/${total}` : String(value),
    value
  }))
})

applyPublicationQueryToFilters()

const allLinks = computed(() => [
  ...(filters.page === 1 ? drafts.value : []),
  ...links.value.map(normalizeLink)
])

const filteredLinks = computed(() => {
  return allLinks.value.filter((link) => {
    if (!link.draft_id) return true
    return matchesClientFilters(link)
  })
})

const periodGroups = computed(() => {
  const periods = new Map()
  const campaigns = groupToCampaigns(filteredLinks.value)

  for (const campaign of campaigns) {
    const period = buildPeriodLabel(campaign.date, filters.periodUnit)

    if (!periods.has(period)) {
      periods.set(period, [])
    }

    periods.get(period).push(campaign)
  }

  return Array.from(periods.entries())
      .map(([period, items]) => ({
        period,
        items
      }))
      .sort((a, b) => b.period.localeCompare(a.period))
})

watch(
    () => periodGroups.value.map((period) => period.period),
    (periods, previousPeriods = []) => {
      if (!periodPanelsInitialized.value) {
        if (!periods.length) return

        expandedPeriodNames.value = [...periods]
        periodPanelsInitialized.value = true
        return
      }

      const current = new Set(expandedPeriodNames.value)
      const previous = new Set(previousPeriods)
      expandedPeriodNames.value = periods.filter((period) =>
          current.has(period) || !previous.has(period)
      )
    },
    { immediate: true }
)

const campaignColumns = [
  {
    type: 'expand',
    renderExpand(row) {
      return h(NDataTable, {
        columns: childColumns,
        data: row.links,
        pagination: false,
        size: 'small',
        style: 'margin: 8px 0 8px 32px'
      })
    }
  },
  {
    title: columnLabels.campaignSubject,
    key: 'subj',
    minWidth: 260,
    render(row) {
      return h('div', [
        h('strong', row.subj || pageCaps.fallback.noSubject),
        h('div', { class: 'muted mono' }, row.publication_id || '')
      ])
    }
  },
  {
    title: columnLabels.recipients,
    key: 'mails',
    minWidth: 260,
    render(row) {
      return h(NSpace, { size: 4 }, {
        default: () => row.mails.map((mail) => {
          const email = extractEmail(mail)

          return h(NTag, {
            size: 'small',
            round: true,
            style: 'cursor: pointer;',
            onClick: () => copyText(email)
          }, {
            default: () => mail
          })
        })
      })
    }
  },
  {
    title: columnLabels.linksCount,
    key: 'links_count',
    width: 100
  },
  {
    title: columnLabels.types,
    key: 'types',
    minWidth: 220,
    render(row) {
      return h(NSpace, { size: 4 }, {
        default: () => row.types.map((type) =>
            h(NTag, { size: 'small' }, { default: () => type })
        )
      })
    }
  },
  {
    title: columnLabels.campaignDate,
    key: 'date',
    width: 170,
    render(row) {
      return h('span', {
        class: 'mono',
        style: 'cursor: pointer; text-decoration: underline dotted;',
        onClick: () => loadCampaignReports(row, { force: true })
      }, formatDate(row.date))
    }
  }
]

const childColumns = [
  {
    title: columnLabels.linkDate,
    key: 'date',
    width: 140,
    render(row) {
      return renderDateWithPreview(getLatestActionDate(row), row)
    }
  },
  {
    title: columnLabels.linkType,
    key: 'type',
    width: 120,
    render(row) {
      return renderTypeBadge(row)
    }
  },
  {
    title: columnLabels.linkAnchor,
    key: 'link',
    minWidth: 260,
    render(row) {
      const anchor = buildMarkdownText(row) || '—'
      const copyValue = buildAnchorCopyValue(row)

      return h('div', [
        copyCell({
          text: anchor,
          copy: copyValue
        })
      ])
    }
  },
  {
    title: columnLabels.linkShort,
    key: 'short',
    minWidth: 260,
    render(row) {
      const shortUrl = getShortUrl(row)

      if (row.type === 'redirect') {
        return renderRedirectUrlCell(row, shortUrl)
      }

      return shortUrl
          ? copyCell({
            text: shortUrl,
            copy: buildLinkCopyValue(row, shortUrl),
            mono: true
          })
          : h('span', { class: 'muted' }, '—')
    }
  },
  {
    title: columnLabels.linkStatus,
    key: 'status',
    width: 120,
    render(row) {
      const busy = isStatusActionBusy(row)
      const children = [
        h(NButton, {
          size: 'small',
          type: row.status === 'active' || row.status === 'published' ? 'success' : 'warning',
          secondary: true,
          loading: busy,
          disabled: busy,
          onClick: () => toggleStatus(row)
        }, {
          default: () => formatLinkStatus(row.status)
        })
      ]

      if (row.status === 'draft' && row.draft_id) {
        children.push(
            h(NButton, {
              quaternary: true,
              circle: true,
              size: 'tiny',
              type: 'error',
              title: tooltips.deleteDraft,
              onClick: (event) => {
                event.stopPropagation()
                removeDraft(row)
              }
            }, {
              icon: () => h(NIcon, null, {
                default: () => h(Trash2, { size: 14, strokeWidth: 1.9 })
              })
            })
        )
      }

      return h(NSpace, { size: 4, align: 'center' }, { default: () => children })
    }
  },
  {
    title: columnLabels.linkClicksLeft,
    key: 'remaining_clicks',
    width: 140,
    render(row) {
      if (!isActiveLink(row)) return null
      return renderClicksEditor(row)
    }
  },
  {
    title: columnLabels.linkFresh,
    key: 'fresh_until',
    width: 160,
    render(row) {
      if (!isActiveLink(row)) return null
      return renderFreshEditor(row)
    }
  },
  {
    title: columnLabels.linkFlags,
    key: 'access_flags',
    width: 150,
    render(row) {
      if (!isActiveLink(row)) return null
      return h(NSpace, { size: 6, align: 'center' }, {
        default: () => [
          accessIcon({
            active: hasPassword(row),
            activeTitle: tooltips.passwordActive,
            inactiveTitle: tooltips.passwordInactive,
            activeIcon: Lock,
            inactiveIcon: LockOpen,
            onClick: () => openAccessModal(row)
          }),
          accessIcon({
            active: hasSticky(row),
            activeTitle: tooltips.stickyActive,
            inactiveTitle: tooltips.stickyInactive,
            activeIcon: FingerprintPattern,
            inactiveIcon: FingerprintPattern,
            onClick: () => toggleSticky(row)
          }),
          renderDelayEditor(row)
        ]
      })
    }
  }
]

onMounted(() => {
  load()
  setupPublicationsFixedFilter()
})

onBeforeUnmount(() => {
  clearPublicationFilterLoadTimer()
  teardownPublicationsFixedFilter()
})

watch(
    () => [
      filters.query,
      filters.range?.[0] || '',
      filters.range?.[1] || ''
    ],
    () => schedulePublicationFilterLoad()
)

watch(
    () => filters.periodUnit,
    () => updatePublicationRouteQuery()
)

function campaignRowKey(row) {
  return row.key
}

function getExpandedCampaignKeys(period) {
  return expandedCampaignKeysByPeriod[period] || []
}

function updateExpandedCampaignKeys(period, keys, items) {
  const previous = new Set(expandedCampaignKeysByPeriod[period] || [])
  expandedCampaignKeysByPeriod[period] = keys

  for (const key of keys) {
    if (previous.has(key)) continue

    const row = items.find((item) => campaignRowKey(item) === key)
    if (row) {
      loadCampaignReportsOnce(row)
    }
  }
}

async function loadCampaignReportsOnce(row) {
  const key = getCampaignStatsKey(row)
  if (campaignReportsLoaded[key]) return

  campaignReportsLoaded[key] = true
  await loadCampaignReports(row, { notify: false })
}

async function loadCampaignReports(row, options = {}) {
  const { force = false, notify = true } = options

  if (force) {
    clearCampaignReports(row)
  }

  const links = row.links || []

  if (!links.length) {
    if (notify) message.warning(captions.campaignNoLinks)
    return
  }

  let results = []

  try {
    await loadPublicationLinkReports(links)
    results = links.map(() => ({ status: 'fulfilled' }))
  } catch (error) {
    debugCampaignReports('loadCampaignReports:bulk:error', {
      campaign: row.publication_id || row.key || row.subj || '',
      error
    })
    results = await Promise.allSettled(
        links.map((link) => loadLinkReport(link))
    )
  }

  const ok = results.filter((item) => item.status === 'fulfilled').length
  const failed = results.length - ok

  if (failed) {
    if (notify) message.warning(`${captions.campaignStatsPartial}: ${ok}/${links.length}`)
  } else {
    if (notify) message.success(`${captions.campaignStatsLoaded}: ${ok}`)
  }
}

function debugCampaignReports(label, payload) {
  try {
    if (globalThis.localStorage?.getItem('uportal_debug_reports') !== '1') return
    console.warn(`[uportal-report] ${label}`, payload)
  } catch {
    // Debug logging must not affect rendering.
  }
}

function clearCampaignReports(row) {
  for (const link of row.links || []) {
    delete reportCache[getLinkReportKey(link)]
  }

  delete campaignReportsLoaded[getCampaignStatsKey(row)]
}

function getCampaignStatsKey(row) {
  return (row.links || [])
      .map(getLinkReportKey)
      .sort()
      .join('|')
}

function getLinkReportKey(row) {
  return `${row.publication_id}:${row.token}`
}

async function load() {
  clearPublicationFilterLoadTimer()
  updatePublicationRouteQuery()
  await refreshLinks({ notify: true })
}

async function refreshLinks({ notify = true } = {}) {
  loading.value = true

  try {
    await store.dispatch('loadLinks', buildServerFilters())
    if (notify) {
      const loaded = countDisplayedCampaigns()
      const total = linksPager.value.total || loaded
      message.success(formatCaption(captions.loaded, { loaded, total }))
    }
  } catch (error) {
    if (isAuthorizationError(error)) {
      clearPublicationRows()
      store.commit('logout')
      if (notify) message.error(captions.tokenDisabled)
    } else if (notify) {
      message.error(captions.loadError)
    }
  } finally {
    loading.value = false
  }
}

function countDisplayedCampaigns() {
  return periodGroups.value.reduce((sum, period) => sum + period.items.length, 0)
}

function clearPublicationRows() {
  store.commit('setLinks', [])
  store.commit('setLinksPager', {
    limit: filters.limit,
    offset: (filters.page - 1) * filters.limit,
    total: 0,
    pages: 0,
    has_next: false
  })
}

function applyFilters() {
  clearPublicationFilterLoadTimer()
  filters.page = 1
  load()
}

function schedulePublicationFilterLoad() {
  clearPublicationFilterLoadTimer()
  publicationFilterLoadTimer = window.setTimeout(() => {
    filters.page = 1
    updatePublicationRouteQuery()
    load()
  }, PUBLICATIONS_FILTER_LOAD_DELAY_MS)
}

function clearPublicationFilterLoadTimer() {
  if (!publicationFilterLoadTimer) return
  window.clearTimeout(publicationFilterLoadTimer)
  publicationFilterLoadTimer = null
}

function setupPublicationsFixedFilter() {
  nextTick(() => {
    updatePublicationsFixedFilter()
    window.addEventListener('scroll', updatePublicationsFixedFilter, { passive: true })
    document.addEventListener('scroll', updatePublicationsFixedFilter, { passive: true, capture: true })
    window.addEventListener('resize', updatePublicationsFixedFilter)
    publicationsFilterScrollParents = getPublicationsFilterScrollParents(publicationsFilterDockRef.value)
    publicationsFilterScrollParents.forEach((element) => {
      element.addEventListener('scroll', updatePublicationsFixedFilter, { passive: true })
    })

    if (typeof ResizeObserver !== 'undefined') {
      publicationsFilterResizeObserver = new ResizeObserver(updatePublicationsFixedFilter)
      if (publicationsFilterDockRef.value) publicationsFilterResizeObserver.observe(publicationsFilterDockRef.value)
      if (publicationsFilterPanelRef.value) publicationsFilterResizeObserver.observe(publicationsFilterPanelRef.value)
    }
  })
}

function teardownPublicationsFixedFilter() {
  window.removeEventListener('scroll', updatePublicationsFixedFilter)
  document.removeEventListener('scroll', updatePublicationsFixedFilter, { capture: true })
  window.removeEventListener('resize', updatePublicationsFixedFilter)
  publicationsFilterScrollParents.forEach((element) => {
    element.removeEventListener('scroll', updatePublicationsFixedFilter)
  })
  publicationsFilterScrollParents = []
  publicationsFilterResizeObserver?.disconnect()
  publicationsFilterResizeObserver = null
}

function updatePublicationsFixedFilter() {
  const dock = publicationsFilterDockRef.value
  const panel = publicationsFilterPanelRef.value
  if (!dock || !panel) return

  const rect = dock.getBoundingClientRect()
  const shouldFix = rect.top <= 0
  const height = panel.offsetHeight

  publicationsFilterFixed.value = shouldFix

  if (shouldFix) {
    publicationsFilterDockStyle.height = `${height}px`
    publicationsFilterPanelStyle.position = 'fixed'
    publicationsFilterPanelStyle.top = '0'
    publicationsFilterPanelStyle.left = `${rect.left}px`
    publicationsFilterPanelStyle.width = `${rect.width}px`
    publicationsFilterPanelStyle.zIndex = '100'
    return
  }

  publicationsFilterDockStyle.height = ''
  publicationsFilterPanelStyle.position = ''
  publicationsFilterPanelStyle.top = ''
  publicationsFilterPanelStyle.left = ''
  publicationsFilterPanelStyle.width = ''
  publicationsFilterPanelStyle.zIndex = ''
}

function getPublicationsFilterScrollParents(element) {
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

function handlePublicationPageChange(page) {
  filters.page = page
  updatePublicationRouteQuery()
  load()
}

function handlePublicationPageSizeChange(pageSize) {
  filters.limit = pageSize
  filters.page = 1
  updatePublicationRouteQuery()
  load()
}

function buildServerFilters() {
  const payload = {
    mode: 'campaigns',
    limit: filters.limit,
    offset: (filters.page - 1) * filters.limit
  }
  const query = filters.query.trim()

  if (query) payload.query = query

  if (filters.range?.length === 2) {
    payload.from = new Date(filters.range[0]).toISOString()
    payload.to = new Date(filters.range[1]).toISOString()
  }

  return payload
}

function applyPublicationQueryToFilters() {
  const params = new URLSearchParams(window.location.search)
  const page = normalizePositiveInteger(params.get('p'), filters.page)
  const limit = normalizeAllowedPageSize(params.get('n'), filters.limit)
  const period = params.get('per') || ''
  const from = params.get('from') || ''
  const to = params.get('to') || ''

  filters.query = params.get('q') || ''
  filters.page = page
  filters.limit = limit

  if (periodOptions.some(item => item.value === period)) {
    filters.periodUnit = period
  }

  if (from && to) {
    const fromDate = new Date(from)
    const toDate = new Date(to)

    if (!Number.isNaN(fromDate.getTime()) && !Number.isNaN(toDate.getTime())) {
      filters.range = [fromDate.getTime(), toDate.getTime()]
    }
  }
}

function updatePublicationRouteQuery() {
  if (!window.location.pathname.startsWith('/ui/pubs')) return

  const params = new URLSearchParams()
  const query = filters.query.trim()

  if (query) params.set('q', query)
  if (filters.page > 1) params.set('p', String(filters.page))
  if (filters.limit !== 25) params.set('n', String(filters.limit))
  if (filters.periodUnit !== 'month') params.set('per', filters.periodUnit)

  if (filters.range?.length === 2) {
    params.set('from', formatRouteDate(filters.range[0]))
    params.set('to', formatRouteDate(filters.range[1]))
  }

  const queryString = params.toString()
  const nextUrl = `${window.location.pathname}${queryString ? `?${queryString}` : ''}${window.location.hash}`

  if (nextUrl !== `${window.location.pathname}${window.location.search}${window.location.hash}`) {
    window.history.replaceState({}, '', nextUrl)
  }
}

function normalizePositiveInteger(value, fallback) {
  const number = Number(value)
  if (!Number.isFinite(number) || number < 1) return fallback
  return Math.trunc(number)
}

function normalizeAllowedPageSize(value, fallback) {
  const number = normalizePositiveInteger(value, fallback)
  return publicationPageSizes.includes(number) ? number : fallback
}

function formatRouteDate(value) {
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return ''
  return date.toISOString().slice(0, 10)
}

function matchesClientFilters(link) {
  const query = filters.query.trim().toLowerCase()
  const date = getLinkDate(link)

  if (filters.range?.length === 2 && date) {
    const from = new Date(filters.range[0])
    const to = new Date(filters.range[1])
    const current = new Date(date)

    if (current < from || current > to) return false
  }

  if (!query) return true

  const haystack = [
    link.subj,
    link.title,
    link.description,
    link.link,
    link.anchor,
    link.token,
    link.publication_id,
    ...(link.mails || [])
  ]
      .join(' ')
      .toLowerCase()

  return haystack.includes(query)
}

function buildShortMarkdown(row) {
  const short = getShortUrl(row)

  if (!short) return buildMarkdownText(row)

  if (row.type === 'pixel') {
    return `<img src="${short}" width="1" height="1" alt="" style="width:1px;height:1px;border:0;" data-uportal-pixel="1">`
  }

  return buildMarkdownLink(row, short)
}
function openCreate() {
  editingDraft.value = null
  linkEditorVisible.value = true
}
function extractEmail(value) {
  const text = String(value || '')
  const match = text.match(/<([^>]+)>/)
  if (match?.[1]) return match[1].trim()

  const plain = text.match(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/i)
  return plain?.[0] || text
}
function buildAnchorCopyValue(row) {
  if (row.type === 'pixel') {
    const short = getShortUrl(row)
    return `<img src="${short}" width="1" height="1" alt="" style="width:1px;height:1px;border:0;" data-uportal-pixel="1">`
  }

  return buildShortMarkdown(row)
}

function buildLinkCopyValue(row, shortUrl) {
  if (!shortUrl) return ''
  return shortUrl
}

function buildMarkdownLink(row, url) {
  const anchor = buildMarkdownAnchor(row) || url
  return buildCopyText(row, `[${escapeMarkdownLinkText(anchor)}](${escapeMarkdownUrl(url)})`)
}

function buildMarkdownText(row) {
  return buildCopyText(row, buildMarkdownAnchor(row))
}

function buildCopyText(row, middle) {
  return [
    getRowPre(row),
    middle,
    getRowPost(row)
  ].filter(Boolean).join(' ').replace(/\s+/g, ' ').trim()
}

function buildMarkdownAnchor(row) {
  return row.link || row.raw?.link || row.raw?.meta?.link || getLatestActionDetail(row, 'link') || row.anchor || row.title || ''
}

function getSourceUrl(row) {
  return row.target_url || row.form?.target_url || row.raw?.target_url || row.raw?.meta?.target_url || row.raw?.form?.target_url || ''
}

function getShortUrl(row) {
  const short = row.short_url || row.shortlink || row.short || row.url || row.raw?.short_url || row.raw?.shortlink || row.raw?.short || row.raw?.url || ''
  if (!short) return ''
  if (/^https?:\/\//.test(short)) return normalizePublicUrl(short)

  const serverUrl = normalizeServerUrl(store.state.serverUrl)
  return `${serverUrl}/s/${short}`
}

function escapeMarkdownLinkText(value) {
  return String(value || '').replace(/([\\[\]])/g, '\\$1')
}

function escapeMarkdownUrl(value) {
  return String(value || '').replace(/\)/g, '%29')
}
function formatClicksLeft(value) {
  if (normalizeClicksLimit(value) < 0 || value === '' || value == null) return '∞'
  return String(value)
}

function renderClicksEditor(row) {
  if (row.status === 'draft') return formatClicksLeft(row.remaining_clicks)

  const key = linkParamKey(row)

  return h(NPopover, {
    trigger: 'click',
    placement: 'bottom',
    show: !!clicksPopoverShown[key],
    onUpdateShow: value => {
      clicksPopoverShown[key] = value
      if (value) prepareLinkParamDraft(row)
    }
  }, {
    trigger: () => h('span', {
      class: 'mono',
      style: 'cursor: pointer; text-decoration: underline dotted;',
    }, formatClicksLeft(row.remaining_clicks)),
    default: () => h(NSpace, { vertical: true, size: 8, style: 'width: 150px' }, {
      default: () => [
        h(NInput, {
          value: getLinkParamDraft(row).remaining_clicks,
          maxlength: 5,
          placeholder: '-1',
          onUpdateValue: value => {
            getLinkParamDraft(row).remaining_clicks = normalizeClicksInput(value)
          }
        }),
        h(NButton, {
          size: 'small',
          type: 'primary',
          onClick: () => saveClicks(row)
        }, { default: () => pageCaps.save })
      ]
    })
  })
}

function renderFreshEditor(row) {
  if (row.status === 'draft') return formatFresh(row.fresh_until)

  const key = linkParamKey(row)

  return h(NPopover, {
    trigger: 'click',
    placement: 'bottom',
    show: !!freshPopoverShown[key],
    onUpdateShow: value => {
      freshPopoverShown[key] = value
      if (value) prepareLinkParamDraft(row)
    }
  }, {
    trigger: () => h('span', {
      class: 'mono',
      style: 'cursor: pointer; text-decoration: underline dotted;',
    }, formatFresh(row.fresh_until)),
    default: () => h(NSpace, { vertical: true, size: 8, style: 'width: 250px' }, {
      default: () => [
        h(NDatePicker, {
          value: getLinkParamDraft(row).fresh_ts,
          type: 'datetime',
          clearable: true,
          style: 'width: 100%',
          format: 'yyyy-MM-dd HH:mm',
          timePickerProps: { format: 'HH:mm' },
          onUpdateValue: value => {
            getLinkParamDraft(row).fresh_ts = value
          }
        }),
        h(NButton, {
          size: 'small',
          type: 'primary',
          onClick: () => saveFreshness(row)
        }, { default: () => pageCaps.save })
      ]
    })
  })
}

function renderDelayEditor(row) {
  if (row.status === 'draft') return null

  const delay = normalizeDelay(row.delay)
  const color = delay > 0 ? '#2080f0' : '#18a058'
  const key = linkParamKey(row)

  return h(NPopover, {
    trigger: 'click',
    placement: 'bottom',
    show: !!delayPopoverShown[key],
    onUpdateShow: value => {
      delayPopoverShown[key] = value
      if (value) prepareLinkParamDraft(row)
    }
  }, {
    trigger: () => h('span', {
      style: `display: inline-flex; align-items: center; justify-content: center; color: ${color}; cursor: pointer;`,
      title: formatCaption(tooltips.delay, { value: formatDelay(delay) }),
    }, [
      h(Timer, { size: 15, strokeWidth: 1.8, color, stroke: color })
    ]),
    default: () => h(NSpace, { vertical: true, size: 8, style: 'width: 150px' }, {
      default: () => [
        h(NInputNumber, {
          value: getLinkParamDraft(row).delay,
          min: 0,
          step: 1,
          style: 'width: 100%',
          onUpdateValue: value => {
            getLinkParamDraft(row).delay = normalizeDelay(value)
          }
        }),
        h(NButton, {
          size: 'small',
          type: 'primary',
          onClick: () => saveDelay(row)
        }, { default: () => pageCaps.save })
      ]
    })
  })
}

function formatDelay(value) {
  return formatCaption(pageCaps.fallback.seconds, { value: normalizeDelay(value) })
}

function getLinkParamDraft(row) {
  const key = linkParamKey(row)
  if (!linkParamDrafts[key]) {
    linkParamDrafts[key] = makeLinkParamDraft(row)
  }
  return linkParamDrafts[key]
}

function prepareLinkParamDraft(row) {
  linkParamDrafts[linkParamKey(row)] = makeLinkParamDraft(row)
}

function makeLinkParamDraft(row) {
  return {
    remaining_clicks: formatClicksLeft(row.remaining_clicks) === '∞' ? '-1' : String(row.remaining_clicks ?? ''),
    fresh_ts: toDatePickerValue(row.fresh_until),
    delay: normalizeDelay(row.delay)
  }
}

function linkParamKey(row) {
  return `${row.publication_id}:${row.token}`
}

function toDatePickerValue(value) {
  if (value === -1 || value === '-1' || value === '' || value == null) return null
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return null
  return date.getTime()
}

async function saveClicks(row) {
  try {
    const value = normalizeClicksLimit(getLinkParamDraft(row).remaining_clicks)
    await store.dispatch('setLinkClicks', {
      publication_id: row.publication_id,
      token: row.token,
      remaining_clicks: value
    })
    getLinkParamDraft(row).remaining_clicks = String(value)
    row.remaining_clicks = value
    clicksPopoverShown[linkParamKey(row)] = false
    message.success(captions.clicksSaved)
  } catch (error) {
    message.error(formatCaption(captions.clicksSaveError, { error: formatApiError(error) }))
  }
}

async function saveFreshness(row) {
  try {
    const value = getLinkParamDraft(row).fresh_ts
        ? new Date(getLinkParamDraft(row).fresh_ts).toISOString()
        : '-1'
    await store.dispatch('setLinkFreshness', {
      publication_id: row.publication_id,
      token: row.token,
      fresh_until: value
    })
    row.fresh_until = value || -1
    freshPopoverShown[linkParamKey(row)] = false
    message.success(captions.freshSaved)
  } catch (error) {
    message.error(formatCaption(captions.freshSaveError, { error: formatApiError(error) }))
  }
}

async function saveDelay(row) {
  try {
    const value = normalizeDelay(getLinkParamDraft(row).delay)
    await store.dispatch('setPublicationDelay', {
      publication_id: row.publication_id,
      token: row.token,
      delay: value
    })
    getLinkParamDraft(row).delay = value
    row.delay = String(value)
    delayPopoverShown[linkParamKey(row)] = false
    message.success(captions.delaySaved)
  } catch (error) {
    message.error(formatCaption(captions.delaySaveError, { error: formatApiError(error) }))
  }
}

function normalizeDelay(value) {
  const numeric = Number(value)
  if (!Number.isFinite(numeric) || numeric < 0) return 0
  return Math.floor(numeric)
}

function normalizeLink(raw) {
  return {
    ...raw,
    publication_id: raw.publication_id || raw.publication || '',
    token: raw.token || '',
    type: raw.type || '',
    status: raw.status || 'published',
    short: getShortUrl(raw),
    subj: raw.subj || raw.title || '',
    mails: normalizeMails(raw.mails),
    pre: raw.pre || raw.meta?.pre || '',
    link: raw.link || raw.meta?.link || '',
    anchor: raw.anchor || raw.link || raw.meta?.link || '',
    post: raw.post || raw.meta?.post || '',
    target_url: raw.target_url || raw.form?.target_url || raw.meta?.target_url || '',
    delay: raw.delay ?? raw.meta?.delay ?? raw.form?.delay ?? '0',
    image: raw.image || raw.meta?.image || '',
    imageDataUrl: raw.imageDataUrl || '',
    preview_url: raw.preview_url || raw.meta?.preview_url || '',
    password_hash: raw.password_hash || raw.meta?.password_hash || '',
    password_protected: !!(raw.password_protected || raw.meta?.password_protected),
    password_hint: raw.password_hint || raw.meta?.password_hint || '',
    sticky: !!raw.sticky,
    remaining_clicks: raw.remaining_clicks,
    published_at: raw.published_at || raw.meta?.published_at || '',
    last_action: raw.last_action || null,
    date: raw.last_action?.date || getRawDate(raw),
    raw
  }
}

function groupToCampaigns(items) {
  const map = new Map()
  const seenLinks = new Set()

  for (const link of items) {
    const linkKey = getCampaignLinkKey(link)
    if (seenLinks.has(linkKey)) continue
    seenLinks.add(linkKey)

    const key = buildCampaignKey(link)

    if (!map.has(key)) {
      map.set(key, {
        key,
        publication_id: link.publication_id,
        subj: link.subj || pageCaps.fallback.noSubject,
        mails: link.mails || [],
        links: [],
        links_count: 0,
        typesSet: new Set(),
        date: getPublicationSortDate(link)
      })
    }

    const campaign = map.get(key)

    campaign.links.push(link)
    campaign.links_count += 1

    if (link.type) campaign.typesSet.add(link.type)

    const linkDate = getPublicationSortDate(link)

    if (linkDate && (!campaign.date || new Date(linkDate) < new Date(campaign.date))) {
      campaign.date = linkDate
    }
  }

  return Array.from(map.values())
      .map((campaign) => ({
        ...campaign,
        types: Array.from(campaign.typesSet)
      }))
      .sort((a, b) => new Date(b.date || 0) - new Date(a.date || 0))
}

function getCampaignLinkKey(link) {
  return [
    link.publication_id || '',
    link.token || '',
    link.short_id || link.short || link.short_url || ''
  ].join(':')
}

function buildCampaignKey(link) {
  const publicationId = link.publication_id || ''
  const subj = link.subj || ''
  const mails = [...(link.mails || [])].sort().join(',')
  return `${publicationId}::${subj}::${mails}`
}

function normalizeMails(value) {
  if (Array.isArray(value)) return value

  if (typeof value === 'string') {
    return value
        .split(',')
        .map((item) => item.trim())
        .filter(Boolean)
  }

  return []
}

function getLinkDate(link) {
  return link.date || getRawDate(link.raw || link)
}

function getRawDate(raw) {
  const actions = raw.actions || raw.raw?.actions || []

  if (Array.isArray(actions) && actions.length) {
    const last = [...actions]
        .filter((item) => item.date)
        .sort((a, b) => new Date(b.date) - new Date(a.date))[0]

    if (last?.date) return last.date
  }

  return (
      raw.created_at ||
      raw.created ||
      raw.date ||
      raw.ts ||
      raw.updated_at ||
      ''
  )
}

function buildPeriodLabel(dateValue, unit) {
  if (!dateValue) return pageCaps.fallback.noDate

  const date = new Date(dateValue)
  if (Number.isNaN(date.getTime())) return pageCaps.fallback.noDate

  const year = date.getFullYear()
  const month = date.getMonth() + 1
  const day = date.getDate()

  if (unit === 'day') {
    return `${year}-${pad(month)}-${pad(day)}`
  }

  if (unit === 'week') {
    return `${year}-W${pad(getWeekNumber(date))}`
  }

  if (unit === 'quarter') {
    return `${year}-Q${Math.floor((month - 1) / 3) + 1}`
  }

  if (unit === 'year') {
    return String(year)
  }

  return `${year}-${pad(month)}`
}

function getWeekNumber(date) {
  const current = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()))
  const dayNum = current.getUTCDay() || 7

  current.setUTCDate(current.getUTCDate() + 4 - dayNum)

  const yearStart = new Date(Date.UTC(current.getUTCFullYear(), 0, 1))

  return Math.ceil((((current - yearStart) / 86400000) + 1) / 7)
}

function pad(value) {
  return String(value).padStart(2, '0')
}

function formatDate(value) {
  if (!value) return '—'

  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return '—'

  return date.toLocaleString()
}

async function publishDraft(row) {
  try {
    const result = await store.dispatch('publishDraft', row)
    store.commit('publishDraftLocally', {
      draftId: row.draft_id,
      link: buildPublishedLink(row, result)
    })
    await cleanupDraftAssets(row)
    message.success(captions.linkPublished)
  } catch (error) {
    message.error(formatCaption(captions.publishError, { error: formatApiError(error) }))
  }
}

async function publishFromStatus(row) {
  if (row.status === 'draft') {
    await publishDraft(row)
    return
  }

  message.info(captions.alreadyPublished)
}

async function unpublish(row) {
  try {
    await store.dispatch('unpublishLink', row)
    message.success(captions.unpublished)
    await load()
  } catch {
    message.error(captions.unpublishError)
  }
}

function openAccessModal(row) {
  accessRow.value = row
  passwordForm.password = ''
  accessModalVisible.value = true
}

async function toggleSticky(row) {
  await saveSticky(!hasSticky(row), row)
}

async function saveSticky(value, row = accessRow.value) {
  if (!row) return

  accessSaving.value = true

  try {
    await store.dispatch('setPublicationSticky', {
      publication_id: row.publication_id,
      token: row.token,
      sticky: value
    })
    row.sticky = !!value
    if (row.raw) row.raw.sticky = !!value
    message.success(value ? captions.stickySavedOn : captions.stickySavedOff)
  } catch (error) {
    message.error(formatCaption(captions.stickySaveError, { error: formatApiError(error) }))
  } finally {
    accessSaving.value = false
  }
}

async function savePassword() {
  if (!accessRow.value) return

  passwordSaving.value = true

  try {
    const data = await store.dispatch('setPublicationPassword', {
      publication_id: accessRow.value.publication_id,
      token: accessRow.value.token,
      password: passwordForm.password,
      password_hint: '',
      password_ttl_sec: 1800
    })
    const meta = data?.message?.[0]?.meta || {}
    accessRow.value.password_hash = meta.password_hash || ''
    accessRow.value.password_hint = meta.password_hint || ''
    if (accessRow.value.raw) {
      accessRow.value.raw.password_hash = meta.password_hash || ''
      accessRow.value.raw.password_hint = meta.password_hint || ''
    }
    passwordForm.password = ''
    message.success(accessRow.value.password_hash ? captions.passwordSaved : captions.passwordRemoved)
  } catch (error) {
    message.error(formatCaption(captions.passwordSaveError, { error: formatApiError(error) }))
  } finally {
    passwordSaving.value = false
  }
}

async function removeDraft(row) {
  store.commit('removeDraft', row.draft_id)
  await cleanupDraftAssets(row)
  message.success(captions.draftDeleted)
}

async function cleanupDraftAssets(row) {
  try {
    await deleteDraftAssetsForDraft(row)
  } catch (error) {
    message.warning(formatCaption(captions.draftStorageWarning, { error: formatApiError(error) }))
  }
}

function copyCell({ text, copy, mono = false, tag = false }) {
  const content = tag
      ? h(NTag, { size: 'small' }, { default: () => text })
      : h('span', { class: mono ? 'mono' : '' }, text)

  return h(NTooltip, {}, {
    trigger: () => h('span', {
      style: 'display: inline-flex; align-items: center; gap: 6px; cursor: pointer;',
      onClick: () => copyText(copy)
    }, [
      h(NIcon, { size: 15 }, { default: () => h(CopyOutline) }),
      content
    ]),
    default: () => formatCaption(tooltips.copy, { value: copy })
  })
}

function renderRedirectUrlCell(row, shortUrl) {
  if (!shortUrl) return h('span', { class: 'muted' }, '—')

  const sourceUrl = getSourceUrl(row)
  const children = []

  children.push(copyIconButton({
    icon: CopyOutline,
    copy: shortUrl,
    title: formatCaption(tooltips.copyShort, { value: shortUrl })
  }))
  children.push(h('span', { class: 'mono' }, shortUrl))

  if (sourceUrl) {
    children.push(copyIconButton({
      icon: ExternalLink,
      copy: sourceUrl,
      title: formatCaption(tooltips.copySource, { value: sourceUrl })
    }))
  }

  return h('span', {
    style: 'display: inline-flex; align-items: center; gap: 6px;'
  }, children)
}

function copyIconButton({ icon, copy, title }) {
  return h(NTooltip, {}, {
    trigger: () => h('span', {
      style: 'display: inline-flex; align-items: center; cursor: pointer; color: rgba(31, 34, 37, 0.72);',
      onClick: (event) => {
        event.stopPropagation()
        copyText(copy)
      }
    }, [
      icon === CopyOutline
          ? h(NIcon, { size: 15 }, { default: () => h(CopyOutline) })
          : h(icon, { size: 15, strokeWidth: 1.8 })
    ]),
    default: () => title
  })
}

async function copyText(value) {
  if (!value) {
    message.warning(captions.nothingToCopy)
    return
  }

  await navigator.clipboard.writeText(value)
  message.success(captions.copied)
}

function accessIcon({ active, activeTitle, inactiveTitle, activeIcon, inactiveIcon, onClick = null }) {
  const icon = active ? activeIcon : inactiveIcon
  const color = active ? '#f0a020' : '#18a058'

  return h(NTooltip, { trigger: 'hover' }, {
    trigger: () => h('span', {
      style: `display: inline-flex; align-items: center; justify-content: center; color: ${color}; cursor: ${onClick ? 'pointer' : 'help'};`,
      onClick: onClick || undefined
    }, [
      h(icon, {
        size: 17,
        strokeWidth: 1.9,
        color,
        stroke: color
      })
    ]),
    default: () => active ? activeTitle : inactiveTitle
  })
}

function formatApiError(error) {
  return error?.response?.data?.message?.[0]?.text ||
      error?.response?.data?.message ||
      error?.response?.data?.error ||
      error?.message ||
      pageCaps.fallback.unknownError
}

function isAuthorizationError(error) {
  const status = error?.response?.status
  return status === 401 || status === 403
}

function buildPublishedLink(row, result) {
  return {
    ...row,
    ...extractPublishedLink(result),
    status: 'published',
    draft_id: ''
  }
}

function extractPublishedLink(payload) {
  if (Array.isArray(payload?.message)) return payload.message[0] || {}
  if (Array.isArray(payload?.items)) return payload.items[0] || {}
  if (Array.isArray(payload?.links)) return payload.links[0] || {}
  if (payload?.message && typeof payload.message === 'object') return payload.message
  return payload || {}
}

function renderDateWithPreview(value, row, attrs = {}) {
  const label = attrs.class === 'mono' ? formatDate(value) : relativeFromNow(value)
  const preview = getPreviewImageUrl(row)
  const triggerAttrs = {
    ...attrs,
    class: attrs.class || 'mono',
    style: attrs.style || (preview ? 'cursor: help; text-decoration: underline dotted;' : '')
  }

  const trigger = () => h('span', triggerAttrs, label)

  if (!preview) return trigger()

  return h(NTooltip, { trigger: 'hover', placement: 'right' }, {
    trigger,
    default: () => h('img', {
      src: preview,
      alt: row?.image || '',
      class: 'publication-date-preview',
      onError: (event) => {
        event.currentTarget.style.display = 'none'
      }
    })
  })
}

function getPreviewImageUrl(row) {
  if (!row) return ''

  const image = row.imageDataUrl || row.image || row.raw?.imageDataUrl || row.raw?.image || row.raw?.meta?.image || ''
  if (/^(https?:|data:|blob:)/.test(image)) return image

  const publicationId = row.publication_id || row.raw?.publication_id || ''
  const token = row.token || row.raw?.token || ''
  const direct = row.preview_url || row.raw?.preview_url || row.raw?.meta?.preview_url || ''

  if (!image || !publicationId || !token) return direct ? normalizePublicUrl(direct) : ''

  const serverUrl = normalizeServerUrl(store.state.serverUrl)
  return `${serverUrl}/assets-public/${encodeURIComponent(publicationId)}/${encodeURIComponent(token)}/${encodeURIComponent(image)}`
}

function normalizePublicUrl(value) {
  const serverUrl = normalizeServerUrl(store.state.serverUrl)

  try {
    const url = new URL(value)
    if (url.pathname.startsWith('/s/') || url.pathname.startsWith('/assets-public/')) {
      return `${serverUrl}${url.pathname}${url.search}${url.hash}`
    }
  } catch {
    return value
  }

  return value
}

function getFirstPreviewLink(row) {
  return (row.links || []).find(link => getPreviewImageUrl(link)) || row.links?.[0] || null
}

function hasPassword(row) {
  return !!(
    row.form?.password ||
    row.password ||
    row.password_protected ||
    row.password_hash ||
    row.raw?.password_protected ||
    row.raw?.password ||
    row.raw?.password_hash ||
    row.raw?.meta?.password_hash ||
    row.raw?.form?.password
  )
}

function hasSticky(row) {
  return !!(row.sticky || row.raw?.sticky || row.raw?.meta?.sticky)
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

function getActionDates(row) {
  const dates = []

  if (row.last_action?.date) {
    dates.push(new Date(row.last_action.date))
  }

  if (row.raw?.last_action?.date) {
    dates.push(new Date(row.raw.last_action.date))
  }

  const actions = row.actions || row.raw?.actions || []
  if (Array.isArray(actions)) {
    for (const action of actions) {
      if (action.date) {
        dates.push(new Date(action.date))
      }
    }
  }

  return dates.filter(date => !Number.isNaN(date.getTime()))
}

function getLatestActionDate(row) {
  const dates = getActionDates(row)

  if (dates.length) {
    return new Date(Math.max(...dates.map(date => date.getTime()))).toISOString()
  }

  return getFallbackDate(row)
}

function getEarliestActionDate(row) {
  const dates = getActionDates(row)

  if (dates.length) {
    return new Date(Math.min(...dates.map(date => date.getTime()))).toISOString()
  }

  return getFallbackDate(row)
}

function getPublicationSortDate(row) {
  const stableDate = (
      row.published_at ||
      row.raw?.published_at ||
      row.created_at ||
      row.raw?.created_at ||
      row.created ||
      row.raw?.created ||
      ''
  )

  if (stableDate) return stableDate

  return getEarliestActionDate(row)
}

function getFallbackDate(row) {
  return (
      row.last_action?.date ||
      row.raw?.last_action?.date ||
      row.created_at ||
      row.created ||
      row.date ||
      row.ts ||
      row.updated_at ||
      row.raw?.created_at ||
      row.raw?.created ||
      row.raw?.date ||
      row.raw?.ts ||
      row.raw?.updated_at ||
      ''
  )
}

function relativeFromNow(value) {
  if (!value) return '—'

  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return '—'

  const diffMs = Date.now() - date.getTime()
  const minutes = Math.floor(diffMs / 60000)
  const hours = Math.floor(minutes / 60)
  const days = Math.floor(hours / 24)

  if (minutes < 1) return pageCaps.fallback.justNow
  if (minutes < 60) return formatCaption(pageCaps.fallback.minutesAgo, { value: minutes })
  if (hours < 24) return formatCaption(pageCaps.fallback.hoursAgo, { value: hours })
  return formatCaption(pageCaps.fallback.daysAgo, { value: days })
}

function formatFresh(value) {
  if (value === -1 || value === '-1' || value === '' || value == null) {
    return '∞'
  }

  return formatDate(value)
}

async function toggleStatus(row) {
  const key = getStatusActionKey(row)
  if (statusActionBusy[key]) return

  statusActionBusy[key] = true
  try {
    if (row.status === 'draft') {
      await publishDraft(row)
      return
    }

    const nextStatus = row.status === 'active' || row.status === 'published'
        ? 'hold'
        : 'active'

    try {
      await store.dispatch('setPublicationStatus', {
        publication_id: row.publication_id,
        token: row.token,
        status: nextStatus
      })
      row.status = nextStatus
      if (row.raw) row.raw.status = nextStatus
      message.success(formatCaption(captions.statusChanged, { status: formatLinkStatus(nextStatus) }))
    } catch (error) {
      message.error(formatCaption(captions.statusChangeError, { error: formatApiError(error) }))
    }
  } finally {
    delete statusActionBusy[key]
  }
}

function isStatusActionBusy(row) {
  return !!statusActionBusy[getStatusActionKey(row)]
}

function getStatusActionKey(row) {
  return `${row.publication_id || ''}:${row.token || ''}:${row.draft_id || ''}`
}

function formatLinkStatus(status) {
  if (status === 'hold' || status === 'disabled' || status === 'inactive') return 'hold'
  if (status === 'published') return 'active'
  return status || 'active'
}

function isActiveLink(row) {
  const status = formatLinkStatus(row?.status)
  return status === 'active'
}

function normalizeClicksInput(value) {
  const text = String(value || '').replace(/[^\d-]/g, '').slice(0, 5)
  if (text.includes('-')) return '-1'
  return text
}

function normalizeClicksLimit(value) {
  const number = Number(value)
  if (!Number.isFinite(number) || number < 0) return -1
  return Math.trunc(number)
}
function campaignRowClassName(row) {
  const status = getCampaignReportStatus(row)

  if (status === 'green') return 'campaign-row-green'
  if (status === 'red') return 'campaign-row-red'

  return ''
}

function getCampaignReportStatus(row) {
  const links = row.links || []

  if (!links.length) return ''

  const cached = links
      .map(link => reportCache[`${link.publication_id}:${link.token}`])
      .filter(Boolean)

  if (cached.length !== links.length) return ''

  const hasGreen = cached.some(item => (item.summary?.views || 0) > 0)

  if (hasGreen) return 'green'

  return 'red'
}
</script>
<style scoped>
.publications-filter-dock {
  margin-bottom: 16px;
}

.publications-filter-panel.is-fixed {
  background: #fff;
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.06);
}

.publications-filter-bar {
  display: grid;
  grid-template-columns: minmax(280px, 2fr) minmax(220px, 1fr) 112px minmax(260px, 1.1fr) 40px;
  gap: 16px;
  align-items: end;
}

.publications-filter-bar :deep(.n-form-item) {
  margin-bottom: 0;
}

.publications-period-unit {
  min-width: 0;
}

.publications-pagination-item {
  min-width: 0;
}

.publications-pagination {
  max-width: 100%;
  overflow-x: auto;
  overflow-y: hidden;
  padding-bottom: 1px;
  white-space: nowrap;
}

.publications-pagination :deep(.n-pagination) {
  flex-wrap: nowrap;
}

.publications-add-item {
  justify-self: end;
}

.period-collapse-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  width: 100%;
  min-width: 0;
  gap: 12px;
}

.period-collapse-count {
  flex: 0 0 auto;
  min-width: 28px;
  text-align: right;
  color: rgba(31, 34, 37, 0.55);
  font-variant-numeric: tabular-nums;
}

.publications-refresh-button {
  color: rgba(31, 34, 37, 0.42);
}

.publications-refresh-button:hover {
  color: rgba(31, 34, 37, 0.72);
}

.publications-add-button {
  color: #18a058 !important;
  border: 1px solid #18a058 !important;
}

.publications-add-button :deep(svg) {
  color: currentColor;
  stroke: currentColor;
}

:deep(.campaign-row-green td) {
  background-color: rgba(24, 160, 88, 0.08) !important;
}

:deep(.campaign-row-red td) {
  background-color: rgba(208, 48, 80, 0.08) !important;
}

:deep(.campaign-row-green:hover td) {
  background-color: rgba(24, 160, 88, 0.13) !important;
}

:deep(.campaign-row-red:hover td) {
  background-color: rgba(208, 48, 80, 0.13) !important;
}

.publication-date-preview {
  display: block;
  width: 160px;
  max-height: 120px;
  object-fit: cover;
  border-radius: 4px;
}

@media (max-width: 1180px) {
  .publications-filter-bar {
    grid-template-columns: minmax(260px, 1fr) minmax(220px, 1fr) 112px 40px;
  }

  .publications-pagination-item {
    grid-column: 1 / -1;
  }
}

@media (max-width: 760px) {
  .publications-filter-bar {
    grid-template-columns: 1fr 40px;
  }

  .publications-period-unit,
  .publications-pagination-item {
    grid-column: 1 / -1;
  }
}
</style>
