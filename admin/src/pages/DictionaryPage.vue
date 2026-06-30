<template>
  <div class="app-page">
    <div class="page-header">
      <div>
        <h2>{{ caps.title }}</h2>
        <div class="muted">
          {{ caps.subtitle }}
        </div>
      </div>
    </div>

    <n-card style="margin-bottom: 16px">
      <n-space vertical size="large">
        <div class="dictionary-toolbar">
          <n-input
            v-model:value="search"
            class="dictionary-search"
            style="width: 100%"
            clearable
            :placeholder="caps.searchPlaceholder"
          >
            <template #prefix>
              <n-button
                circle
                quaternary
                size="small"
                class="dictionary-refresh-button"
                :loading="loading"
                :title="caps.refresh"
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

          <n-button
            circle
            quaternary
            class="dictionary-add-button"
            :title="caps.addItem"
            @click="openCreate"
          >
            <template #icon>
              <n-icon>
                <Plus :size="16" :stroke-width="1.8" />
              </n-icon>
            </template>
          </n-button>
        </div>

        <n-data-table
          :columns="columns"
          :data="filteredItems"
          :loading="loading"
          :pagination="{ pageSize: 10 }"
        />
      </n-space>
    </n-card>

    <DictionaryEditorModal
      v-model:show="editorVisible"
      :item="selectedItem"
      @save="saveItem"
    />
  </div>
</template>

<script setup>
import { computed, h, onMounted, ref } from 'vue'
import { useStore } from 'vuex'
import { Pencil, Plus, RefreshCw, Trash2 } from 'lucide-vue-next'
import { NButton, NIcon, NPopconfirm, NSpace, NTag, useMessage } from 'naive-ui'
import DictionaryEditorModal from '../dictionary/DictionaryEditorModal.vue'
import { formatCaption, getCaptions } from '../captions'

const store = useStore()
const message = useMessage()
const caps = getCaptions('dictionaryPage')

const search = ref('')
const editorVisible = ref(false)
const selectedItem = ref(null)

const loading = computed(() => store.state.dictionary.loading)
const items = computed(() => store.state.dictionary)

const filteredItems = computed(() => {
  const needle = search.value.trim().toLowerCase()
  if (!needle) return items.value

  return items.value.filter((item) => {
    return [
      item.id,
      item.pre,
      item.post,
      item.url,
      item.anchor,
      item.type,
      item.tags
    ].some((value) => String(value || '').toLowerCase().includes(needle))
  })
})

const columns = [
  {
    title: 'anchor',
    key: 'anchor',
    minWidth: 160,
    render(row) {
      return h('strong', row.anchor || '—')
    }
  },
  {
    title: 'type',
    key: 'type',
    width: 120,
    render(row) {
      return h(NTag, { size: 'small' }, { default: () => row.type || 'redirect' })
    }
  },
  {
    title: 'url',
    key: 'url',
    minWidth: 220,
    render(row) {
      return h('span', { class: 'mono' }, row.url || '—')
    }
  },
  {
    title: 'pre / post',
    key: 'text',
    minWidth: 260,
    render(row) {
      const pre = row.pre ? `pre: ${row.pre}` : ''
      const post = row.post ? `post: ${row.post}` : ''
      return h('div', [
        h('div', { class: 'muted' }, pre || 'pre: —'),
        h('div', { class: 'muted' }, post || 'post: —')
      ])
    }
  },
  {
    title: 'tags',
    key: 'tags',
    minWidth: 160,
    render(row) {
      const tags = String(row.tags || '')
        .split(',')
        .map((tag) => tag.trim())
        .filter(Boolean)

      if (!tags.length) return h('span', { class: 'muted' }, '—')

      return h(NSpace, { size: 4 }, {
        default: () => tags.map((tag) =>
          h(NTag, { size: 'small', round: true }, { default: () => tag })
        )
      })
    }
  },
  {
    title: caps.actions,
    key: 'actions',
    width: 230,
    render(row) {
      return h(NSpace, {}, {
        default: () => [
          h(NButton, {
            quaternary: true,
            size: 'tiny',
            class: 'dictionary-edit-button',
            title: caps.edit,
            style: {
              color: '#f0a020'
            },
            onClick: () => openEdit(row)
          }, {
            icon: () => h(NIcon, null, {
              default: () => h(Pencil, { size: 14, strokeWidth: 1.9 })
            })
          }),

          h(NPopconfirm, {
            onPositiveClick: () => deleteItem(row)
          }, {
            trigger: () => h(NButton, {
              quaternary: true,
              size: 'tiny',
              class: 'dictionary-delete-button',
              title: caps.delete,
              style: {
                color: '#d03050'
              },
              disabled: !row.id
            }, {
              icon: () => h(NIcon, null, {
                default: () => h(Trash2, { size: 14, strokeWidth: 1.9 })
              })
            }),
            default: () => formatCaption(caps.deleteConfirm, { item: row.anchor || row.id })
          })
        ]
      })
    }
  }
]

onMounted(load)

async function load() {
  try {
    const rows = await store.dispatch('loadDictionary')
    message.success(formatCaption(caps.loaded, { count: rows.length }))
  } catch {
    message.error(caps.loadError)
  }
}

function openCreate() {
  selectedItem.value = null
  editorVisible.value = true
}

function openEdit(row) {
  selectedItem.value = { ...row }
  editorVisible.value = true
}

async function saveItem(item) {
  try {
    await store.dispatch('saveDictionaryItem', item)
    message.success(item.id ? caps.saved : caps.created)
    editorVisible.value = false
  } catch {
    message.error(caps.saveError)
  }
}

async function deleteItem(row) {
  try {
    await store.dispatch('deleteDictionaryItem', row.id)
    message.success(caps.deleted)
  } catch {
    message.error(caps.deleteError)
  }
}
</script>
<style scoped>
.dictionary-refresh-button {
  color: rgba(31, 34, 37, 0.42);
}

.dictionary-refresh-button:hover {
  color: rgba(31, 34, 37, 0.72);
}

.dictionary-toolbar {
  display: flex;
  width: 100%;
  align-items: center;
  gap: 12px;
}

.dictionary-search {
  width: 100%;
  flex: 1 1 auto;
  min-width: 0;
}

.dictionary-add-button {
  flex: 0 0 auto;
  color: #18a058 !important;
  border: 1px solid #18a058 !important;
}

.dictionary-add-button :deep(svg) {
  color: currentColor;
  stroke: currentColor;
}

.dictionary-edit-button {
  color: #f0a020 !important;
  --n-padding: 0 3px;
}

.dictionary-edit-button :deep(svg) {
  color: currentColor;
  stroke: currentColor;
}

.dictionary-delete-button {
  color: #d03050 !important;
  --n-padding: 0 3px;
}

.dictionary-delete-button :deep(svg) {
  color: currentColor;
  stroke: currentColor;
}
</style>
