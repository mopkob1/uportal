<template>
  <div class="page-anchor-row">
    <n-form-item :label="texts.fields.pre">
      <n-input
          :value="draft.pre"
          @update:value="draft.pre = $event"
      />
    </n-form-item>

    <n-form-item :label="texts.fields.anchor">
      <n-input
          :value="draft.link"
          @update:value="draft.link = $event"
      />
    </n-form-item>

    <n-form-item :label="texts.fields.post">
      <n-input
          :value="draft.post"
          @update:value="draft.post = $event"
      />
    </n-form-item>
  </div>

  <div class="page-title-row" :class="{ 'has-preview': previewUrl }">
    <n-form-item :label="texts.fields.title">
      <n-input
          :value="draft.form.title"
          @update:value="draft.form.title = $event"
      />
    </n-form-item>

    <n-form-item v-if="!previewUrl" :label="texts.fields.previewImage">
      <n-input
          :value="draft.image"
          @update:value="draft.image = $event"
      >
        <template #suffix>
          <span class="page-preview-actions">
            <n-button
                quaternary
                size="tiny"
                type="button"
                :title="texts.actions.uploadPreview"
                @click.stop="openPreviewDialog"
            >
              <template #icon>
                <n-icon>
                  <ImagePlus :size="15" :stroke-width="1.8" />
                </n-icon>
              </template>
            </n-button>

            <n-button
                v-if="draft.image"
                quaternary
                size="tiny"
                type="button"
                :title="texts.actions.clearPreview"
                @click.stop="clearPreview"
            >
              <template #icon>
                <n-icon>
                  <X :size="15" :stroke-width="1.8" />
                </n-icon>
              </template>
            </n-button>
          </span>
        </template>
      </n-input>
    </n-form-item>

    <n-form-item
        v-if="previewUrl"
        label=" "
        class="page-preview-item"
    >
      <button
          class="page-preview-thumb"
          type="button"
          :title="texts.actions.clearPreview"
          @click="clearPreview"
      >
        <img :src="previewUrl" :alt="draft.image || texts.actions.uploadPreview">
      </button>
    </n-form-item>

    <input
        ref="previewInput"
        class="page-hidden-input"
        type="file"
        accept="image/*"
        @change="onPreviewChange"
    >
  </div>

  <n-form-item :label="texts.fields.description">
    <n-input
        :value="draft.form.description"
        type="textarea"
        :autosize="{ minRows: 2 }"
        @update:value="draft.form.description = $event"
    />
  </n-form-item>

  <n-tabs
      type="card"
      :value="draft.form.pageMode"
      @update:value="draft.form.pageMode = $event"
  >
    <n-tab-pane name="markdown" :tab="texts.pageModes.markdown">
      <n-tabs class="page-subtabs" type="line">
        <n-tab-pane name="markdown" :tab="pageTexts.tabs.text">
          <n-input
              class="markdown-editor"
              :value="draft.form.markdownText"
              type="textarea"
              :autosize="false"
              @update:value="draft.form.markdownText = $event"
          />
        </n-tab-pane>

        <n-tab-pane name="preview" :tab="pageTexts.tabs.preview">
          <div
              class="markdown-preview"
              @click="openPreviewLink"
              v-html="renderedMarkdown"
          ></div>
        </n-tab-pane>
      </n-tabs>
    </n-tab-pane>

    <n-tab-pane name="files">
      <template #tab>
        <span class="page-files-tab">
          {{ texts.pageModes.files }}
        </span>
      </template>

      <n-tabs class="page-subtabs" type="line">
        <n-tab-pane name="upload">
          <template #tab>
            <span class="page-files-upload-tab">
              {{ pageTexts.tabs.upload }}
              <n-button
                  quaternary
                  circle
                  size="tiny"
                  type="button"
                  :title="texts.actions.uploadPageFiles"
                  @click.stop.prevent="openPageFilesDialog"
              >
                <template #icon>
                  <n-icon>
                    <FileUp :size="14" :stroke-width="1.8" />
                  </n-icon>
                </template>
              </n-button>
            </span>
          </template>

          <div class="page-file-tags-frame">
            <span class="page-file-tags-count">
              {{ formatText(pageTexts.filesCount, { count: pageFiles.length }) }}
            </span>

            <div class="page-file-tags">
              <template
                  v-for="file in pageFiles"
                  :key="getPageFileName(file)"
              >
                <n-tooltip
                    v-if="isImageFile(file) && pageFilePreviewUrl(file)"
                    trigger="hover"
                    placement="top"
                >
                  <template #trigger>
                    <n-tag
                        class="page-file-tag"
                        :class="getPageFileClass(file)"
                        :bordered="true"
                        closable
                        @close.stop="removePageFile(file)"
                    >
                      <span class="page-file-tag-content">
                        <span class="page-file-name">{{ getPageFileName(file) }}</span>
                      </span>
                    </n-tag>
                  </template>

                  <img
                      class="page-file-preview"
                      :src="pageFilePreviewUrl(file)"
                      :alt="getPageFileName(file)"
                  >
                </n-tooltip>

                <n-tag
                    v-else
                    class="page-file-tag"
                    :class="{
                      [getPageFileClass(file)]: true,
                      'is-md': isMdFile(file),
                      'is-selected': isSelectedEntryFile(file)
                    }"
                    :bordered="true"
                    closable
                    @click="selectEntryFile(file)"
                    @close.stop="removePageFile(file)"
                >
                  <span class="page-file-tag-content">
                    <n-icon
                        v-if="isSelectedEntryFile(file)"
                        class="page-file-check"
                        size="14"
                    >
                        <Check :size="14" :stroke-width="2" />
                      </n-icon>
                    <span class="page-file-name">{{ getPageFileName(file) }}</span>
                  </span>
                </n-tag>
              </template>

              <span v-if="!pageFiles.length" class="page-files-empty">
                {{ pageTexts.empty }}
              </span>
            </div>
          </div>

        </n-tab-pane>

        <n-tab-pane
            name="preview"
            :tab="pageTexts.tabs.preview"
            :disabled="!selectedPageMarkdown"
        >
          <div
              class="markdown-preview"
              @click="openPreviewLink"
              v-html="renderedPageFileMarkdown"
          ></div>
        </n-tab-pane>
      </n-tabs>

      <input
          ref="pageFilesInput"
          class="page-hidden-input"
          type="file"
          multiple
          @change="onPageFilesChange"
      >
    </n-tab-pane>
  </n-tabs>
