import { dictionaryService } from '../../services/dictionaryService'

export default {
  namespaced: true,

  state: () => ({
    items: [],
    loading: false,
    error: ''
  }),

  mutations: {
    setLoading(state, value) {
      state.loading = value
    },

    setError(state, error) {
      state.error = error
    },

    setItems(state, items) {
      state.items = items
    }
  },

  actions: {
    async load({ commit }) {
      commit('setLoading', true)
      commit('setError', '')

      try {
        const items = await dictionaryService.list()
        commit('setItems', items)
        return items
      } catch (error) {
        commit('setError', error.message || 'Dictionary load failed')
        throw error
      } finally {
        commit('setLoading', false)
      }
    },

    async upsert({ dispatch }, item) {
      const result = await dictionaryService.upsert(item)
      await dispatch('load')
      return result
    },

    async delete({ dispatch }, id) {
      const result = await dictionaryService.delete(id)
      await dispatch('load')
      return result
    }
  }
}
