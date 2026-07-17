<template>
  <n-modal :show="show" @update:show="emit('update:show', $event)">
    <n-card style="width: 860px" :title="modalTitle">
      <n-form label-placement="top">
        <div class="form-row-4">
          <n-form-item :label="texts.fields.type">
            <n-select
                :value="draft.type"
                :options="typeOptions"
                @update:value="draft.type = $event"
            />
          </n-form-item>

          <n-form-item :label="texts.fields.publicationId">
            <n-select
                :value="draft.publication_id"
                :options="publicationOptions"
                filterable
                tag
                :placeholder="texts.placeholders.newPublication"
                @update:value="draft.publication_id = $event"
            />
          </n-form-item>

          <n-form-item :label="texts.fields.linkToken">
            <n-select
                :value="draft.token"
                :options="tokenOptions"
                filterable
                tag
                :placeholder="texts.placeholders.newToken"
                @update:value="draft.token = $event"
            />
          </n-form-item>

          <n-form-item v-if="draft.type !== 'pixel'" :label="texts.fields.language">
            <n-select
                :value="draft.lang"
                :options="languageOptions"
                @update:value="draft.lang = $event"
            />
          </n-form-item>
        </div>

        <RedirectForm v-if="draft.type === 'redirect'" :draft="draft" :texts="texts" />
        <PageForm v-if="draft.type === 'page'" :draft="draft" :texts="texts" />
        <DownloadForm v-if="draft.type === 'download'" :draft="draft" :texts="texts" />
        <PixelForm v-if="draft.type === 'pixel'" :draft="draft" :texts="texts" />

        <AdvancedDraftOptions
            :draft="draft"
            :recipients-text="recipientsText"
            :texts="texts"
            :publication-locked="publicationLocked"
            @update:recipients-text="recipientsText = $event"
        />

        <n-space justify="end" style="margin-top: 18px">
          <n-button @click="emit('update:show', false)">
            {{ texts.modal.cancel }}
          </n-button>

          <n-button
              type="primary"
              :loading="draftSaving"
              :disabled="draftSaving"
              @click="saveDraft"
          >
            {{ texts.modal.saveDraft }}
          </n-button>
        </n-space>
      </n-form>
    </n-card>
  </n-modal>
</template>

<script setup>
import { computed, reactive, ref, watch } from 'vue'
import { useStore } from 'vuex'
import { useMessage } from 'naive-ui'

import AdvancedDraftOptions from './AdvancedDraftOptions.vue'
import RedirectForm from './forms/RedirectForm.vue'
import DownloadForm from './forms/DownloadForm.vue'
import PageForm from './forms/PageForm.vue'
import PixelForm from './forms/PixelForm.vue'
import { getDraftAsset, putDraftAsset } from '../services/draftAssetStore'
import { formatCaption, getCaptions } from '../captions'

const props = defineProps({
  show: Boolean,
  editDraft: {
    type: Object,
    default: null
  }
})

const emit = defineEmits(['update:show'])

const store = useStore()
const message = useMessage()

const editorCaptions = getCaptions('linkEditor')
const texts = {
  modal: editorCaptions.titles,
  fields: editorCaptions.labels,
  actions: editorCaptions.actions,
  tabs: {
    markdown: 'Markdown',
    preview: 'Preview',
    ...(editorCaptions.tabs || {})
  },
  pageModes: {
    markdown: 'Markdown',
    files: editorCaptions.tabs.files
  },
  placeholders: editorCaptions.placeholders,
  messages: editorCaptions.messages,
  tooltips: editorCaptions.hints,
  pageForm: getCaptions('pageForm'),
  pixelForm: getCaptions('pixelForm')
}

const typeOptions = [
  { label: editorCaptions.types.redirect, value: 'redirect' },
  { label: editorCaptions.types.page, value: 'page' },
  { label: editorCaptions.types.download, value: 'download' },
  { label: editorCaptions.types.pixel, value: 'pixel' }
]

const languageOptions = [
  { label: 'Auto', value: 'auto' },
  { label: 'English', value: 'en' },
  { label: 'Русский', value: 'ru' },
  { label: 'Español', value: 'es' }
]

const draft = reactive(makeEmptyDraft())
const recipientsText = ref('')
const draftSaving = ref(false)

const modalTitle = computed(() => {
  const title = props.editDraft ? texts.modal.editTitle : texts.modal.createTitle
  return `${title}: ${draft.type}`
})

const publicationLocked = computed(() => {
  if (!draft.publication_id) return false

  return (store.state.links || [])
      .some(item => (item.publication_id || item.publication) === draft.publication_id)
})

