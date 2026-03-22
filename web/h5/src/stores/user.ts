import { defineStore } from 'pinia'

const STORAGE_KEY = 'im_user_info'

export const useUserStore = defineStore('user', {
  state: () => ({
    userId: '',
    token: '',
    serviceUserId: '',
    wsUrl: '',
    apiUrl: ''
  }),

  getters: {
    isLoggedIn: (state) => !!state.token && !!state.userId
  },

  actions: {
    /** Persist current state to localStorage */
    saveToStorage() {
      localStorage.setItem(
        STORAGE_KEY,
        JSON.stringify({
          userId: this.userId,
          token: this.token,
          serviceUserId: this.serviceUserId,
          wsUrl: this.wsUrl,
          apiUrl: this.apiUrl
        })
      )
    },

    /** Restore state from localStorage */
    loadFromStorage() {
      const raw = localStorage.getItem(STORAGE_KEY)
      if (!raw) return
      try {
        const data = JSON.parse(raw)
        this.userId = data.userId || ''
        this.token = data.token || ''
        this.serviceUserId = data.serviceUserId || ''
        this.wsUrl = data.wsUrl || ''
        this.apiUrl = data.apiUrl || ''
      } catch {
        // Ignore malformed storage data
      }
    },

    /** Set user credentials after a successful login */
    login(info: {
      userId: string
      token: string
      serviceUserId?: string
      wsUrl?: string
      apiUrl?: string
    }) {
      this.userId = info.userId
      this.token = info.token
      this.serviceUserId = info.serviceUserId || ''
      this.wsUrl = info.wsUrl || ''
      this.apiUrl = info.apiUrl || ''
      this.saveToStorage()
    },

    logout() {
      this.userId = ''
      this.token = ''
      this.serviceUserId = ''
      this.wsUrl = ''
      this.apiUrl = ''
      localStorage.removeItem(STORAGE_KEY)
    }
  }
})
