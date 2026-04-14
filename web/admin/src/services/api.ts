import request from '@/utils/request'

export interface CreateUserRequest {
  nickname: string
  groupNickname: string
  serviceUserId: string
  avatar?: string
}

export interface UpdateUserRequest {
  nickname?: string
  groupNickname?: string
  serviceUserId?: string
  status?: number
  avatar?: string
}

export interface BatchCreateRequest {
  count: number
  serviceUserId: string
  prefix?: string
}

export interface CreateServiceRequest {
  userId: string
  nickname: string
  avatar?: string
}

export interface UpdateServiceRequest {
  nickname?: string
  avatar?: string
  status?: number
}

export interface SettingsRequest {
  cleanupEnabled: boolean
  retentionDays: number
  cronExpression: string
  newPassword?: string
  currentPassword?: string
}

// Auth
export const adminLogin = (username: string, password: string) =>
  request.post('/auth/login', { username, password })

// Stats
export const getStats = () => request.get('/stats')

// Users
export const getUsers = (page: number, pageSize: number, keyword?: string) =>
  request.get('/users', { params: { page, pageSize, keyword } })

export const createUser = (data: CreateUserRequest) =>
  request.post('/users', data)

export const updateUser = (id: string, data: UpdateUserRequest) =>
  request.put(`/users/${id}`, data)

export const deleteUser = (id: string) =>
  request.delete(`/users/${id}`)

export const batchCreateUsers = (data: BatchCreateRequest) =>
  request.post('/users/batch', data)

// Services
export const getServices = () =>
  request.get('/services')

export const createService = (data: CreateServiceRequest) =>
  request.post('/services', data)

export const updateService = (id: string, data: UpdateServiceRequest) =>
  request.put(`/services/${id}`, data)

export const deleteService = (id: string) =>
  request.delete(`/services/${id}`)

// Settings
export const getSettings = () =>
  request.get('/settings')

export const updateSettings = (data: SettingsRequest) =>
  request.put('/settings', data)

export const changePassword = (currentPassword: string, newPassword: string) =>
  request.put('/password', { currentPassword, newPassword })

// Upload file (uses /api/upload, not /api/admin/upload)
export const uploadFile = (file: File) => {
  const formData = new FormData()
  formData.append('file', file)
  return request.post('/upload', formData, {
    baseURL: '/api',
    headers: { 'Content-Type': 'multipart/form-data' }
  })
}

// Groups
export const getGroups = () =>
  request.get('/groups')

export const createGroup = (data: { name: string; ownerId: string; avatar?: string }) =>
  request.post('/groups', data)

export const updateGroup = (id: string, data: { name?: string; avatar?: string }) =>
  request.put(`/groups/${id}`, data)

export const deleteGroup = (id: string) =>
  request.delete(`/groups/${id}`)
