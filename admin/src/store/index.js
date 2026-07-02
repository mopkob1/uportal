import { createStore } from 'vuex'
import {
  linksList,
  publishDraftRequest,
  setClicks,
  setFreshness,
  setLinkDelay,
  setLinkPassword,
  setLinkStatus,
  setLinkSticky,
  activityList,
  dictionaryList,
  dictionaryUpsert,
  dictionaryDelete,
  tokensList,
  tokenSelfGet,
  tokenSelfUpsert,
  tokenUpsert,
  tokenDelete
} from '../api/uportalApi'
import {
  DEFAULT_SERVER_URL,
  LEGACY_DEFAULT_SERVER_URLS,
  normalizeServerUrl
} from '../config/server'

const TOKEN_KEY = 'uportal_token'
const ADMIN_TOKEN_KEY = 'uportal_admin_token'
const SERVER_URL_KEY = 'uportal_server_url'
const AUTH_HEADER_KEY = 'uportal_auth_header'
const CLIENT_UID_KEY = 'uportal_client_uid'
const LEGACY_DRAFTS_KEY = 'uportal_publication_drafts'
const DRAFTS_KEY_PREFIX = 'uportal_publication_drafts:'
const LINKS_PAGE_LIMIT = 500
export { DEFAULT_SERVER_URL, LEGACY_DEFAULT_SERVER_URLS, normalizeServerUrl }

clearPersistedSecret(TOKEN_KEY)
clearPersistedSecret(ADMIN_TOKEN_KEY)