</template>

<script setup>
import { Check, FileUp, ImagePlus, X } from 'lucide-vue-next'
import { computed, onBeforeUnmount, ref, watch } from 'vue'
import MarkdownIt from 'markdown-it'

const props = defineProps({
  draft: {
    type: Object,
    required: true
  },
  texts: {
    type: Object,
    required: true
  }
})

const draft = props.draft
const texts = props.texts
const pageTexts = props.texts.pageForm
const previewInput = ref(null)
const previewUrl = ref('')
const pageFilesInput = ref(null)
const pageFilePreviewUrls = ref({})
const selectedPageMarkdownText = ref('')

const md = new MarkdownIt({
  html: true,
  linkify: true,
  breaks: true
})

function formatText(template, values = {}) {
  return String(template || '').replace(/\{([A-Za-z0-9_]+)\}/g, (match, key) => (
      Object.prototype.hasOwnProperty.call(values, key) ? String(values[key]) : match
  ))
}

const defaultImageRenderer = md.renderer.rules.image || ((tokens, idx, options, env, self) => {
  return self.renderToken(tokens, idx, options)
})

md.renderer.rules.image = (tokens, idx, options, env, self) => {
  const token = tokens[idx]
  const srcIndex = token.attrIndex('src')
  const resolveAssetUrl = env?.resolveAssetUrl

  if (srcIndex >= 0 && typeof resolveAssetUrl === 'function') {
    const resolvedUrl = resolveAssetUrl(token.attrs[srcIndex][1])

    if (resolvedUrl) {
      token.attrs[srcIndex][1] = resolvedUrl
    }
  }

  return defaultImageRenderer(tokens, idx, options, env, self)
}

const renderedMarkdown = computed(() => {
  return renderPageMarkdown(draft.form.markdownText || '')
})

const renderedPageFileMarkdown = computed(() => {
  return renderPageMarkdown(selectedPageMarkdownText.value || '')
})

const pageFiles = computed(() => {
  return Array.isArray(draft.form.files) ? draft.form.files : []
})

const selectedPageMarkdown = computed(() => {
  return pageFiles.value.find(file => isSelectedEntryFile(file)) || null
})

function openPreviewDialog() {
  previewInput.value?.click()
}

function openPageFilesDialog() {
  pageFilesInput.value?.click()
}

