<template>
  <div class="user-manage">
    <div class="page-header">
      <h2>用户管理</h2>
      <div class="header-actions">
        <el-input
          v-model="searchKeyword"
          placeholder="搜索用户昵称..."
          clearable
          style="width: 240px; margin-right: 12px"
          prefix-icon="Search"
          @clear="loadUsers"
          @keyup.enter="loadUsers"
        />
        <el-button type="primary" :icon="Plus" @click="openCreateDialog">创建用户</el-button>
        <el-button :icon="Operation" @click="batchVisible = true">批量创建</el-button>
      </div>
    </div>

    <UserTable
      :users="users"
      :loading="tableLoading"
      @edit="openEditDialog"
      @delete="handleDelete"
      @generate-link="showLoginLink"
    />

    <div class="pagination-wrapper">
      <el-pagination
        v-model:current-page="page"
        v-model:page-size="pageSize"
        :total="total"
        :page-sizes="[10, 20, 50, 100]"
        layout="total, sizes, prev, pager, next, jumper"
        @change="loadUsers"
      />
    </div>

    <UserForm
      :visible="formVisible"
      :user="editingUser"
      :services="services"
      @close="formVisible = false"
      @submit="handleFormSubmit"
    />

    <el-dialog v-model="linkVisible" title="用户登录链接" width="500px">
      <p style="margin-bottom: 12px; color: #606266;">用户可通过以下链接直接登录：</p>
      <el-input
        v-model="loginLink"
        readonly
        type="textarea"
        :rows="3"
      />
      <template #footer>
        <el-button @click="linkVisible = false">关闭</el-button>
        <el-button type="primary" :icon="CopyDocument" @click="copyLink">复制链接</el-button>
      </template>
    </el-dialog>

    <el-dialog v-model="batchVisible" title="批量创建用户" width="420px">
      <el-form :model="batchForm" label-width="100px">
        <el-form-item label="创建数量">
          <el-input-number v-model="batchForm.count" :min="1" :max="100" />
        </el-form-item>
        <el-form-item label="绑定客服">
          <el-select v-model="batchForm.serviceUserId" placeholder="请选择客服" style="width:100%">
            <el-option
              v-for="svc in services"
              :key="svc.userId"
              :label="svc.nickname"
              :value="svc.userId"
            />
          </el-select>
        </el-form-item>
        <el-form-item label="昵称前缀">
          <el-input v-model="batchForm.prefix" placeholder="可选，如：用户" />
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="batchVisible = false">取消</el-button>
        <el-button type="primary" :loading="batchLoading" @click="handleBatchCreate">确认创建</el-button>
      </template>
    </el-dialog>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted, reactive } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import { Plus, Operation, CopyDocument } from '@element-plus/icons-vue'
import { getUsers, deleteUser, createUser, updateUser, batchCreateUsers, getServices } from '@/services/api'
import UserTable from '@/components/UserTable.vue'
import UserForm from '@/components/UserForm.vue'

interface User {
  id: string
  nickname: string
  serviceUserId: string
  serviceName: string
  status: number
  createdAt: string
}

interface Service {
  userId: string
  nickname: string
}

const users = ref<User[]>([])
const services = ref<Service[]>([])
const tableLoading = ref(false)
const page = ref(1)
const pageSize = ref(20)
const total = ref(0)
const searchKeyword = ref('')

const formVisible = ref(false)
const editingUser = ref<User | null>(null)
const linkVisible = ref(false)
const loginLink = ref('')
const batchVisible = ref(false)
const batchLoading = ref(false)

const batchForm = reactive({
  count: 10,
  serviceUserId: '',
  prefix: ''
})

const loadUsers = async () => {
  tableLoading.value = true
  try {
    const res = await getUsers(page.value, pageSize.value, searchKeyword.value)
    users.value = res.data.list || []
    total.value = res.data.total || 0
  } catch {
    // handled by interceptor
  } finally {
    tableLoading.value = false
  }
}

const loadServices = async () => {
  try {
    const res = await getServices()
    services.value = res.data.list || res.data || []
  } catch {
    // handled
  }
}

const openCreateDialog = () => {
  editingUser.value = null
  formVisible.value = true
}

const openEditDialog = (user: User) => {
  editingUser.value = user
  formVisible.value = true
}

const handleFormSubmit = async (formData: { nickname: string; serviceUserId: string; avatar?: string }) => {
  try {
    if (editingUser.value) {
      await updateUser(editingUser.value.id, formData)
      ElMessage.success('更新成功')
    } else {
      await createUser(formData)
      ElMessage.success('创建成功')
    }
    formVisible.value = false
    loadUsers()
  } catch {
    // handled
  }
}

const handleDelete = async (user: User) => {
  try {
    await ElMessageBox.confirm(`确认删除用户 "${user.nickname}" 吗？`, '删除确认', {
      confirmButtonText: '确认删除',
      cancelButtonText: '取消',
      type: 'warning'
    })
    await deleteUser(user.id)
    ElMessage.success('删除成功')
    loadUsers()
  } catch (e: unknown) {
    if (e !== 'cancel') {
      // handled by interceptor
    }
  }
}

const showLoginLink = (user: User) => {
  const { protocol, hostname, port, origin } = window.location
  const isLocal = hostname === 'localhost' || hostname === '127.0.0.1'
  const h5BaseURL = isLocal && port === '3001'
    ? `${protocol}//${hostname}:3000`
    : origin

  loginLink.value = `${h5BaseURL}/chat?id=${user.id}`
  linkVisible.value = true
}

const copyLink = async () => {
  try {
    await navigator.clipboard.writeText(loginLink.value)
    ElMessage.success('链接已复制到剪贴板')
  } catch {
    ElMessage.warning('复制失败，请手动复制')
  }
}

const handleBatchCreate = async () => {
  if (!batchForm.serviceUserId) {
    ElMessage.warning('请选择绑定客服')
    return
  }
  batchLoading.value = true
  try {
    await batchCreateUsers(batchForm)
    ElMessage.success(`成功批量创建 ${batchForm.count} 个用户`)
    batchVisible.value = false
    loadUsers()
  } catch {
    // handled
  } finally {
    batchLoading.value = false
  }
}

onMounted(() => {
  loadUsers()
  loadServices()
})
</script>

<style scoped>
.user-manage {
  padding: 0;
}

.page-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 20px;
  flex-wrap: wrap;
  gap: 12px;
}

.page-header h2 {
  font-size: 20px;
  color: #303133;
}

.header-actions {
  display: flex;
  align-items: center;
  gap: 8px;
  flex-wrap: wrap;
}

.pagination-wrapper {
  display: flex;
  justify-content: flex-end;
  margin-top: 20px;
}
</style>