export default createStore({
  state: {
    adminHeader: localStorage.getItem('uportal_admin_header') || 'X-Admin-Key',
    adminToken: '',
    excludedUids: JSON.parse(localStorage.getItem('uportal_excluded_uids') || '[]'),
    tokens: [],
    tokensPager: {
      page: 1,
      limit: 10,
      total: 0,
      has_next: false
    },
    serverUrl: normalizeServerUrl(localStorage.getItem(SERVER_URL_KEY)),
    authHeader: localStorage.getItem(AUTH_HEADER_KEY) || 'X-User-Token',
    token: '',
    clientUid: getOrCreateClientUid(),
    authorized: false,
    draftScopeKey: '',

    links: [],
    linksPager: {
      limit: LINKS_PAGE_LIMIT,
      offset: 0,
      total: 0,
      pages: 0,
      has_next: false
    },
    activity: [],
    activityPager: {
      page: 1,
      limit: 50,
      total: 0,
      has_next: false
    },

    dictionary: [],
    drafts: []
  },

  mutations: {
    setExcludedUids(state, value) {
      state.excludedUids = Array.isArray(value) ? value : []
      localStorage.setItem('uportal_excluded_uids', JSON.stringify(state.excludedUids))
    },
    setAuthConfig(state, payload) {
      state.serverUrl = normalizeServerUrl(payload.serverUrl)
      state.authHeader = payload.authHeader || 'X-User-Token'
      state.token = payload.token || ''
      state.authorized = !!state.token
      state.draftScopeKey = getDraftScopeKey(state.token)
      state.drafts = loadStoredDrafts(state.token)

      localStorage.setItem(SERVER_URL_KEY, state.serverUrl)
      localStorage.setItem(AUTH_HEADER_KEY, state.authHeader)
      clearPersistedSecret(TOKEN_KEY)
    },

    logout(state) {
      state.token = ''
      state.authorized = false
      state.draftScopeKey = ''
      state.drafts = []
      clearPersistedSecret(TOKEN_KEY)
    },
    setAdminToken(state, token) {
      state.adminToken = token
      clearPersistedSecret(ADMIN_TOKEN_KEY)
    },

    setToken(state, token) {
      state.token = token
      state.authorized = !!state.token
      state.draftScopeKey = getDraftScopeKey(state.token)
      state.drafts = loadStoredDrafts(state.token)
      clearPersistedSecret(TOKEN_KEY)
    },

    setLinks(state, links) {
      state.links = links
    },

    mergePublicationLinks(state, payload) {
      const publicationId = payload.publication_id || ''
      const links = Array.isArray(payload.links) ? payload.links : []

      if (!publicationId) return

      const existing = state.links.filter(item =>
          (item.publication_id || item.publication || '') !== publicationId
      )

      state.links = [
        ...links,
        ...existing
      ]
    },

    setLinksPager(state, payload) {
      state.linksPager = {
        limit: payload.limit || LINKS_PAGE_LIMIT,
        offset: payload.offset || 0,
        total: payload.total || 0,
        pages: payload.pages || 0,
        has_next: !!payload.has_next
      }
    },

    setActivity(state, payload) {
      state.activity = payload.items || []
      state.activityPager = {
        page: payload.page || 1,
        limit: payload.limit || 50,
        total: payload.total || 0,
        has_next: !!payload.has_next
      }
    },

    setDictionary(state, items) {
      state.dictionary = items
    },

    addDraft(state, draft) {
      const publicationId = draft.publication_id || ''
      const updatedDraft = {
        ...draft,
        draft_owner_key: state.draftScopeKey
      }

      state.drafts = state.drafts
          .map(item => {
            if (!publicationId || item.publication_id !== publicationId) return item
            if ((item.type || '') !== (updatedDraft.type || '')) return item

            return {
              ...item,
              subj: updatedDraft.subj || '',
              mails: Array.isArray(updatedDraft.mails) ? updatedDraft.mails : []
            }
          })
          .filter(item => item.draft_id !== updatedDraft.draft_id)

      state.drafts.unshift(updatedDraft)
      persistDrafts(state.drafts, state.token)
    },

    removeDraft(state, draftId) {
      state.drafts = state.drafts.filter(item => item.draft_id !== draftId)
      persistDrafts(state.drafts, state.token)
    },

    publishDraftLocally(state, payload) {
      state.drafts = state.drafts.filter(item => item.draft_id !== payload.draftId)
      persistDrafts(state.drafts, state.token)

      if (payload.link) {
        state.links = [
          payload.link,
          ...state.links.filter(item =>
              item.publication_id !== payload.link.publication_id ||
              item.token !== payload.link.token
          )
        ]
      }
    },

    updateLinkParams(state, payload) {
      state.links = state.links.map(item => {
        if (item.publication_id !== payload.publication_id || item.token !== payload.token) return item
        return {
          ...item,
          ...payload.values
        }
      })
    },
    setAdminAuth(state, payload) {
      state.adminHeader = payload.header || 'X-Admin-Key'
      state.adminToken = payload.token || ''

      localStorage.setItem('uportal_admin_header', state.adminHeader)
      clearPersistedSecret(ADMIN_TOKEN_KEY)
    },

    setTokens(state, payload) {
      state.tokens = payload.items || []
      state.tokensPager = {
        page: payload.page || 1,
        limit: payload.limit || 10,
        total: payload.total || 0,
        has_next: !!payload.has_next
      }
    }
  },

  actions: {
    async loadLinks({ commit }, filters = {}) {
      const result = await loadPagedLinks(filters)
      const items = result.items

      commit('setLinks', items)
      commit('setLinksPager', result.pager)

      return items
    },

    async loadPublicationLinks({ commit }, publicationId) {
      if (!publicationId) return []

      const result = await loadAllLinks({ publication_id: publicationId })
      commit('mergePublicationLinks', {
        publication_id: publicationId,
        links: result.items
      })

      return result.items
    },

    async publishDraft(context, draft) {
      return await publishDraftRequest(draft)
    },

    async setLinkFreshness({ commit }, payload) {
      const data = await setFreshness(payload.publication_id, payload.token, payload.fresh_until)
      commit('updateLinkParams', {
        publication_id: payload.publication_id,
        token: payload.token,
        values: { fresh_until: payload.fresh_until || -1 }
      })
      return data
    },

    async setLinkClicks({ commit }, payload) {
      const value = normalizeClicksLimit(payload.remaining_clicks)
      const data = await setClicks(payload.publication_id, payload.token, value)
      commit('updateLinkParams', {
        publication_id: payload.publication_id,
        token: payload.token,
        values: { remaining_clicks: value }
      })
      return data
    },

    async setPublicationStatus({ commit }, payload) {
      const status = payload.status === 'hold' ? 'hold' : 'active'
      const data = await setLinkStatus(payload.publication_id, payload.token, status)
      commit('updateLinkParams', {
        publication_id: payload.publication_id,
        token: payload.token,
        values: { status }
      })
      return data
    },

    async setPublicationSticky({ commit }, payload) {
      const sticky = !!payload.sticky
      const data = await setLinkSticky(payload.publication_id, payload.token, sticky)
      commit('updateLinkParams', {
        publication_id: payload.publication_id,
        token: payload.token,
        values: { sticky }
      })
      return data
    },

    async setPublicationDelay({ commit }, payload) {
      const delay = normalizeDelay(payload.delay)
      const data = await setLinkDelay(payload.publication_id, payload.token, delay)
      commit('updateLinkParams', {
        publication_id: payload.publication_id,
        token: payload.token,
        values: { delay: String(delay) }
      })
      return data
    },

    async setPublicationPassword({ commit }, payload) {
      const data = await setLinkPassword(
          payload.publication_id,
          payload.token,
          payload.password,
          payload.password_hint,
          payload.password_ttl_sec
      )
      const meta = data?.message?.[0]?.meta || {}
      commit('updateLinkParams', {
        publication_id: payload.publication_id,
        token: payload.token,
        values: {
          password_hash: meta.password_hash || '',
          password_hint: meta.password_hint || ''
        }
      })
      return data
    },

    async loadActivity({ commit }, filters = {}) {
      const data = await activityList(filters)
      const paged = extractPaged(data, filters)
      commit('setActivity', paged)
      return paged
    },

    async loadDictionary({ commit }) {
      const data = await dictionaryList()
      const items = extractList(data)
      commit('setDictionary', items)
      return items
    },

    async saveDictionaryItem({ dispatch }, item) {
      const data = await dictionaryUpsert(item)
      await dispatch('loadDictionary')
      return data
    },

    async deleteDictionaryItem({ dispatch }, id) {
      const data = await dictionaryDelete(id)
      await dispatch('loadDictionary')
      return data
    },

    async createUserToken({ state }, payload) {
      return await tokenCreate(payload, state.adminToken)
    },

    async revokeUserToken({ state }, token) {
      return await tokenRevoke(token, state.adminToken)
    },
    async loadTokens({ state, commit }, params = {}) {
      const data = state.adminToken
          ? await tokensList(
              params,
              state.adminHeader,
              state.adminToken
          )
          : await tokenSelfGet()

      const paged = extractPaged(data, params)
      commit('setTokens', paged)
      return paged
    },

    async saveTokenItem({ state }, item) {
      const data = state.adminToken
          ? await tokenUpsert(
              item,
              state.adminHeader,
              state.adminToken
          )
          : await tokenSelfUpsert(item)

      return data
    },

    async deleteTokenItem({ state }, token) {
      const data = await tokenDelete(
          token,
          state.adminHeader,
          state.adminToken
      )

      return data
    }
  }
})

