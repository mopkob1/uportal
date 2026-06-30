import axios from 'axios'
import store, { normalizeServerUrl } from '../store'

const baseURL = normalizeServerUrl(import.meta.env.VITE_UPORTAL_BASE_URL)

export const httpClient = axios.create({
  baseURL,
  timeout: 30000
})

httpClient.interceptors.request.use((config) => {
  const token = store.state.auth?.userToken || store.state.token

  if (token) {
    config.headers['X-User-Token'] = token
    if (store.state.clientUid) {
      config.headers['X-UPortal-Client-Uid'] = store.state.clientUid
      config.headers['X-UPortal-Client-Type'] = 'web'
    }
  }

  return config
})

export function normalizeApiResponse(response) {
  return response?.data
}
