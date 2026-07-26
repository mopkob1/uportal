<template>
  <n-modal :show="show" :mask-closable="!saving" @update:show="emit('update:show', $event)">
    <n-card style="width: 680px" :title="title">
      <n-form label-placement="top">
        <n-form-item :label="captions.tokenLabel">
          <n-input
              v-model:value="form.token"
              :disabled="isEdit || saving"
              :placeholder="captions.tokenPlaceholder"
          />
        </n-form-item>

        <n-form-item :label="captions.userLabel">
          <n-input v-model:value="form.user" :disabled="saving" :placeholder="captions.userPlaceholder" />
        </n-form-item>

        <n-form-item :label="captions.statusLabel">
          <n-select v-model:value="form.status" :disabled="saving" :options="statusOptions" />
        </n-form-item>

        <n-form-item :label="captions.tagsLabel">
          <n-dynamic-tags v-model:value="form.tags" :disabled="saving" />
        </n-form-item>

        <n-form-item :label="captions.idleTimeoutLabel">
          <n-input-number
              v-model:value="form.profile.idle_timeout_minutes"
              :min="1"
              :step="1"
              :disabled="saving"
              style="width: 180px"
          />
        </n-form-item>

        <n-space justify="end">
          <n-button :disabled="saving" @click="emit('update:show', false)">
            {{ captions.cancel }}
          </n-button>

          <n-button type="primary" :loading="saving" :disabled="saving" @click="save">
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
  },
  saving: {
    type: Boolean,
    default: false
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

      Object.assign(form, props.item ? normalizeForm({
        ...emptyForm(),
        ...props.item
      }) : emptyForm())
    }
)

function emptyForm() {
  return {
    token: '',
    user: '',
    scope: ['upload', 'activity', 'dictionary'],
    status: 'active',
    tags: [],
    profile: {
      idle_timeout_minutes: 15
    },
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
    profile: {
      ...(form.profile || {}),
      idle_timeout_minutes: normalizeIdleTimeoutMinutes(form.profile?.idle_timeout_minutes)
    },
    active_clients: {
      web: form.active_clients?.web || '',
      plugin: form.active_clients?.plugin || ''
    }
  })
}

function normalizeForm(value) {
  return {
    ...value,
    profile: {
      ...(value.profile || {}),
      idle_timeout_minutes: normalizeIdleTimeoutMinutes(value.profile?.idle_timeout_minutes)
    }
  }
}

function normalizeIdleTimeoutMinutes(value) {
  const number = Number(value)
  if (!Number.isFinite(number) || number <= 0) return 15
  return Math.max(1, Math.floor(number))
}
</script>
