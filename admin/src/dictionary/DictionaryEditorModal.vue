<template>
  <n-modal :show="show" @update:show="emit('update:show', $event)">
    <n-card style="width: 720px" :title="title" :bordered="false">
      <n-form label-placement="top">
        <div class="dictionary-anchor-row">
          <n-form-item :label="caps.preLabel">
            <n-input v-model:value="form.pre" :placeholder="caps.prePlaceholder" />
          </n-form-item>

          <n-form-item :label="caps.anchorLabel">
            <n-input v-model:value="form.anchor" :placeholder="caps.anchorPlaceholder" />
          </n-form-item>

          <n-form-item :label="caps.postLabel">
            <n-input v-model:value="form.post" :placeholder="caps.postPlaceholder" />
          </n-form-item>
        </div>

        <div class="dictionary-url-row">
          <n-form-item :label="caps.urlLabel">
            <n-input v-model:value="form.url" placeholder="https://example.com" />
          </n-form-item>

          <n-form-item :label="caps.tagsLabel">
            <n-input v-model:value="form.tags" placeholder="demo,test" />
          </n-form-item>
        </div>

        <n-space justify="end">
          <n-button @click="emit('update:show', false)">{{ caps.cancel }}</n-button>
          <n-button type="primary" @click="save">{{ caps.save }}</n-button>
        </n-space>
      </n-form>
    </n-card>
  </n-modal>
</template>

<script setup>
import { computed, reactive, watch } from 'vue'
import { getCaptions } from '../captions'

const props = defineProps({
  show: Boolean,
  item: {
    type: Object,
    default: null
  }
})

const emit = defineEmits(['update:show', 'save'])
const caps = getCaptions('dictionaryEditor')

const form = reactive(emptyForm())

const isEdit = computed(() => !!props.item?.id)
const title = computed(() => isEdit.value ? caps.editTitle : caps.newTitle)

watch(
  () => props.show,
  (value) => {
    if (!value) return
    Object.assign(form, props.item ? { ...emptyForm(), ...props.item } : emptyForm())
  }
)

function emptyForm() {
  return {
    id: '',
    pre: '',
    post: '',
    url: '',
    anchor: '',
    type: 'redirect',
    tags: ''
  }
}

function save() {
  emit('save', { ...form, type: 'redirect' })
}
</script>

<style scoped>
.dictionary-anchor-row {
  display: grid;
  grid-template-columns: 1fr 1.4fr 1fr;
  gap: 16px;
}

.dictionary-url-row {
  display: grid;
  grid-template-columns: minmax(0, 1.4fr) minmax(180px, 0.6fr);
  gap: 16px;
}
</style>
