<template>
  <div class="group-manage">
    <div class="page-header">
      <h2>群组管理</h2>
      <el-button type="primary" :icon="Plus" @click="openCreateDialog">创建群组</el-button>
    </div>

    <el-table :data="groups" :loading="tableLoading" stripe border style="width: 100%">
      <el-table-column label="群组ID" prop="id" width="180" />
      <el-table-column label="群名称" prop="name" min-width="140" />
      <el-table-column label="群主ID" prop="ownerId" min-width="160" />
      <el-table-column label="成员数" prop="memberCount" width="100" align="center" />
      <el-table-column label="状态" width="90" align="center">
        <template #default="{ row }">
          <el-tag :type="row.dissolved ? 'danger' : 'success'">
            {{ row.dissolved ? '已解散' : '正常' }}
          </el-tag>
        </template>
      </el-table-column>
      <el-table-column label="创建时间" prop="createdAt" min-width="160">
        <template #default="{ row }">
          {{ formatDate(row.createdAt) }}
        </template>
      </el-table-column>
      <el-table-column label="操作" width="120" align="center">
        <template #default="{ row }">
          <el-button
            type="danger"
            size="small"
            :disabled="row.dissolved"
            @click="handleDissolve(row)"
          >
            解散
          </el-button>
        </template>
      </el-table-column>
    </el-table>

    <!-- 创建群组对话框 -->
    <el-dialog v-model="createVisible" title="创建群组" width="420px">
      <el-form :model="createForm" :rules="createRules" ref="createFormRef" label-width="84px">
        <el-form-item label="群名称" prop="name">
          <el-input v-model="createForm.name" placeholder="请输入群名称" />
        </el-form-item>
        <el-form-item label="群主" prop="ownerId">
          <el-select v-model="createForm.ownerId" placeholder="请选择群主（客服）" style="width: 100%">
            <el-option
              v-for="svc in services"
              :key="svc.userId"
              :label="svc.nickname + ' (' + svc.userId + ')'"
              :value="svc.userId"
            />
          </el-select>
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="createVisible = false">取消</el-button>
        <el-button type="primary" :loading="createLoading" @click="handleCreate">创建</el-button>
      </template>
    </el-dialog>
  </div>
</template>

<script setup lang="ts">
import { ref, reactive, onMounted } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import { Plus } from '@element-plus/icons-vue'
import type { FormInstance, FormRules } from 'element-plus'
import { getGroups, createGroup, deleteGroup, getServices } from '@/services/api'

interface Group {
  id: string
  name: string
  ownerId: string
  memberCount: number
  dissolved: boolean
  createdAt: string
}

interface Service {
  userId: string
  nickname: string
}

const groups = ref<Group[]>([])
const services = ref<Service[]>([])
const tableLoading = ref(false)
const createVisible = ref(false)
const createLoading = ref(false)

const createFormRef = ref<FormInstance>()
const createForm = reactive({ name: '', ownerId: '' })
const createRules: FormRules = {
  name: [{ required: true, message: '请输入群名称', trigger: 'blur' }],
  ownerId: [{ required: true, message: '请选择群主', trigger: 'change' }]
}

function formatDate(iso: string) {
  if (!iso) return '-'
  return new Date(iso).toLocaleString('zh-CN', { hour12: false })
}

const loadGroups = async () => {
  tableLoading.value = true
  try {
    const res = await getGroups()
    groups.value = (res.data as { list?: Group[] }).list || []
  } catch {
    // handled by interceptor
  } finally {
    tableLoading.value = false
  }
}

const loadServices = async () => {
  try {
    const res = await getServices()
    services.value = (res.data as { list?: Service[] }).list || (res.data as Service[]) || []
  } catch {
    // handled
  }
}

const openCreateDialog = () => {
  createForm.name = ''
  createForm.ownerId = ''
  createVisible.value = true
}

const handleCreate = async () => {
  if (!createFormRef.value) return
  await createFormRef.value.validate(async (valid) => {
    if (!valid) return
    createLoading.value = true
    try {
      await createGroup({ name: createForm.name, ownerId: createForm.ownerId })
      ElMessage.success('群组创建成功')
      createVisible.value = false
      loadGroups()
    } catch {
      // handled
    } finally {
      createLoading.value = false
    }
  })
}

const handleDissolve = async (group: Group) => {
  try {
    await ElMessageBox.confirm(
      `确认解散群组「${group.name}」吗？解散后群成员将收到通知，操作不可撤销。`,
      '解散确认',
      { confirmButtonText: '确认解散', cancelButtonText: '取消', type: 'warning' }
    )
    await deleteGroup(group.id)
    ElMessage.success('群组已解散')
    loadGroups()
  } catch (e: unknown) {
    if (e !== 'cancel') {
      // handled by interceptor
    }
  }
}

onMounted(() => {
  loadGroups()
  loadServices()
})
</script>

<style scoped>
.group-manage {
  padding: 0;
}
.page-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 20px;
}
.page-header h2 {
  margin: 0;
  font-size: 20px;
  font-weight: 600;
  color: #303133;
}
</style>
