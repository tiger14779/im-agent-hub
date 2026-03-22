<template>
  <div class="service-manage">
    <div class="page-header">
      <h2>客服管理</h2>
      <el-button type="primary" :icon="Plus" @click="openCreateDialog">添加客服</el-button>
    </div>

    <el-table :data="services" v-loading="loading" border stripe>
      <el-table-column prop="id" label="ID" width="200" show-overflow-tooltip />
      <el-table-column label="头像" width="80">
        <template #default="{ row }">
          <el-avatar :size="36" :src="row.avatar" :icon="UserFilled" />
        </template>
      </el-table-column>
      <el-table-column prop="nickname" label="昵称" />
      <el-table-column prop="userId" label="用户ID" show-overflow-tooltip />
      <el-table-column label="状态" width="100">
        <template #default="{ row }">
          <el-tag :type="row.status === 1 ? 'success' : 'danger'">
            {{ row.status === 1 ? '启用' : '禁用' }}
          </el-tag>
        </template>
      </el-table-column>
      <el-table-column prop="createdAt" label="创建时间" width="180" />
      <el-table-column label="操作" width="220" fixed="right">
        <template #default="{ row }">
          <el-button size="small" @click="openEditDialog(row)">编辑</el-button>
          <el-button
            size="small"
            :type="row.status === 1 ? 'warning' : 'success'"
            @click="toggleStatus(row)"
          >
            {{ row.status === 1 ? '禁用' : '启用' }}
          </el-button>
          <el-button size="small" type="danger" @click="handleDelete(row)">删除</el-button>
        </template>
      </el-table-column>
    </el-table>

    <!-- Create/Edit Dialog -->
    <el-dialog v-model="dialogVisible" :title="editingService ? '编辑客服' : '添加客服'" width="440px">
      <el-form :model="form" :rules="rules" ref="formRef" label-width="80px">
        <el-form-item label="用户ID" prop="userId" v-if="!editingService">
          <el-input v-model="form.userId" placeholder="请输入客服用户ID" />
        </el-form-item>
        <el-form-item label="昵称" prop="nickname">
          <el-input v-model="form.nickname" placeholder="请输入客服昵称" />
        </el-form-item>
        <el-form-item label="头像URL">
          <el-input v-model="form.avatar" placeholder="请输入头像URL（可选）" />
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="dialogVisible = false">取消</el-button>
        <el-button type="primary" :loading="submitLoading" @click="handleSubmit">
          {{ editingService ? '保存' : '创建' }}
        </el-button>
      </template>
    </el-dialog>
  </div>
</template>

<script setup lang="ts">
import { ref, reactive, onMounted } from 'vue'
import { ElMessage, ElMessageBox, type FormInstance, type FormRules } from 'element-plus'
import { Plus, UserFilled } from '@element-plus/icons-vue'
import { getServices, createService, updateService, deleteService } from '@/services/api'

interface ServiceStaff {
  id: string
  userId: string
  nickname: string
  avatar: string
  status: number
  createdAt: string
}

const services = ref<ServiceStaff[]>([])
const loading = ref(false)
const dialogVisible = ref(false)
const editingService = ref<ServiceStaff | null>(null)
const submitLoading = ref(false)
const formRef = ref<FormInstance>()

const form = reactive({
  userId: '',
  nickname: '',
  avatar: ''
})

const rules: FormRules = {
  userId: [{ required: true, message: '请输入用户ID', trigger: 'blur' }],
  nickname: [{ required: true, message: '请输入客服昵称', trigger: 'blur' }]
}

const loadServices = async () => {
  loading.value = true
  try {
    const res = await getServices()
    services.value = res.data.list || res.data || []
  } catch {
    // handled
  } finally {
    loading.value = false
  }
}

const openCreateDialog = () => {
  editingService.value = null
  form.userId = ''
  form.nickname = ''
  form.avatar = ''
  dialogVisible.value = true
}

const openEditDialog = (svc: ServiceStaff) => {
  editingService.value = svc
  form.userId = svc.userId
  form.nickname = svc.nickname
  form.avatar = svc.avatar
  dialogVisible.value = true
}

const handleSubmit = async () => {
  if (!formRef.value) return
  await formRef.value.validate(async (valid) => {
    if (!valid) return
    submitLoading.value = true
    try {
      if (editingService.value) {
        await updateService(editingService.value.id, {
          nickname: form.nickname,
          avatar: form.avatar
        })
        ElMessage.success('更新成功')
      } else {
        await createService(form)
        ElMessage.success('创建成功')
      }
      dialogVisible.value = false
      loadServices()
    } catch {
      // handled
    } finally {
      submitLoading.value = false
    }
  })
}

const toggleStatus = async (svc: ServiceStaff) => {
  const newStatus = svc.status === 1 ? 0 : 1
  try {
    await updateService(svc.id, { status: newStatus })
    ElMessage.success(newStatus === 1 ? '已启用' : '已禁用')
    loadServices()
  } catch {
    // handled
  }
}

const handleDelete = async (svc: ServiceStaff) => {
  try {
    await ElMessageBox.confirm(`确认删除客服 "${svc.nickname}" 吗？`, '删除确认', {
      confirmButtonText: '确认删除',
      cancelButtonText: '取消',
      type: 'warning'
    })
    await deleteService(svc.id)
    ElMessage.success('删除成功')
    loadServices()
  } catch (e: unknown) {
    if (e !== 'cancel') {
      // handled
    }
  }
}

onMounted(loadServices)
</script>

<style scoped>
.service-manage {
  padding: 0;
}

.page-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 20px;
}

.page-header h2 {
  font-size: 20px;
  color: #303133;
}
</style>
