import { defineStore } from 'pinia'

const STORAGE_KEY = 'im_user_info'

export const useUserStore = defineStore('user', {
  state: () => ({
    userId: '',
    nickname: '',
    avatar: '',
    token: '',
    serviceUserId: '',
    serviceNickname: '',
    serviceAvatar: ''
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
          avatar: this.avatar,
          token: this.token,
          serviceUserId: this.serviceUserId,
          serviceNickname: this.serviceNickname,
          serviceAvatar: this.serviceAvatar
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
        this.avatar = data.avatar || ''
        this.token = data.token || ''
        this.serviceUserId = data.serviceUserId || ''
        this.serviceNickname = data.serviceNickname || ''
        this.serviceAvatar = data.serviceAvatar || ''
      } catch {
        // Ignore malformed storage data
      }
    },

    /** Set user credentials after a successful login */
    login(info: {
      userId: string
      token: string
      nickname?: string
      avatar?: string
      serviceUserId?: string
      serviceNickname?: string
      serviceAvatar?: string
    }) {
      this.userId = info.userId
      this.token = info.token
      this.nickname = info.nickname || ''
      this.avatar = info.avatar || ''
      this.serviceUserId = info.serviceUserId || ''
      this.serviceNickname = info.serviceNickname || ''
      this.serviceAvatar = info.serviceAvatar || ''
      this.saveToStorage()
    },

    logout() {
      this.userId = ''
      this.nickname = ''
      this.avatar = ''
      this.token = ''
      this.serviceUserId = ''
      this.serviceNickname = ''
      this.serviceAvatar = ''
      localStorage.removeItem(STORAGE_KEY)
    }
  }
})
