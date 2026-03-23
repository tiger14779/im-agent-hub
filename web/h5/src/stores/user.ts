import { defineStore } from 'pinia'

const STORAGE_KEY = 'im_user_info'

export const useUserStore = defineStore('user', {
  state: () => ({
    userId: '',
    nickname: '',
    token: '',
    serviceUserId: ''
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
          nickname: this.nickname,
          token: this.token,
          serviceUserId: this.serviceUserId
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
        this.nickname = data.nickname || ''
        this.token = data.token || ''
        this.serviceUserId = data.serviceUserId || ''
      } catch {
        // Ignore malformed storage data
      }
    },

    /** Set user credentials after a successful login */
    login(info: {
      userId: string
      token: string
      nickname?: string
      serviceUserId?: string
    }) {
      this.userId = info.userId
      this.token = info.token
      this.nickname = info.nickname || ''
      this.serviceUserId = info.serviceUserId || ''
      this.saveToStorage()
    },

    logout() {
      this.userId = ''
      this.nickname = ''
      this.token = ''
      this.serviceUserId = ''
      localStorage.removeItem(STORAGE_KEY)
    }
  }
})