const tokenOptions = computed(() => {
  if (!draft.publication_id) {
    return []
  }

  const tokens = (store.state.drafts || [])
      .filter(item => getPublicationId(item) === draft.publication_id)
      .filter(item => getPublicationType(item) === draft.type)
      .map(item => item.token)
      .filter(token => token && token !== 'X-User-Token')

  return [
    { label: texts.placeholders.newToken, value: '' },
    ...Array.from(new Set(tokens)).map(token => ({
      label: token,
      value: token
    }))
  ]
})

const publicationOptions = computed(() => {
  return Array.from(new Set(
      (store.state.drafts || [])
          .map(item => item.publication_id)
          .filter(Boolean)
  )).map(publicationId => ({
    label: publicationId,
    value: publicationId
  }))
})

watch(
    () => props.show,
    (value) => {
      if (!value) return
      resetDraft(props.editDraft || makeEmptyDraft())
    }
)

watch(
    () => draft.publication_id,
    (value, oldValue) => {
      if (!value || value === oldValue) return
      applyPublicationDefaults(value)
    }
)

watch(
    () => draft.token,
    (value, oldValue) => {
      if (!value || value === oldValue || !draft.publication_id) return
      if (clearTokenIfTypeMismatch(value)) return
      applyTokenDraft(draft.publication_id, value)
    }
)

watch(
    () => draft.type,
    () => {
      if (draft.token) {
        clearTokenIfTypeMismatch(draft.token)
      }

      if (draft.type === 'pixel') {
        draft.lang = 'auto'
        draft.form.password = ''
        draft.fresh_until = -1
        draft.remaining_clicks = -1
        draft.sticky = false
        draft.image = ''
        draft.imageDataUrl = ''
        draft.imageDataKey = ''
        draft.imageFile = null
        draft.fileDataUrl = ''
        draft.fileDataKey = ''
        draft.fileName = ''
        draft.file = null
      }
    }
)

function makeEmptyDraft() {
  return {
    draft_id: '',
    publication_id: '',
    token: '',
    type: 'redirect',
    status: 'draft',
    subj: '',
    mails: [],
    sticky: false,
    pre: '',
    link: '',
    post: '',
    fresh_until: -1,
    remaining_clicks: -1,
    lang: 'auto',
    image: '',
    imageDataUrl: '',
    imageDataKey: '',
    imageFile: null,
    fileDataUrl: '',
    fileDataKey: '',
    fileName: '',
    file: null,
    form: {
      target_url: '',
      title: '',
      description: '',
      filename: '',
      entry_md: 'page.md',
      markdownText: '',
      pageMode: 'markdown',
      files: [],
      password: '',
      password_hint: ''
    }
  }
}

function resetDraft(source) {
  Object.assign(draft, makeEmptyDraft(), cloneDraft(source))

  if (draft.token === 'X-User-Token') {
    draft.token = ''
  }

  recipientsText.value = Array.isArray(draft.mails)
      ? draft.mails.join(', ')
      : ''

  restoreDraftAssets()
}

function applyPublicationDefaults(publicationId) {
  const source = getPublicationDefaultsSource(publicationId)

  if (!source) return

  draft.subj = source.subj || ''
  recipientsText.value = Array.isArray(source.mails)
      ? source.mails.join(', ')
      : ''
}

function getPublicationDefaultsSource(publicationId) {
  return (store.state.drafts || [])
      .find(item => item.publication_id === publicationId && item.draft_id !== draft.draft_id) ||
      (store.state.links || [])
          .find(item => (item.publication_id || item.publication) === publicationId)
}

function applyTokenDraft(publicationId, token) {
  const source = (store.state.drafts || [])
      .find(item =>
          item.publication_id === publicationId &&
          item.token === token &&
          getPublicationType(item) === draft.type
      )

  if (!source || source.draft_id === draft.draft_id) return

  resetDraft(source)
}

function clearTokenIfTypeMismatch(token) {
  const source = findTokenSource(draft.publication_id, token)

  if (!source || getPublicationType(source) === draft.type) return false

  draft.token = ''
  message.warning(texts.messages.wrongTokenType)
  return true
}

function findTokenSource(publicationId, token) {
  return (store.state.drafts || []).find(item =>
      getPublicationId(item) === publicationId &&
      item.token === token
  )
}

function getPublicationId(item) {
  return item.publication_id || item.publication || ''
}

function getPublicationType(item) {
  return item.type || item.raw?.type || ''
}

function cloneDraft(value) {
  const result = clonePlain(value)

  result.imageFile = value?.imageFile || null
  result.file = value?.file || null
  result.form = result.form || {}
  result.form.files = Array.isArray(value?.form?.files)
      ? value.form.files.map(clonePageFileEntry)
      : []

  return result
}

