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
  (response) => response.data,
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
