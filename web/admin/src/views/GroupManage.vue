<template>
  <div class="group-manage">
    <div class="page-header">
      <h2>群组管理</h2>
      <el-button type="primary" :icon="Plus" @click="openCreateDialog">创建群组</el-button>
    </div>

    <el-table :data="groups" :loading="tableLoading" stripe border style="width: 100%">
      <el-table-column label="头像" width="72" align="center">
        <template #default="{ row }">
          <el-avatar v-if="row.avatar" :size="36" :src="row.avatar" />
          <el-avatar v-else :size="36" style="background:#67c23a;font-size:14px">群</el-avatar>
        </template>
      </el-table-column>
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
      <el-table-column label="操作" width="160" align="center">
        <template #default="{ row }">
          <el-button
            type="primary"
            size="small"
            :disabled="row.dissolved"
            @click="openEditDialog(row)"
          >
            编辑
          </el-button>
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
        <el-form-item label="头像URL">
          <el-input v-model="createForm.avatar" placeholder="（可选）群头像图片链接" />
          <div v-if="createForm.avatar" style="margin-top:6px">
            <el-avatar :size="48" :src="createForm.avatar" />
          </div>
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="createVisible = false">取消</el-button>
        <el-button type="primary" :loading="createLoading" @click="handleCreate">创建</el-button>
      </template>
    </el-dialog>

    <!-- 编辑群组对话框 -->
    <el-dialog v-model="editVisible" title="编辑群组" width="420px">
      <el-form :model="editForm" ref="editFormRef" label-width="84px">
        <el-form-item label="群名称" :rules="[{ required: true, message: '请输入群名称', trigger: 'blur' }]">
          <el-input v-model="editForm.name" placeholder="请输入群名称" />
        </el-form-item>
        <el-form-item label="头像URL">
          <el-input v-model="editForm.avatar" placeholder="（可选）群头像图片链接" />
          <div v-if="editForm.avatar" style="margin-top:6px">
            <el-avatar :size="48" :src="editForm.avatar" />
          </div>
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="editVisible = false">取消</el-button>
        <el-button type="primary" :loading="editLoading" @click="handleEdit">保存</el-button>
      </template>
    </el-dialog>
  </div>
</template>

<script setup lang="ts">
import { ref, reactive, onMounted } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import { Plus } from '@element-plus/icons-vue'
import type { FormInstance, FormRules } from 'element-plus'
import { getGroups, createGroup, updateGroup, deleteGroup, getServices } from '@/services/api'

interface Group {
  id: string
  name: string
  avatar: string
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
const editVisible = ref(false)
const editLoading = ref(false)
let editingGroupId = ''

const createFormRef = ref<FormInstance>()
const createForm = reactive({ name: '', ownerId: '', avatar: '' })
const createRules: FormRules = {
  name: [{ required: true, message: '请输入群名称', trigger: 'blur' }],
  ownerId: [{ required: true, message: '请选择群主', trigger: 'change' }]
}

const editFormRef = ref<FormInstance>()
const editForm = reactive({ name: '', avatar: '' })

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
  createForm.avatar = ''
  createVisible.value = true
}

const handleCreate = async () => {
  if (!createFormRef.value) return
  await createFormRef.value.validate(async (valid) => {
    if (!valid) return
    createLoading.value = true
    try {
      await createGroup({ name: createForm.name, ownerId: createForm.ownerId, avatar: createForm.avatar })
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

const openEditDialog = (group: Group) => {
  editingGroupId = group.id
  editForm.name = group.name
  editForm.avatar = group.avatar || ''
  editVisible.value = true
}

const handleEdit = async () => {
  if (!editFormRef.value) return
  await editFormRef.value.validate(async (valid) => {
    if (!valid) return
    editLoading.value = true
    try {
      await updateGroup(editingGroupId, { name: editForm.name, avatar: editForm.avatar })
      ElMessage.success('群组信息已更新')
      editVisible.value = false
      loadGroups()
    } catch {
      // handled
    } finally {
      editLoading.value = false
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