function openPreviewLink(event) {
  const link = event.target?.closest?.('a')
  if (!link?.href) return

  event.preventDefault()
  event.stopPropagation()

  const url = new URL(link.getAttribute('href') || link.href, window.location.href)
  window.open(url.href, '_blank', 'noopener,noreferrer')
}

function onPreviewChange(event) {
  const file = event.target.files?.[0] || null

  draft.imageFile = file
  draft.image = file?.name || ''
  draft.imageDataKey = ''

  if (file) {
    savePreviewDataUrl(file)
  }

  if (event.target) {
    event.target.value = ''
  }
}

function clearPreview() {
  setPreviewDataUrl('')
  draft.imageFile = null
  draft.image = ''
  draft.imageDataUrl = ''
  draft.imageDataKey = ''
}

function savePreviewDataUrl(file) {
  const reader = new FileReader()

  reader.onload = () => {
    draft.imageDataUrl = typeof reader.result === 'string' ? reader.result : ''
  }

  reader.readAsDataURL(file)
}

function setPreviewObjectUrl(file) {
  if (previewUrl.value?.startsWith('blob:')) {
    URL.revokeObjectURL(previewUrl.value)
    previewUrl.value = ''
  }

  if (file) {
    previewUrl.value = URL.createObjectURL(file)
  }
}

function setPreviewDataUrl(value) {
  if (previewUrl.value?.startsWith('blob:')) {
    URL.revokeObjectURL(previewUrl.value)
  }

  previewUrl.value = value || ''
}

function onPageFilesChange(event) {
  const selectedFiles = Array.from(event.target.files || [])
  const filesByName = new Map(
      pageFiles.value.map(file => [getPageFileName(file), normalizePageFile(file)])
  )

  for (const file of selectedFiles) {
    filesByName.set(file.name, {
      name: file.name,
      file
    })
  }

  draft.form.files = Array.from(filesByName.values())

  ensureEntryMd()

  if (event.target) {
    event.target.value = ''
  }
}

function removePageFile(file) {
  const name = getPageFileName(file)
  draft.form.files = pageFiles.value
      .filter(item => getPageFileName(item) !== name)
      .map(normalizePageFile)

  if (draft.form.entry_md === name) {
    draft.form.entry_md = getFirstMdFileName()
  }

  if (draft.image === name) {
    draft.image = ''
  }
}

function selectEntryFile(file) {
  if (!isMdFile(file)) return
  draft.form.entry_md = getPageFileName(file)
}

function isSelectedEntryFile(file) {
  return isMdFile(file) && draft.form.entry_md === getPageFileName(file)
}

function ensureEntryMd() {
  if (draft.form.pageMode !== 'files') return

  if (draft.form.entry_md && pageFiles.value.some(file =>
      getPageFileName(file) === draft.form.entry_md && isMdFile(file)
  )) {
    return
  }

  draft.form.entry_md = getFirstMdFileName()
}

function getFirstMdFileName() {
  return getPageFileName(pageFiles.value.find(isMdFile))
}

function normalizePageFile(file) {
  if (file?.file instanceof File) {
    return {
      name: file.name || file.file.name,
      file: file.file
    }
  }

  if (file instanceof File) {
    return {
      name: file.name,
      file
    }
  }

  return {
    name: file?.name || '',
    file: file?.file || null
  }
}

function getPageFileName(file) {
  return file?.name || file?.file?.name || ''
}

function isMdFile(file) {
  return /\.md$/i.test(getPageFileName(file))
}

function isImageFile(file) {
  return /\.(png|jpg|jpeg|gif|webp)$/i.test(getPageFileName(file))
}

function getPageFileClass(file) {
  const name = getPageFileName(file).toLowerCase()

  if (/\.md$/.test(name)) return 'is-ext-md'
  if (/\.(png|jpg|jpeg|gif|webp)$/.test(name)) return 'is-ext-image'
  if (/\.css$/.test(name)) return 'is-ext-css'
  if (/\.html?$/.test(name)) return 'is-ext-html'
  if (/\.(js|mjs|json)$/.test(name)) return 'is-ext-code'

  return 'is-ext-file'
}

function pageFilePreviewUrl(file) {
  return pageFilePreviewUrls.value[getPageFileName(file)] || ''
}

