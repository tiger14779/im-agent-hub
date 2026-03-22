<template>
  <el-table :data="users" v-loading="loading" border stripe>
    <el-table-column prop="id" label="ID" width="200" show-overflow-tooltip />
    <el-table-column prop="nickname" label="昵称" min-width="120" />
    <el-table-column prop="serviceName" label="绑定客服" min-width="120">
      <template #default="{ row }">
        {{ row.serviceName || row.serviceId || '-' }}
      </template>
    </el-table-column>
    <el-table-column prop="createdAt" label="创建时间" width="180" />
    <el-table-column label="状态" width="90">
      <template #default="{ row }">
        <el-tag :type="row.status === 1 ? 'success' : 'danger'" size="small">
          {{ row.status === 1 ? '正常' : '禁用' }}
        </el-tag>
      </template>
    </el-table-column>
    <el-table-column label="操作" width="220" fixed="right">
      <template #default="{ row }">
        <el-button size="small" type="primary" plain @click="emit('edit', row)">编辑</el-button>
        <el-button size="small" type="danger" plain @click="emit('delete', row)">删除</el-button>
        <el-button size="small" type="success" plain @click="emit('generate-link', row)">登录链接</el-button>
      </template>
    </el-table-column>
  </el-table>
</template>

<script setup lang="ts">
interface User {
  id: string
  nickname: string
  serviceId: string
  serviceName: string
  status: number
  createdAt: string
}

defineProps<{
  users: User[]
  loading: boolean
}>()

const emit = defineEmits<{
  edit: [user: User]
  delete: [user: User]
  'generate-link': [user: User]
}>()
</script>
