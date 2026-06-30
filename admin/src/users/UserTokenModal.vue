<template>
  <n-modal :show="show" @update:show="emit('update:show', $event)">
    <n-card style="width: 680px" :title="title">
      <n-form label-placement="top">
        <n-form-item :label="captions.tokenLabel">
          <n-input
              v-model:value="form.token"
              :disabled="isEdit"
              :placeholder="captions.tokenPlaceholder"
          />
        </n-form-item>

        <n-form-item :label="captions.userLabel">
          <n-input v-model:value="form.user" :placeholder="captions.userPlaceholder" />
        </n-form-item>

        <n-form-item :label="captions.scopeLabel">
          <n-dynamic-tags v-model:value="form.scope" />
        </n-form-item>

        <n-form-item :label="captions.statusLabel">
          <n-select v-model:value="form.status" :options="statusOptions" />
        </n-form-item>

        <n-form-item :label="captions.tagsLabel">
          <n-dynamic-tags v-model:value="form.tags" />
        </n-form-item>

        <n-space justify="end">
          <n-button @click="emit('update:show', false)">
            {{ captions.cancel }}
          </n-button>

          <n-button type="primary" @click="save">
            {{ captions.save }}
          </n-button>
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

const form = reactive(emptyForm())

const isEdit = computed(() => !!props.item?.token)
const title = computed(() => isEdit.value ? captions.editTitle : captions.createTitle)

const captions = getCaptions('userTokenModal')

const statusOptions = [
  { label: captions.statusActive, value: 'active' },
  { label: captions.statusHold, value: 'hold' }
]

watch(
    () => props.show,
    (value) => {
      if (!value) return

      Object.assign(form, props.item ? {
        ...emptyForm(),
        ...props.item
      } : emptyForm())
    }
)

function emptyForm() {
  return {
    token: '',
    user: '',
    scope: ['upload', 'activity', 'dictionary'],
    status: 'active',
    tags: [],
    active_clients: {
      web: '',
      plugin: ''
    }
  }
}

function save() {
  emit('save', {
    token: form.token,
    user: form.user,
    scope: form.scope,
    status: form.status,
    tags: form.tags,
    active_clients: {
      web: form.active_clients?.web || '',
      plugin: form.active_clients?.plugin || ''
    }
  })
}
</script>