function extractList(payload) {
  if (Array.isArray(payload)) return payload

  if (Array.isArray(payload?.items)) return payload.items
  if (Array.isArray(payload?.links)) return payload.links
  if (Array.isArray(payload?.events)) return payload.events
  if (Array.isArray(payload?.data)) return payload.data

  if (Array.isArray(payload?.message)) {
    if (Array.isArray(payload.message[0]?.items)) return payload.message[0].items
    if (Array.isArray(payload.message[0]?.links)) return payload.message[0].links
    if (Array.isArray(payload.message[0]?.data)) return payload.message[0].data
    return payload.message.filter(item => item && typeof item === 'object')
  }

  return []
}

async function loadPagedLinks(filters = {}) {
  const limit = normalizePageLimit(filters.limit || LINKS_PAGE_LIMIT)
  const offset = normalizeOffset(filters.offset)
  const data = await linksList({
    ...filters,
    limit,
    offset
  })
  const meta = extractListMeta(data)
  const items = extractLinksPayload(data)
  const total = Number.isFinite(meta.total) ? meta.total : items.length

  return {
    items,
    pager: {
      limit,
      offset,
      total,
      pages: 1,
      has_next: offset + limit < total
    }
  }
}

async function loadAllLinks(filters = {}) {
  const limit = normalizePageLimit(filters.limit || LINKS_PAGE_LIMIT)
  const baseFilters = {
    ...filters,
    limit
  }
  const items = []
  let offset = normalizeOffset(filters.offset)
  let total = null
  let pages = 0

  while (true) {
    const data = await linksList({
      ...baseFilters,
      offset
    })
    const pageItems = extractLinksPayload(data)
    const meta = extractListMeta(data)

    items.push(...pageItems)
    pages += 1

    if (Number.isFinite(meta.total)) {
      total = meta.total
    }

    const nextOffset = offset + limit
    const hasKnownNext = Number.isFinite(total) && nextOffset < total
    const hasInferredNext = !Number.isFinite(total) && pageItems.length >= limit

    if (!pageItems.length || (!hasKnownNext && !hasInferredNext)) {
      offset = nextOffset
      break
    }

    offset = nextOffset
  }

  return {
    items,
    pager: {
      limit,
      offset: 0,
      total: Number.isFinite(total) ? total : items.length,
      pages,
      has_next: false
    }
  }
}

function extractLinksPayload(payload) {
  const campaigns = extractCampaigns(payload)

  return campaigns.length
      ? campaigns.flatMap(campaign => Array.isArray(campaign.links) ? campaign.links : [])
      : extractList(payload)
}

function extractListMeta(payload) {
  const meta = payload?.meta || payload?.message?.[0]?.meta || {}
  const total = Number(meta.count ?? meta.total ?? meta.itemCount)
  const limit = Number(meta.limit)
  const offset = Number(meta.offset)

  return {
    total: Number.isFinite(total) ? total : null,
    limit: Number.isFinite(limit) ? limit : null,
    offset: Number.isFinite(offset) ? offset : null
  }
}

