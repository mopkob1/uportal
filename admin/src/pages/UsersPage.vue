<template>
  <n-space vertical size="large">
    <n-collapse v-model:expanded-names="adminPanelExpanded">
      <n-collapse-item :title="captions.adminAccessTitle" name="admin-access">
        <n-card>
          <n-grid :cols="2" :x-gap="16">
            <n-form-item-gi :label="captions.adminHeaderLabel">
              <n-input v-model:value="adminHeader" :placeholder="captions.adminHeaderPlaceholder" />
            </n-form-item-gi>

            <n-form-item-gi :label="captions.adminTokenLabel">
              <n-input
                  v-model:value="adminToken"
                  type="password"
                  show-password-on="click"
                  :placeholder="captions.adminTokenPlaceholder"
              />
            </n-form-item-gi>
          </n-grid>

          <n-space justify="end">
            <n-button type="primary" @click="saveAdminAuth">
              {{ captions.saveAdminAccess }}
            </n-button>
          </n-space>
        </n-card>
      </n-collapse-item>
    </n-collapse>

    <n-card>
      <template #header>
        <n-space justify="space-between" style="width: 100%">
          <span>{{ captions.usersTitle }}</span>

          <n-space>
            <n-input
                v-model:value="query"
                clearable
                :placeholder="captions.searchPlaceholder"
                style="width: min(56vw, 640px)"
                @keyup.enter="applySearch"
                @clear="applySearchAfterClear"
            >
              <template #prefix>
                <n-button
                    circle
                    quaternary
                    size="small"
                    :title="tooltips.search"
                    @click.stop="applySearch"
                >
                  <template #icon>
                    <n-icon>
                      <Search :size="15" :stroke-width="1.8" />
                    </n-icon>
                  </template>
                </n-button>
              </template>
            </n-input>

            <n-button
                v-if="hasAdminToken"
                circle
                quaternary
                class="users-add-button"
                :title="tooltips.addUser"
                @click="openCreate"
            >
              <template #icon>
                <n-icon>
                  <Plus :size="16" :stroke-width="1.8" />
                </n-icon>
              </template>
            </n-button>
          </n-space>
        </n-space>
      </template>

      <n-data-table
          remote
          :columns="columns"
          :data="tokens"
          :loading="loading"
          :pagination="pagination"
      />
    </n-card>

    <UserTokenModal
        v-model:show="editorVisible"
        :item="selectedItem"
        @save="saveItem"
    />
  </n-space>
</template>

<script setup>
import { computed, h, nextTick, onMounted, ref } from 'vue'
import { useStore } from 'vuex'
import { CopyOutline } from '@vicons/ionicons5'
import { Pencil, Plus, Search, Trash2 } from 'lucide-vue-next'
import { useMessage, NButton, NIcon, NPopconfirm, NSelect, NSpace, NTag, NTooltip } from 'naive-ui'
import UserTokenModal from '../users/UserTokenModal.vue'
import { formatCaption, getCaptions } from '../captions'

const userCaps = getCaptions('users')
const columnLabels = userCaps.columns
const captions = userCaps.texts
const tooltips = userCaps.actions

const store = useStore()
const message = useMessage()

const adminHeader = ref(store.state.adminHeader || 'X-Admin-Key')
const adminToken = ref(store.state.adminToken || '')
const adminPanelExpanded = ref(adminToken.value ? [] : ['admin-access'])
const query = ref('')

const loading = ref(false)
const editorVisible = ref(false)
const selectedItem = ref(null)

const tokens = computed(() => store.state.tokens || [])
const hasAdminToken = computed(() => !!store.state.adminToken)
const pager = computed(() => store.state.tokensPager || {
  page: 1,
  limit: 10,
  total: 0
})

