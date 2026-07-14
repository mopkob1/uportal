<template>
    <n-config-provider
        :locale="naiveLocale"
        :date-locale="naiveDateLocale"
        :theme-overrides="themeOverrides"
    >
    <n-message-provider placement="bottom-right">
      <n-dialog-provider>
        <n-layout style="min-height: 100vh">

          <n-layout-header bordered class="app-header">
            <strong>UPORTAL</strong>

            <div class="app-header-spacer"></div>

            <nav class="app-tabs" :aria-label="caps.mainNavigation">
              <button
                  v-for="item in navigationItems"
                  :key="item.page"
                  type="button"
                  class="app-tab"
                  :class="{ 'is-active': page === item.page }"
                  :disabled="!authorized"
                  @click="navigateTo(item)"
              >
                {{ item.label }}
              </button>
            </nav>

            <n-button
                circle
                quaternary
                @click="authVisible = true"
                style="background: transparent;"
            >
              <component
                  :is="authorized ? LockOpen : Lock"
                  :size="18"
                  :stroke-width="1.8"
                  :color="authorized ? '#18a058' : '#f0a020'"
                  style="opacity: 0.9;"
              />
            </n-button>
          </n-layout-header>

          <n-layout-content style="padding: 20px">
            <n-empty
                v-if="!authorized"
                :description="caps.authRequired"
                style="margin-top: 80px"
            />

            <template v-else>
              <PublicationsPage v-if="page === 'publications'" :key="pageKeys.publications" />
              <StatisticsPage v-if="page === 'activity'" :key="pageKeys.activity" />
              <DictionaryPage v-if="page === 'dictionary'" :key="pageKeys.dictionary" />
              <UsersPage v-if="page === 'users'" :key="pageKeys.users" />
            </template>
          </n-layout-content>

        </n-layout>

        <AuthModal v-model:show="authVisible" @saved="refreshCurrentPage" />
      </n-dialog-provider>
    </n-message-provider>
  </n-config-provider>
</template>

<script setup>
import { Lock, LockOpen } from 'lucide-vue-next'
import { dateRuRU, ruRU } from 'naive-ui'
import {computed, onBeforeUnmount, onMounted, ref} from 'vue'
import {useStore} from 'vuex'

import AuthModal from './components/AuthModal.vue'
import PublicationsPage from './pages/PublicationsPage.vue'
import StatisticsPage from './pages/StatisticsPage.vue'
import DictionaryPage from './pages/DictionaryPage.vue'
import UsersPage from './pages/UsersPage.vue'
import { getCaptionLanguage, getCaptions } from './captions'
const store = useStore()
const caps = getCaptions('app')
const captionLanguage = getCaptionLanguage()
const naiveLocale = computed(() => captionLanguage === 'ru' ? ruRU : null)
const naiveDateLocale = computed(() => captionLanguage === 'ru' ? dateRuRU : null)
const uiFontFamily = 'Arial, Helvetica, sans-serif'
const themeOverrides = {
  common: {
    fontFamily: uiFontFamily,
    fontFamilyMono: 'Consolas, "Courier New", monospace'
  }
}

const navigationItems = [
  { page: 'publications', label: caps.tabs.publications, path: '/ui/pubs' },
  { page: 'activity', label: caps.tabs.activity, path: '/ui/stats' },
  { page: 'dictionary', label: caps.tabs.dictionary, path: '/ui/dict' },
  { page: 'users', label: caps.tabs.users, path: '/ui/users' }
]
const pathToPage = new Map(navigationItems.map(item => [item.path, item.page]))
const pageToPath = new Map(navigationItems.map(item => [item.page, item.path]))
const page = ref(resolvePageFromLocation())
const authVisible = ref(false)
const pageKeys = ref({
  publications: 0,
  activity: 0,
  dictionary: 0,
  users: 0
})

const token = computed(() => store.state.token)
const authorized = computed(() => store.state.authorized)

onMounted(async () => {
  await store.dispatch('bootstrapAuth')
  window.addEventListener('popstate', handlePopState)
  normalizeInitialRoute()
})

onBeforeUnmount(() => {
  window.removeEventListener('popstate', handlePopState)
})

function resolvePageFromLocation() {
  const path = window.location.pathname.replace(/\/+$/, '') || '/'
  return pathToPage.get(path) || 'publications'
}

function normalizeInitialRoute() {
  const path = window.location.pathname.replace(/\/+$/, '') || '/'
  if (pathToPage.has(path)) return

  const target = pageToPath.get(page.value) || '/ui/pubs'
  window.history.replaceState({}, '', `${target}${window.location.search}${window.location.hash}`)
}

function handlePopState() {
  page.value = resolvePageFromLocation()
}

function navigateTo(item) {
  if (!authorized.value || page.value === item.page) return

  page.value = item.page
  window.history.pushState({}, '', item.path)
}

function refreshCurrentPage(payload) {
  if (!payload?.changed || !authorized.value) return
  pageKeys.value = {
    ...pageKeys.value,
    [page.value]: pageKeys.value[page.value] + 1
  }
}
</script>

<style scoped>
:global(html),
:global(body),
:global(#app) {
  font-family: Arial, Helvetica, sans-serif;
}

.app-header {
  height: 64px;
  padding: 0 20px;
  display: flex;
  align-items: center;
  gap: 18px;
}

.app-header-spacer {
  flex: 1;
}

.app-tabs {
  display: inline-flex;
  align-items: center;
  gap: 48px;
}

.app-tab {
  appearance: none;
  border: 0;
  border-bottom: 2px solid transparent;
  background: transparent;
  padding: 8px 0 7px;
  color: rgba(31, 34, 37, 0.62);
  font: inherit;
  font-size: 15px;
  line-height: 1.2;
  cursor: pointer;
}

.app-tab:hover:not(:disabled) {
  color: rgba(31, 34, 37, 0.9);
}

.app-tab.is-active {
  color: #18a058;
  border-bottom-color: #18a058;
}

.app-tab:disabled {
  cursor: not-allowed;
  opacity: 0.45;
}
</style>
