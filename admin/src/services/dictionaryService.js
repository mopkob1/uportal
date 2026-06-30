import { uportalApi } from '../api/uportalApi'
import { extractItems } from './normalizers'

export function normalizeDictionaryItem(raw) {
  return {
    id: raw.id || '',
    pre: raw.pre || '',
    post: raw.post || '',
    url: raw.url || '',
    anchor: raw.anchor || '',
    type: raw.type || 'redirect',
    tags: raw.tags || '',
    raw
  }
}

export const dictionaryService = {
  async list() {
    const payload = await uportalApi.dictionary.list()
    return extractItems(payload).map(normalizeDictionaryItem)
  },

  async upsert(item) {
    return uportalApi.dictionary.upsert(item)
  },

  async delete(id) {
    return uportalApi.dictionary.delete(id)
  }
}
