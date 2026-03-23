import axios from 'axios'
import { useUserStore } from '@/stores/user'

const request = axios.create({
  baseURL: '/api',
  timeout: 10000
})

// Attach auth token to every request
request.interceptors.request.use((config) => {
  const userStore = useUserStore()
  if (userStore.token) {
    config.headers.Authorization = `Bearer ${userStore.token}`
  }
  return config
})

// Unified error handling
request.interceptors.response.use(
  (response) => {
    const payload = response?.data

    if (payload && payload.code !== undefined && payload.code !== null) {
      const code = Number(payload.code)
      if (code !== 0) {
        const message = payload.msg || '请求失败'
        return Promise.reject(new Error(message))
      }
      return payload.data
    }

    return payload
  },
  (error) => {
    const msg =
      error.response?.data?.message ||
      error.response?.data?.msg ||
      error.message ||
      '网络请求失败'
    console.error('[request]', msg, error)
    return Promise.reject(new Error(msg))
  }
)

export default request
