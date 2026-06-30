<template>
  <n-collapse style="margin-top: 18px">
    <n-collapse-item :title="texts.modal.advanced" name="advanced">
      <template v-if="draft.type !== 'pixel'">
        <div class="advanced-rules-row">
          <n-form-item :label="texts.fields.freshUntil">
            <n-tooltip trigger="hover">
              <template #trigger>
                <n-date-picker
                    :value="freshUntilTs"
                    type="datetime"
                    clearable
                    style="width: 100%"
                    format="yyyy-MM-dd HH:mm"
                    :time-picker-props="{ format: 'HH:mm' }"
                    @update:value="updateFreshUntil"
                />
              </template>
              {{ texts.tooltips.freshUntil }}
            </n-tooltip>
          </n-form-item>

          <n-form-item :label="texts.fields.clicks">
            <n-tooltip trigger="hover">
              <template #trigger>
                <n-input
                    :value="String(draft.remaining_clicks ?? '')"
                    maxlength="5"
                    @update:value="updateRemainingClicks"
                />
              </template>
              {{ texts.tooltips.remainingClicks }}
            </n-tooltip>
          </n-form-item>

          <n-form-item :label="texts.fields.sticky">
            <n-tooltip trigger="hover">
              <template #trigger>
                <n-switch
                    :value="!!draft.sticky"
                    @update:value="draft.sticky = $event"
                />
              </template>
              {{ texts.tooltips.sticky }}
            </n-tooltip>
          </n-form-item>

          <n-form-item :label="texts.fields.password">
            <n-tooltip trigger="hover">
              <template #trigger>
                <n-input-group>
                  <n-input
                      :value="draft.form.password"
                      type="password"
                      show-password-on="click"
                      autocomplete="new-password"
                      :input-props="{ autocomplete: 'new-password' }"
                      @update:value="draft.form.password = $event"
                  >
                    <template #prefix>
                      <n-button
                          quaternary
                          size="tiny"
                          type="button"
                          :title="texts.actions.copy"
                          @click.stop="copyPassword"
                      >
                        <template #icon>
                          <Copy :size="15" :stroke-width="1.8" />
                        </template>
                      </n-button>
                    </template>
                  </n-input>

                  <n-button secondary @click="generatePassword">
                    <template #icon>
                      <RefreshCw :size="16" />
                    </template>
                  </n-button>
                </n-input-group>
              </template>
              {{ texts.tooltips.password }}
            </n-tooltip>
          </n-form-item>
        </div>
      </template>

      <n-form-item :label="texts.fields.subject">
        <n-input
            :value="draft.subj"
            :disabled="publicationLocked"
            @update:value="draft.subj = $event"
        />
      </n-form-item>

      <n-form-item :label="texts.fields.recipients">
        <n-input
            :value="recipientsText"
            type="textarea"
            :disabled="publicationLocked"
            :autosize="{ minRows: 2 }"
            @update:value="emit('update:recipientsText', $event)"
        />
      </n-form-item>
    </n-collapse-item>
  </n-collapse>
</template>

<script setup>
import { computed, ref, watch } from 'vue'
import { useMessage } from 'naive-ui'
import { Copy, RefreshCw } from 'lucide-vue-next'

const props = defineProps({
  draft: {
    type: Object,
    required: true
  },
  recipientsText: {
    type: String,
    default: ''
  },
  texts: {
    type: Object,
    required: true
  },
  publicationLocked: {
    type: Boolean,
    default: false
  }
})

const emit = defineEmits(['update:recipientsText'])

const draft = props.draft
const texts = props.texts
const publicationLocked = computed(() => props.publicationLocked)
const message = useMessage()
const freshUntilTs = ref(null)

watch(
    () => draft.fresh_until,
    (value) => {
      freshUntilTs.value = value && value !== -1
          ? new Date(value).getTime()
          : null
    },
    { immediate: true }
)

function updateFreshUntil(value) {
  freshUntilTs.value = value
  draft.fresh_until = value ? new Date(value).toISOString() : -1
}

function updateRemainingClicks(value) {
  const filtered = String(value || '').replace(/[^\d-]/g, '').slice(0, 5)
  draft.remaining_clicks = filtered
}

function generatePassword() {
  draft.form.password =
      Math.random().toString(36).slice(2, 8) +
      Math.random().toString(36).slice(2, 8)
}

async function copyPassword() {
  if (!draft.form.password) return
  await navigator.clipboard.writeText(draft.form.password)
  message.success(texts.messages.passwordCopied)
}

</script>
<style scoped>
.advanced-rules-row {
  display: grid;
  grid-template-columns: minmax(150px, 0.7fr) 72px 86px minmax(240px, 1.6fr);
  gap: 12px;
  align-items: start;
}
</style>