function renderPageMarkdown(source) {
  const { body, meta } = parseMarkdownFrontMatter(source)
  const title = draft.form.title || meta.title || ''
  const description = draft.form.description || meta.description || ''
  const contentHtml = resolveHtmlAssetUrls(md.render(body, {
    resolveAssetUrl: resolvePageAssetUrl
  }))

  return `
    <article class="page-preview-doc">
      ${title ? `<h1 class="page-preview-title">${escapeHtml(title)}</h1>` : ''}
      ${description ? `<p class="page-preview-description">${escapeHtml(description)}</p>` : ''}
      <div class="page-preview-content">${contentHtml}</div>
    </article>
  `
}

function parseMarkdownFrontMatter(source) {
  const text = source || ''

  if (!text.startsWith('---\n') && !text.startsWith('---\r\n')) {
    return {
      body: text,
      meta: {}
    }
  }

  const match = text.match(/^---\r?\n([\s\S]*?)\r?\n---(?:\r?\n|$)/)

  if (!match) {
    return {
      body: text,
      meta: {}
    }
  }

  const meta = {}

  for (const line of match[1].split(/\r?\n/)) {
    const item = line.match(/^([A-Za-z0-9_-]+):\s*(.*)$/)
    if (!item) continue
    meta[item[1]] = item[2]
  }

  return {
    body: text.slice(match[0].length),
    meta
  }
}

function resolvePageAssetUrl(src) {
  const assetName = getAssetName(src)

  if (!assetName) return ''

  return pageFilePreviewUrls.value[assetName] || ''
}

function resolveHtmlAssetUrls(html) {
  return html.replace(/\s(src)=("([^"]*)"|'([^']*)')/gi, (match, attr, quoted, doubleValue, singleValue) => {
    const value = doubleValue ?? singleValue ?? ''
    const resolvedUrl = resolvePageAssetUrl(value)

    if (!resolvedUrl) return match

    const quote = quoted.startsWith("'") ? "'" : '"'
    return ` ${attr}=${quote}${escapeHtmlAttribute(resolvedUrl)}${quote}`
  })
}