function extractCampaigns(payload) {
  if (Array.isArray(payload?.campaigns)) return payload.campaigns

  if (Array.isArray(payload?.message)) {
    if (Array.isArray(payload.message[0]?.campaigns)) return payload.message[0].campaigns
    if (payload?.meta?.mode === 'campaigns') return payload.message.filter(item => item && Array.isArray(item.links))
    if (payload?.message?.[0]?.meta?.mode === 'campaigns') return payload.message.filter(item => item && Array.isArray(item.links))
  }

  return []
}

function normalizePageLimit(value) {
  const number = Number(value)
  if (!Number.isFinite(number) || number < 1) return LINKS_PAGE_LIMIT
  return Math.min(Math.trunc(number), 1000)
}

function normalizeOffset(value) {
  const number = Number(value)
  if (!Number.isFinite(number) || number < 0) return 0
  return Math.trunc(number)
}

function extractPaged(payload, filters = {}) {
  if (Array.isArray(payload?.message) && payload.message[0]?.items) {
    return payload.message[0]
  }

  if (Array.isArray(payload?.items)) {
    return payload
  }

  return {
    items: [],
    page: filters.page || 1,
    limit: filters.limit || 50,
    total: 0,
    has_next: false
  }
}

function normalizeClicksLimit(value) {
  const number = Number(value)
  if (!Number.isFinite(number) || number < 0) return -1
  return Math.trunc(number)
}

function normalizeDelay(value) {
  const numeric = Number(value)
  if (!Number.isFinite(numeric) || numeric < 0) return 0
  return Math.floor(numeric)
}

function loadStoredDrafts(token) {
  const key = getDraftsStorageKey(token)
  if (!key) return []

  try {
    const scopeKey = getDraftScopeKey(token)
    const value = localStorage.getItem(key)
    const drafts = JSON.parse(value || '[]')
    if (Array.isArray(drafts) && drafts.length) {
      return normalizeDraftOwners(drafts, scopeKey)
    }

    const legacyDrafts = loadLegacyDrafts()
    if (legacyDrafts.length) {
      const scopedDrafts = normalizeDraftOwners(legacyDrafts, scopeKey, { adoptLegacy: true })
      localStorage.setItem(key, JSON.stringify(scopedDrafts.map(serializeDraft)))
      localStorage.removeItem(LEGACY_DRAFTS_KEY)
      return scopedDrafts
    }

    return []
  } catch {
    return []
  }
}

function persistDrafts(drafts, token) {
  const key = getDraftsStorageKey(token)
  if (!key) return

  const serializableDrafts = drafts.map(serializeDraft)
  localStorage.setItem(key, JSON.stringify(serializableDrafts))
}

function getDraftsStorageKey(token) {
  const scopeKey = getDraftScopeKey(token)
  if (!scopeKey) return ''
  return `${DRAFTS_KEY_PREFIX}${scopeKey}`
}

function getDraftScopeKey(token) {
  if (!token) return ''
  return hashToken(token)
}

function loadLegacyDrafts() {
  try {
    const value = localStorage.getItem(LEGACY_DRAFTS_KEY)
    const drafts = JSON.parse(value || '[]')
    return Array.isArray(drafts) ? drafts : []
  } catch {
    return []
  }
}

function hashToken(token) {
  let hash = 2166136261
  const value = String(token || '')

  for (let index = 0; index < value.length; index += 1) {
    hash ^= value.charCodeAt(index)
    hash = Math.imul(hash, 16777619)
  }

  return (hash >>> 0).toString(16).padStart(8, '0')
}

function getOrCreateClientUid() {
  const existing = localStorage.getItem(CLIENT_UID_KEY)
  if (existing) return existing

  const random = globalThis.crypto?.randomUUID
      ? globalThis.crypto.randomUUID()
      : `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 12)}`
  const uid = `web-${random}`.replace(/[^A-Za-z0-9._:-]/g, '-').slice(0, 128)
  localStorage.setItem(CLIENT_UID_KEY, uid)
  return uid
}

function clearPersistedSecret(key) {
  try {
    localStorage.removeItem(key)
  } catch {
    // localStorage may be unavailable in hardened browser contexts.
  }
}

function normalizeDraftOwners(drafts, scopeKey, options = {}) {
  return drafts
      .map(draft => ({
        ...draft,
        draft_owner_key: draft?.draft_owner_key || (options.adoptLegacy ? scopeKey : '')
      }))
      .filter(draft => !draft.draft_owner_key || draft.draft_owner_key === scopeKey)
      .map(draft => ({
        ...draft,
        draft_owner_key: scopeKey
      }))
}

function serializeDraft(draft) {
  const value = JSON.parse(JSON.stringify(draft || {}))

  value.file = null
  value.imageFile = null
  value.fileDataUrl = ''
  value.imageDataUrl = ''

  if (Array.isArray(value.form?.files)) {
    value.form.files = value.form.files.map(file => ({
      name: file?.name || '',
      file: null,
      fileDataKey: file?.fileDataKey || ''
    }))
  }

  return value
}
