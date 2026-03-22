import { defineStore } from 'pinia'
import { ref, computed } from 'vue'

export const useAuthStore = defineStore('auth', () => {
  const token = ref<string>(localStorage.getItem('admin_token') || '')
  const username = ref<string>(localStorage.getItem('admin_username') || '')

  const isLoggedIn = computed(() => !!token.value)

  function setAuth(newToken: string, newUsername: string) {
    token.value = newToken
    username.value = newUsername
    localStorage.setItem('admin_token', newToken)
    localStorage.setItem('admin_username', newUsername)
  }

  function logout() {
    token.value = ''
    username.value = ''
    localStorage.removeItem('admin_token')
    localStorage.removeItem('admin_username')
  }

  function checkAuth(): boolean {
    return !!localStorage.getItem('admin_token')
  }

  return { token, username, isLoggedIn, setAuth, logout, checkAuth }
})