function clonePlain(value) {
  return JSON.parse(JSON.stringify(value || {}))
}

function makeId() {
  if (crypto?.randomUUID) return crypto.randomUUID()
  return `draft-${Date.now()}-${Math.random().toString(16).slice(2)}`
}

function generateTokenByType(type) {
  return `${type}-${Math.random().toString(36).slice(2, 8)}`
}

async function saveDraft() {
  if (draftSaving.value) return

  draftSaving.value = true

  try {
    if (!draft.publication_id) {
      draft.publication_id = `pub-${Date.now().toString(36)}`
    }

    if (!draft.token || draft.token === 'X-User-Token') {
      draft.token = generateTokenByType(draft.type)
    }

    const draftId = draft.draft_id || makeId()

    await persistDraftAssets(draftId)

    const payload = {
      ...clonePlain(draft),
      draft_id: draftId,
      status: 'draft',
      mails: recipientsText.value
          .split(',')
          .map(item => item.trim())
          .filter(Boolean),
      created_at: draft.created_at || new Date().toISOString()
    }

    payload.imageFile = draft.imageFile
    payload.file = draft.file
    payload.form = payload.form || {}
    payload.form.files = Array.isArray(draft.form?.files)
        ? draft.form.files.map(clonePageFileEntry)
        : []

    store.commit('addDraft', payload)
    message.success(texts.messages.draftSaved)
    emit('update:show', false)
  } catch (error) {
    message.error(formatCaption(texts.messages.draftSaveError, { error: formatDraftError(error) }))
  } finally {
    draftSaving.value = false
  }
}

async function persistDraftAssets(draftId) {
  const imageDataUrl = draft.imageDataUrl ||
      (draft.imageFile instanceof File ? await readFileAsDataUrl(draft.imageFile) : '')

  if (imageDataUrl) {
    draft.imageDataKey = await putDraftAsset(`${draftId}:image`, imageDataUrl)
    draft.imageDataUrl = ''
  }

  const fileDataUrl = draft.fileDataUrl ||
      (draft.file instanceof File ? await readFileAsDataUrl(draft.file) : '')

  if (fileDataUrl) {
    draft.fileDataKey = await putDraftAsset(`${draftId}:file`, fileDataUrl)
    draft.fileDataUrl = ''
  }

  if (Array.isArray(draft.form?.files)) {
    const files = []

    for (const item of draft.form.files) {
      const entry = clonePageFileEntry(item)
      const source = getPageFileSource(item)

      if (source instanceof File) {
        entry.fileDataKey = await putDraftAsset(
            `${draftId}:page-file:${entry.name || source.name}`,
            await readFileAsDataUrl(source)
        )
        entry.file = source
      }

      files.push(entry)
    }

    draft.form.files = files
  }
}

async function restoreDraftAssets() {
  try {
    if (draft.imageDataKey && !draft.imageDataUrl) {
      draft.imageDataUrl = await getDraftAsset(draft.imageDataKey)
    }

    if (draft.fileDataKey && !draft.fileDataUrl) {
      draft.fileDataUrl = await getDraftAsset(draft.fileDataKey)
    }

    if (Array.isArray(draft.form?.files)) {
      draft.form.files = await Promise.all(
          draft.form.files.map(restorePageFileEntry)
      )
    }
  } catch (error) {
    message.error(formatCaption(texts.messages.draftRestoreError, { error: formatDraftError(error) }))
  }
}

function clonePageFileEntry(item) {
  return {
    name: item?.name || item?.file?.name || '',
    file: getPageFileSource(item),
    fileDataKey: item?.fileDataKey || ''
  }
}

function getPageFileSource(item) {
  return item?.file instanceof File ? item.file : null
}

async function restorePageFileEntry(item) {
  const entry = clonePageFileEntry(item)

  if (!entry.file && entry.fileDataKey) {
    entry.file = dataUrlToFile(await getDraftAsset(entry.fileDataKey), entry.name)
  }

  return entry
}

function readFileAsDataUrl(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader()
    reader.onload = () => resolve(typeof reader.result === 'string' ? reader.result : '')
    reader.onerror = () => reject(reader.error || new Error('file read failed'))
    reader.readAsDataURL(file)
  })
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

function formatDraftError(error) {
  return error?.message || texts.messages.unknownError
}
</script>
<style scoped>
.form-row-2 {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 12px;
}

.form-row-3 {
  display: grid;
  grid-template-columns: 1fr 1fr 1fr;
  gap: 12px;
}

.form-row-4 {
  display: grid;
  grid-template-columns: 0.9fr 1.35fr 1.35fr 0.9fr;
  gap: 12px;
}
</style>
