import axios from 'axios'
import { ElMessage } from 'element-plus'

const request = axios.create({
  baseURL: '/api/admin',
  timeout: 10000,
  headers: {
    'Content-Type': 'application/json',
    'Cache-Control': 'no-cache',
    'Pragma': 'no-cache'
  }
})

request.interceptors.request.use(
  (config) => {
    const token = localStorage.getItem('admin_token')
    if (token) {
      config.headers.Authorization = `Bearer ${token}`
    }
    return config
  },
  (error) => Promise.reject(error)
)

request.interceptors.response.use(
  (response) => {
    const payload = response?.data

    if (payload && payload.code !== undefined && payload.code !== null) {
      const code = Number(payload.code)

      if (code !== 0) {
        const message = payload.msg || '请求失败'

        if (code === 401) {
          localStorage.removeItem('admin_token')
          localStorage.removeItem('admin_username')
          ElMessage.error('登录已过期，请重新登录')
          window.location.href = '/admin/login'
        } else {
          ElMessage.error(message)
        }

        return Promise.reject(new Error(message))
      }

      return {
        ...response,
        data: payload.data
      }
    }

    return response
  },
  (error) => {
    if (error.response?.status === 401) {
      localStorage.removeItem('admin_token')
      localStorage.removeItem('admin_username')
      ElMessage.error('登录已过期，请重新登录')
      window.location.href = '/admin/login'
    } else {
      const message = error.response?.data?.msg || error.response?.data?.message || error.message || '请求失败'
      ElMessage.error(message)
    }
    return Promise.reject(error)
  }
)

export default request
