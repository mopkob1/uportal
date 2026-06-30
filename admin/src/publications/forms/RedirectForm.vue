<template>
  <div class="redirect-anchor-row">
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

  <div class="redirect-url-row" :class="{ 'has-preview': previewUrl }">
    <n-form-item :label="texts.fields.targetUrl">
      <n-input
          :value="draft.form.target_url"
          @update:value="draft.form.target_url = $event"
      >
        <template #suffix>
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
        </template>
      </n-input>

      <input
          ref="previewInput"
          class="redirect-preview-input"
          type="file"
          accept="image/*"
          @change="onPreviewChange"
      >
    </n-form-item>

    <n-form-item :label="texts.fields.delay">
      <n-input-number
          :value="Number(draft.form.delay || 0)"
          :min="0"
          :step="1"
          style="width: 100%"
          @update:value="draft.form.delay = String($event || 0)"
      />
    </n-form-item>

    <n-form-item
        v-if="previewUrl"
        label=" "
        class="redirect-preview-item"
    >
      <button
          class="redirect-preview-thumb"
          type="button"
          :title="texts.actions.clearPreview"
          @click="clearPreview"
      >
        <img :src="previewUrl" :alt="draft.image || texts.actions.uploadPreview">
      </button>
    </n-form-item>
  </div>
</template>

<script setup>
import { ImagePlus } from 'lucide-vue-next'
import { onBeforeUnmount, ref, watch } from 'vue'

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
const previewUrl = ref('')
const previewInput = ref(null)

function openPreviewDialog() {
  previewInput.value?.click()
}

function onPreviewChange(event) {
  const file = event.target.files?.[0] || null
  setPreviewFile(file)
  draft.imageFile = file
  draft.image = file?.name || ''
  draft.imageDataKey = ''

  if (event.target) {
    event.target.value = ''
  }
}

function clearPreview() {
  setPreviewFile(null)
  draft.imageFile = null
  draft.image = ''
  draft.imageDataUrl = ''
  draft.imageDataKey = ''
}

function setPreviewFile(file) {
  setPreviewObjectUrl(file)

  if (file) {
    savePreviewDataUrl(file)
  }
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

function savePreviewDataUrl(file) {
  const reader = new FileReader()

  reader.onload = () => {
    draft.imageDataUrl = typeof reader.result === 'string' ? reader.result : ''
  }

  reader.readAsDataURL(file)
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

onBeforeUnmount(() => {
  if (previewUrl.value?.startsWith('blob:')) {
    URL.revokeObjectURL(previewUrl.value)
  }
})
</script>

<style scoped>
.redirect-anchor-row {
  display: grid;
  grid-template-columns: 1fr 1.4fr 1fr;
  gap: 16px;
}

.redirect-url-row {
  display: grid;
  grid-template-columns: minmax(0, 1fr) 120px;
  gap: 10px;
  align-items: start;
}

.redirect-url-row.has-preview {
  grid-template-columns: minmax(0, 1fr) 120px 72px;
}

.redirect-preview-input {
  display: none;
}

.redirect-preview-item {
  margin: 0;
}

.redirect-preview-thumb {
  width: 72px;
  height: 34px;
  padding: 0;
  overflow: hidden;
  cursor: pointer;
  background: transparent;
  border: 1px solid #dcdfe6;
  border-radius: 3px;
}

.redirect-preview-thumb img {
  display: block;
  width: 100%;
  height: 100%;
  object-fit: cover;
}
</style>