const columns = [
  {
    title: columnLabels.token,
    key: 'token',
    render(row) {
      return tokenCopyCell(row)
    }
  },
  {
    title: columnLabels.user,
    key: 'user'
  },
  {
    title: columnLabels.plugin,
    key: 'plugin',
    width: 190,
    render(row) {
      return clientSelector(row, 'plugin')
    }
  },
  {
    title: columnLabels.web,
    key: 'web',
    width: 190,
    render(row) {
      return clientSelector(row, 'web')
    }
  },
  {
    title: columnLabels.scope,
    key: 'scope',
    render(row) {
      return h(NSpace, { size: 4 }, {
        default: () => normalizeArray(row.scope).map(item =>
            h(NTag, { size: 'small' }, { default: () => formatScope(item) })
        )
      })
    }
  },
  {
    title: columnLabels.status,
    key: 'status',
    render(row) {
      return h(NTag, {
        type: tokenStatusTagType(row.status || 'active'),
        size: 'small',
        style: tokenStatusCanToggle(row.status || 'active') && hasAdminToken.value ? 'cursor: pointer;' : '',
        onClick: () => toggleStatus(row)
      }, {
        default: () => formatStatus(row.status || 'active')
      })
    }
  },
  {
    title: columnLabels.tags,
    key: 'tags',
    render(row) {
      return h(NSpace, { size: 4 }, {
        default: () => normalizeArray(row.tags).map(item =>
            h(NTag, { size: 'small', round: true }, { default: () => item })
        )
      })
    }
  },
  {
    title: columnLabels.actions,
    key: 'actions',
    width: 130,
    render(row) {
      const buttons = [
          iconButton({
            title: tokenCanEdit(row) ? tooltips.edit : tooltips.editLocked,
            icon: Pencil,
            tone: 'edit',
            disabled: !tokenCanEdit(row),
            onClick: () => openEdit(row)
          })
      ]

      if (hasAdminToken.value) {
        buttons.push(h(NPopconfirm, {
            positiveText: captions.confirmDelete,
            negativeText: captions.cancelDelete,
            onPositiveClick: () => deleteItem(row)
          }, {
            trigger: () => iconButton({
              title: tooltips.delete,
              icon: Trash2,
              tone: 'delete',
              tooltip: false
            }),
            default: () => formatCaption(captions.deleteConfirm, {
              token: maskToken(row.token)
            })
          }))
      }

      return h(NSpace, {}, {
        default: () => buttons
      })
    }
  }
]

const pagination = computed(() => ({
  page: pager.value.page,
  pageSize: pager.value.limit,
  itemCount: pager.value.total,
  showSizePicker: true,
  pageSizes: [10, 20, 50, 100],
  onChange: async (page) => {
    await load({ page, limit: pager.value.limit })
  },
  onUpdatePageSize: async (limit) => {
    await load({ page: 1, limit })
  }
}))

function saveAdminAuth() {
  store.commit('setAdminAuth', {
    header: adminHeader.value,
    token: adminToken.value
  })

  adminPanelExpanded.value = adminToken.value ? [] : ['admin-access']
  message.success(captions.adminAccessSaved)
  load({ page: 1, limit: pager.value.limit || 10 })
}

async function load(params = {}) {
  loading.value = true

  try {
    const result = await store.dispatch('loadTokens', {
      page: params.page || pager.value.page || 1,
      limit: params.limit || pager.value.limit || 10,
      query: query.value || ''
    })

    message.success(formatCaption(captions.tokensLoaded, {
      count: result.items.length
    }))
  } catch (error) {
    message.error(captions.tokensLoadError)
  } finally {
    loading.value = false
  }
}

async function applySearch() {
  await load({ page: 1, limit: pager.value.limit || 10 })
}

async function applySearchAfterClear() {
  await nextTick()
  await applySearch()
}

function openCreate() {
  selectedItem.value = null
  editorVisible.value = true
}

function openEdit(row) {
  if (!tokenCanEdit(row)) return

  selectedItem.value = {
    token: row.token,
    user: row.user || row.payload?.user || '',
    scope: normalizeArray(row.scope || row.payload?.scope),
    status: row.status || row.payload?.status || 'active',
    tags: normalizeArray(row.tags || row.payload?.tags),
    active_clients: normalizeActiveClients(row.active_clients || row.payload?.active_clients)
  }

  editorVisible.value = true
}

