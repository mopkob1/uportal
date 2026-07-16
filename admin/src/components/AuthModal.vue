<template>
  <n-modal :show="show" @update:show="emit('update:show', $event)">
    <n-card style="width: 560px" :title="caps.title">
      <n-form label-placement="top">
        <n-form-item :label="caps.serverUrl">
          <n-input
              v-model:value="form.serverUrl"
              placeholder="http://localhost:8080"
          />
        </n-form-item>

        <n-form-item :label="caps.headerName">
          <n-input
              v-model:value="form.authHeader"
              placeholder="X-User-Token"
          />
        </n-form-item>

        <n-form-item :label="caps.token">
          <n-input
              v-model:value="form.token"
              type="password"
              show-password-on="click"
              placeholder="token"
          />
        </n-form-item>

        <n-form-item :label="caps.clientUid">
          <n-input-group>
            <n-input :value="clientUid" disabled />
            <n-button :title="caps.copyClientUid" @click="copyClientUid">
              <template #icon>
                <n-icon>
                  <CopyOutline />
                </n-icon>
              </template>
            </n-button>
          </n-input-group>
        </n-form-item>

        <n-form-item :label="caps.excludedUids">
          <n-input
              v-model:value="form.excludedUids"
              type="textarea"
              :autosize="{ minRows: 3, maxRows: 8 }"
              placeholder="uid1&#10;uid2"
          />
        </n-form-item>
        <n-space justify="space-between">
          <n-button type="error" ghost @click="logout">
            {{ caps.logout }}
          </n-button>

          <n-space>
            <n-button @click="emit('update:show', false)">
              {{ caps.cancel }}
            </n-button>

            <n-button type="primary" :loading="saving" @click="save">
              {{ caps.save }}
            </n-button>
          </n-space>
        </n-space>
      </n-form>
    </n-card>
  </n-modal>
</template>

<script setup>
import { computed, reactive, ref, watch } from 'vue'
import { useStore } from 'vuex'
import { NInputGroup, useMessage } from 'naive-ui'
import { CopyOutline } from '@vicons/ionicons5'
import { getCaptions } from '../captions'
import { normalizeServerUrl } from '../store'

const props = defineProps({
  show: Boolean
})

const emit = defineEmits(['update:show', 'saved'])

const store = useStore()
const message = useMessage()
const caps = getCaptions('auth')
const clientUid = computed(() => store.state.clientUid || '')
const saving = ref(false)

const form = reactive({
  serverUrl: '',
  authHeader: '',
  token: '',
  excludedUids: ''
})

watch(
    () => props.show,
    (value) => {
      if (!value) return

      form.serverUrl = normalizeServerUrl(store.state.serverUrl)
      form.authHeader = store.state.authHeader || 'X-User-Token'
      form.token = store.state.token || ''
      form.excludedUids = (store.state.excludedUids || []).join('\n')
    }
)

async function save() {
  const previousAuth = {
    serverUrl: normalizeServerUrl(store.state.serverUrl),
    authHeader: store.state.authHeader || 'X-User-Token',
    token: store.state.token || '',
    authMode: store.state.authMode || 'token',
    siteSessionKey: getSiteSessionKey(store.state.siteSession)
  }

  saving.value = true

  try {
    if (store.state.siteBackendAvailable) {
      await store.dispatch('loginWithSiteBackend', {
        serverUrl: form.serverUrl,
        token: form.token
      })
    } else {
      store.commit('setAuthConfig', {
        serverUrl: form.serverUrl,
        authHeader: form.authHeader,
        token: form.token
      })
    }

    store.commit(
        'setExcludedUids',
        form.excludedUids
            .split(/\s|,|;/)
            .map(item => item.trim())
            .filter(Boolean)
    )
    message.success(caps.saved)
    emit('saved', {
      changed: true,
      authChanged: previousAuth.serverUrl !== store.state.serverUrl ||
          previousAuth.authHeader !== store.state.authHeader ||
          previousAuth.token !== store.state.token ||
          previousAuth.authMode !== store.state.authMode ||
          previousAuth.siteSessionKey !== getSiteSessionKey(store.state.siteSession)
    })
    emit('update:show', false)
  } catch (error) {
    message.error(error?.message || 'Authorization failed')
  } finally {
    saving.value = false
  }
}

async function copyClientUid() {
  await navigator.clipboard.writeText(clientUid.value)
  message.success(caps.uidCopied)
}

async function logout() {
  saving.value = true
  try {
    await store.dispatch('logoutAuth')
    message.success(caps.reset)
    emit('update:show', false)
  } finally {
    saving.value = false
  }
}

function getSiteSessionKey(session) {
  if (!session?.authenticated) return ''
  return [
    session.account?.id || '',
    session.account?.email || '',
    session.visitorId || ''
  ].filter(Boolean).join(':')
}
</script>