function getAssetName(src) {
  if (!src || /^(?:[a-z][a-z\d+.-]*:|\/\/|#)/i.test(src)) {
    return ''
  }

  const [path] = src.split(/[?#]/)
  const name = path.split('/').filter(Boolean).pop() || ''

  try {
    return decodeURIComponent(name)
  } catch {
    return name
  }
}

function escapeHtml(value) {
  return String(value)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;')
}

function escapeHtmlAttribute(value) {
  return escapeHtml(value)
}

let pageMarkdownReadId = 0

async function readSelectedPageMarkdown() {
  const readId = ++pageMarkdownReadId
  const source = normalizePageFile(selectedPageMarkdown.value).file

  if (!(source instanceof File)) {
    selectedPageMarkdownText.value = ''
    return
  }

  try {
    const text = await source.text()
    if (readId === pageMarkdownReadId) {
      selectedPageMarkdownText.value = text
    }
  } catch {
    if (readId === pageMarkdownReadId) {
      selectedPageMarkdownText.value = ''
    }
  }
}

function syncPageFilePreviews() {
  const next = {}

  for (const file of pageFiles.value) {
    const name = getPageFileName(file)
    const source = normalizePageFile(file).file

    if (!name || !isPreviewAssetFile(file) || !(source instanceof File)) continue

    next[name] = pageFilePreviewUrls.value[name] || URL.createObjectURL(source)
  }

  for (const [name, url] of Object.entries(pageFilePreviewUrls.value)) {
    if (!next[name] && url?.startsWith('blob:')) {
      URL.revokeObjectURL(url)
    }
  }

  pageFilePreviewUrls.value = next
}

function isPreviewAssetFile(file) {
  return /\.(png|jpg|jpeg|gif|webp|mp4|webm|mov|m4v|mp3|wav|ogg)$/i.test(getPageFileName(file))
}

watch(
    () => draft.imageFile,
    (file) => {
      if (file instanceof File) {
        setPreviewObjectUrl(file)
      }
    },
    { immediate: true }
)

watch(
    () => draft.imageDataUrl,
    (dataUrl) => {
      if (draft.imageFile instanceof File) return
      setPreviewDataUrl(dataUrl || '')
    },
    { immediate: true }
)

watch(
    () => draft.form.files,
    () => {
      syncPageFilePreviews()
      ensureEntryMd()
      readSelectedPageMarkdown()
    },
    { immediate: true, deep: true }
)

watch(
    () => draft.form.entry_md,
    () => readSelectedPageMarkdown()
)

watch(
    () => draft.form.pageMode,
    () => ensureEntryMd()
)

onBeforeUnmount(() => {
  if (previewUrl.value?.startsWith('blob:')) {
    URL.revokeObjectURL(previewUrl.value)
  }

  for (const url of Object.values(pageFilePreviewUrls.value)) {
    if (url?.startsWith('blob:')) {
      URL.revokeObjectURL(url)
    }
  }
})
</script>

<style scoped>
.page-anchor-row {
  display: grid;
  grid-template-columns: 1fr 1.4fr 1fr;
  gap: 16px;
}

.page-title-row {
  display: grid;
  grid-template-columns: 2fr 1fr;
  gap: 16px;
  align-items: start;
}

.page-title-row.has-preview {
  grid-template-columns: minmax(0, 1fr) 72px;
}

.page-hidden-input {
  display: none;
}

.page-preview-actions {
  display: inline-flex;
  align-items: center;
  gap: 2px;
}

.page-preview-item {
  margin: 0;
}

.page-preview-thumb {
  width: 72px;
  height: 34px;
  padding: 0;
  overflow: hidden;
  cursor: pointer;
  background: transparent;
  border: 1px solid #dcdfe6;
  border-radius: 3px;
}

.page-preview-thumb img {
  display: block;
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.page-subtabs {
  margin-top: -30px;
}

.page-subtabs :deep(.n-tabs-nav) {
  position: relative;
  z-index: 1;
  justify-content: flex-end;
  transform: translateY(6px);
}

.page-subtabs :deep(.n-tabs-tab) {
  padding-bottom: 1px;
  transform: translateY(2px);
}

.page-subtabs :deep(.n-tabs-nav-scroll-wrapper) {
  flex: 0 1 auto;
}

.page-subtabs :deep(.n-tabs-nav-scroll-content) {
  justify-content: flex-end;
}

.page-files-tab {
  display: inline-flex;
  align-items: center;
  gap: 6px;
}

.page-files-upload-tab {
  display: inline-flex;
  align-items: center;
  gap: 4px;
}

.page-file-tags-frame {
  position: relative;
  border: 1px solid rgba(128, 128, 128, 0.18);
  border-radius: 4px;
  background: rgba(128, 128, 128, 0.035);
}

.page-file-tags-count {
  position: absolute;
  top: 0;
  right: 12px;
  z-index: 1;
  padding: 0 8px 2px;
  color: rgba(31, 34, 37, 0.58);
  font-size: 11px;
  line-height: 16px;
  background: #fff;
  box-shadow: 0 0 0 4px #fff;
  transform: translateY(-45%);
}

.page-file-tags {
  display: flex;
  flex-wrap: wrap;
  gap: 10px 12px;
  height: 208px;
  padding: 18px 12px 10px;
  align-content: flex-start;
  align-items: flex-start;
  justify-content: space-between;
  overflow-y: auto;
  scrollbar-gutter: stable;
}

.page-file-tag {
  max-width: 280px;
  cursor: default;
  font-size: 11px;
  line-height: 18px;
  --n-padding: 0 7px;
  --n-height: 20px;
  --n-font-size: 11px;
  --n-border-radius: 3px;
  --n-close-size: 13px;
  --n-close-icon-size: 10px;
  --n-close-margin: 0 0 0 4px;
}

.page-file-tag :deep(.n-tag__content) {
  min-width: 0;
  overflow: hidden;
}

.page-file-tag :deep(.n-tag__close) {
  flex: 0 0 auto;
}

.page-file-tag.is-ext-md {
  color: #1f7a4d;
  background: rgba(24, 160, 88, 0.08);
  border-color: rgba(24, 160, 88, 0.38);
}

.page-file-tag.is-ext-image {
  color: #8a5a00;
  background: rgba(240, 160, 32, 0.1);
  border-color: rgba(240, 160, 32, 0.42);
}

.page-file-tag.is-ext-css {
  color: #1768a8;
  background: rgba(32, 128, 240, 0.09);
  border-color: rgba(32, 128, 240, 0.38);
}

.page-file-tag.is-ext-html {
  color: #9b4d12;
  background: rgba(208, 96, 32, 0.09);
  border-color: rgba(208, 96, 32, 0.38);
}

.page-file-tag.is-ext-code {
  color: #6750a4;
  background: rgba(103, 80, 164, 0.09);
  border-color: rgba(103, 80, 164, 0.36);
}

.page-file-tag.is-ext-file {
  color: rgba(31, 34, 37, 0.72);
  background: rgba(128, 128, 128, 0.08);
  border-color: rgba(128, 128, 128, 0.32);
}

.page-file-tag.is-md {
  cursor: pointer;
}

.page-file-tag.is-selected {
  background: rgba(24, 160, 88, 0.18);
  border-color: rgba(24, 160, 88, 0.72);
}

.page-file-tag-content {
  display: inline-flex;
  min-width: 0;
  max-width: 232px;
  align-items: center;
  gap: 4px;
}

.page-file-name {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.page-file-check {
  color: #18a058;
}

.page-file-preview {
  display: block;
  width: 160px;
  max-height: 120px;
  object-fit: cover;
  border-radius: 4px;
}

.page-files-empty {
  display: flex;
  width: 100%;
  min-height: 100%;
  padding: 0;
  align-items: center;
  justify-content: center;
  color: rgba(31, 34, 37, 0.45);
  font-size: 12px;
  line-height: 1;
  text-align: center;
}

.markdown-editor {
  height: 208px;
}

.markdown-editor :deep(.n-input-wrapper),
.markdown-editor :deep(.n-input__textarea),
.markdown-editor :deep(.n-input__textarea-el) {
  height: 100% !important;
}

.markdown-editor :deep(.n-input__textarea-el) {
  overflow-y: auto !important;
  resize: none;
}

.markdown-preview {
  height: 208px;
  padding: 0;
  overflow-y: auto;
  border: 1px solid rgba(128, 128, 128, 0.25);
  border-radius: 6px;
  background: #f4f6f8;
  line-height: 1.55;
}

.markdown-preview :deep(.page-preview-doc) {
  max-width: 900px;
  min-height: 100%;
  margin: 0 auto;
  padding: 18px 20px 28px;
  color: #1f2933;
  background: #fff;
}

.markdown-preview :deep(.page-preview-title) {
  margin: 0 0 8px;
  padding: 0 0 8px;
  color: #102a43;
  font-size: 24px;
  line-height: 1.18;
  font-weight: 700;
  border-bottom: 1px solid #d9e2ec;
}

.markdown-preview :deep(.page-preview-description) {
  margin: 0 0 18px;
  color: #52606d;
  font-size: 14px;
  line-height: 1.45;
}

.markdown-preview :deep(.page-preview-content) {
  font-size: 14px;
  line-height: 1.65;
}

.markdown-preview :deep(h1) {
  margin: 24px 0 10px;
  color: #102a43;
  font-size: 22px;
  line-height: 1.2;
}

.markdown-preview :deep(h2) {
  margin: 22px 0 10px;
  color: #102a43;
  font-size: 19px;
  line-height: 1.25;
}

.markdown-preview :deep(h3) {
  margin: 18px 0 8px;
  color: #102a43;
  font-size: 16px;
  line-height: 1.3;
}

.markdown-preview :deep(p) {
  margin: 0.7em 0;
}

.markdown-preview :deep(a) {
  color: #0b69ff;
  text-decoration: underline;
}

.markdown-preview :deep(ul),
.markdown-preview :deep(ol) {
  margin: 0.7em 0;
  padding-left: 24px;
}

.markdown-preview :deep(li) {
  margin-bottom: 4px;
}

.markdown-preview :deep(code) {
  padding: 2px 4px;
  border-radius: 4px;
  background: rgba(128, 128, 128, 0.15);
}

.markdown-preview :deep(pre) {
  padding: 10px;
  overflow: auto;
  border-radius: 6px;
  background: #111827;
  color: #f9fafb;
}

.markdown-preview :deep(pre code) {
  padding: 0;
  background: transparent;
  color: inherit;
}

.markdown-preview :deep(img) {
  display: block;
  width: auto;
  max-width: min(100%, 560px);
  max-height: 720px;
  height: auto;
  margin: 18px auto 24px;
  object-fit: contain;
  border-radius: 12px;
  background: #d9e2ec;
  box-shadow: 0 10px 30px rgba(16, 42, 67, 0.08);
}

.markdown-preview :deep(iframe),
.markdown-preview :deep(video) {
  display: block;
  width: 100%;
  max-width: 760px;
  aspect-ratio: 16 / 9;
  height: auto;
  margin: 18px auto 24px;
  border: 0;
  border-radius: 12px;
  background: #000;
  box-shadow: 0 12px 28px rgba(15, 23, 42, 0.18);
}
</style>