async function saveItem(item) {
  try {
    await store.dispatch('saveTokenItem', item)
    message.success(item.token ? captions.tokenSaved : captions.tokenCreated)
    editorVisible.value = false
    await load({
      page: item.token ? pager.value.page || 1 : 1,
      limit: pager.value.limit || 10
    })
  } catch {
    message.error(captions.tokenSaveError)
  }
}

async function deleteItem(row) {
  try {
    await store.dispatch('deleteTokenItem', row.token)
    message.success(captions.tokenDeleted)
    await load({
      page: pager.value.page || 1,
      limit: pager.value.limit || 10
    })
  } catch {
    message.error(captions.tokenDeleteError)
  }
}

async function toggleStatus(row) {
  if (!hasAdminToken.value) return

  const current = row.status || row.payload?.status || 'active'
  if (!tokenStatusCanToggle(current)) return

  const nextStatus = current === 'active' ? 'hold' : 'active'

  try {
    await store.dispatch('saveTokenItem', {
      token: row.token,
      user: row.user || row.payload?.user || '',
      scope: normalizeArray(row.scope || row.payload?.scope),
      status: nextStatus,
      tags: normalizeArray(row.tags || row.payload?.tags),
      active_clients: normalizeActiveClients(row.active_clients || row.payload?.active_clients)
    })
    message.success(formatCaption(captions.statusChanged, {
      status: formatStatus(nextStatus)
    }))
    await load({
      page: pager.value.page || 1,
      limit: pager.value.limit || 10
    })
  } catch {
    message.error(captions.statusChangeError)
  }
}

async function saveClientSelection(row, type, value) {
  if (!tokenCanEdit(row)) return

  const activeClients = normalizeActiveClients(row.active_clients || row.payload?.active_clients)
  activeClients[type] = normalizeArray(value)

  try {
    await store.dispatch('saveTokenItem', {
      token: row.token,
      user: row.user || row.payload?.user || '',
      scope: normalizeArray(row.scope || row.payload?.scope),
      status: row.status || row.payload?.status || 'active',
      tags: normalizeArray(row.tags || row.payload?.tags),
      active_clients: activeClients
    })
    message.success(captions.clientSaved)
    await load({
      page: pager.value.page || 1,
      limit: pager.value.limit || 10
    })
  } catch {
    message.error(captions.clientSaveError)
  }
}

function clientSelector(row, type) {
  const options = clientOptions(row, type)
  const value = normalizeActiveClients(row.active_clients || row.payload?.active_clients)[type]
  const disabled = !tokenCanEdit(row) || !options.length
  const records = value.map(uid => findClientRecord(row, type, uid)).filter(Boolean)

  const select = () => h(NSelect, {
    value,
    options,
    size: 'small',
    multiple: true,
    clearable: true,
    disabled,
    placeholder: 'EMPTY',
    maxTagCount: 'responsive',
    consistentMenuWidth: false,
    onUpdateValue: (nextValue) => saveClientSelection(row, type, nextValue || [])
  })

  return h(NTooltip, { placement: 'top' }, {
    trigger: select,
    default: () => value.length
        ? h('div', { class: 'client-tooltip' }, value.map(uid => {
          const record = records.find(item => item?.uid === uid)
          const registeredAt = formatDateTime(record?.first_seen || record?.last_seen || '')
          return h('div', { class: 'client-tooltip-row' }, [
            h('div', [
              h('span', 'UID: '),
              h('span', { class: 'mono' }, uid)
            ]),
            h('div', [
              h('span', tooltips.registeredAt),
              h('span', { class: 'mono' }, registeredAt)
            ])
          ])
        }))
        : tooltips.noKnownClients
  })
}

function clientOptions(row, type) {
  const known = row.known_clients || row.payload?.known_clients || {}
  const items = Array.isArray(known[type]) ? known[type] : []

  return items
      .map(item => {
        const uid = typeof item === 'string' ? item : item?.uid || ''
        return uid ? {
          label: maskClientUid(uid),
          value: uid
        } : null
      })
      .filter(Boolean)
}

function findClientRecord(row, type, uid) {
  if (!uid) return null
  const known = row.known_clients || row.payload?.known_clients || {}
  const items = Array.isArray(known[type]) ? known[type] : []
  return items
      .map(item => typeof item === 'string' ? { uid: item } : item)
      .find(item => item?.uid === uid) || null
}

function normalizeActiveClients(value) {
  const source = value && typeof value === 'object' ? value : {}
  return {
    web: normalizeArray(source.web),
    plugin: normalizeArray(source.plugin)
  }
}

async function copyToken(token) {
  await navigator.clipboard.writeText(token)
  message.success(captions.tokenCopied)
}

function tokenCopyCell(row) {
  const token = row.token || ''
  const masked = maskToken(token)

  return h(NTooltip, {}, {
    trigger: () => h('span', {
      style: 'display: inline-flex; align-items: center; gap: 6px; cursor: pointer;',
      onClick: () => copyToken(token)
    }, [
      h('span', { class: 'mono' }, masked),
      h(NIcon, { size: 15 }, { default: () => h(CopyOutline) })
    ]),
    default: () => formatCaption(captions.copyToken, { token })
  })
}

function formatDateTime(value) {
  if (!value) return '—'
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return value
  return date.toLocaleString('ru-RU')
}

function iconButton({ title, icon, tone, onClick, tooltip = true, disabled = false }) {
  const color = tone === 'delete' ? '#d03050' : '#f0a020'
  const button = () => h(NButton, {
      circle: true,
      quaternary: true,
      size: 'small',
      title,
      disabled,
      style: {
        color: disabled ? 'rgba(31, 34, 37, 0.28)' : color,
        borderColor: disabled ? 'rgba(31, 34, 37, 0.18)' : color
      },
      class: ['user-action-button', `user-action-button--${tone}`],
      onClick
    }, {
      icon: () => h(NIcon, { size: 16 }, {
        default: () => h(icon, { size: 16, strokeWidth: 1.8 })
      })
    })

  if (!tooltip) return button()

  return h(NTooltip, {}, {
    trigger: button,
    default: () => title
  })
}

function normalizeArray(value) {
  if (Array.isArray(value)) return value
  if (typeof value === 'string') {
    return value.split(',').map(item => item.trim()).filter(Boolean)
  }
  return []
}

function maskToken(token) {
  if (!token) return ''
  if (token.length <= 14) return token
  return `${token.slice(0, 8)}...${token.slice(-6)}`
}

function maskClientUid(uid) {
  if (!uid) return ''
  if (uid.length <= 16) return uid
  return `${uid.slice(0, 7)}...${uid.slice(-6)}`
}

function formatStatus(status) {
  if (status === 'active') return captions.statusActive
  if (status === 'hold') return captions.statusHold
  if (status === 'revoked') return captions.statusRevoked
  if (status === 'disabled' || status === 'inactive') return captions.statusDisabled
  return status || captions.statusActive
}

function tokenStatusTagType(status) {
  if (status === 'active') return 'success'
  if (status === 'revoked' || status === 'disabled' || status === 'inactive') return 'error'
  return 'warning'
}

function tokenStatusCanToggle(status) {
  return status === 'active' || status === 'hold'
}

function tokenCanEdit(row) {
  const status = row.status || row.payload?.status || 'active'
  return status !== 'revoked'
}

function formatScope(scope) {
  const labels = {
    admin: captions.scopeAdmin,
    upload: captions.scopeUpload,
    activity: captions.scopeActivity,
    dictionary: captions.scopeDictionary
  }

  return labels[scope] || scope
}

onMounted(() => {
  load({ page: 1, limit: pager.value.limit || 10 })
})
</script>

<style scoped>
.users-add-button {
  color: #18a058 !important;
  border: 1px solid #18a058 !important;
}

.users-add-button :deep(svg) {
  color: currentColor;
  stroke: currentColor;
}

.user-action-button {
  background: transparent;
  border: 1px solid currentColor !important;
}

.user-action-button--edit {
  color: #f0a020 !important;
}

.user-action-button--delete {
  color: #d03050 !important;
}

.user-action-button :deep(svg) {
  color: currentColor;
  stroke: currentColor;
}

.client-tooltip-row + .client-tooltip-row {
  margin-top: 8px;
  padding-top: 8px;
  border-top: 1px solid rgba(255, 255, 255, 0.18);
}

</style>
