<template>
  <div class="settings">
    <h2 style="margin-bottom: 24px; color: #303133;">系统设置</h2>

    <!-- Chat cleanup settings -->
    <el-card class="settings-card" shadow="never">
      <template #header>
        <span class="card-title">聊天记录清理设置</span>
      </template>
      <el-form :model="cleanupForm" label-width="140px">
        <el-form-item label="启用自动清理">
          <el-switch v-model="cleanupForm.enabled" />
        </el-form-item>
        <el-form-item label="保留天数">
          <el-input-number
            v-model="cleanupForm.retentionDays"
            :min="1"
            :disabled="!cleanupForm.enabled"
            style="width: 160px"
          />
          <span style="margin-left: 8px; color: #909399;">天</span>
        </el-form-item>
        <el-form-item label="Cron 表达式">
          <el-input
            v-model="cleanupForm.cronExpression"
            placeholder="如：0 0 2 * * ?"
            :disabled="!cleanupForm.enabled"
            style="width: 240px"
          />
          <el-tooltip content="标准 Cron 表达式，建议设置在凌晨低峰时段" placement="right">
            <el-icon style="margin-left: 8px; cursor: pointer; color: #909399;"><QuestionFilled /></el-icon>
          </el-tooltip>
        </el-form-item>
        <el-form-item>
          <el-button type="primary" :loading="cleanupSaving" @click="saveCleanupSettings">保存设置</el-button>
        </el-form-item>
      </el-form>
    </el-card>

    <!-- Change password -->
    <el-card class="settings-card" shadow="never">
      <template #header>
        <span class="card-title">修改管理员密码</span>
      </template>
      <el-form :model="passwordForm" :rules="passwordRules" ref="passwordFormRef" label-width="120px" style="max-width: 480px">
        <el-form-item label="当前密码" prop="currentPassword">
          <el-input
            v-model="passwordForm.currentPassword"
            type="password"
            placeholder="请输入当前密码"
            show-password
          />
        </el-form-item>
        <el-form-item label="新密码" prop="newPassword">
          <el-input
            v-model="passwordForm.newPassword"
            type="password"
            placeholder="请输入新密码（至少6位）"
            show-password
          />
        </el-form-item>
        <el-form-item label="确认新密码" prop="confirmPassword">
          <el-input
            v-model="passwordForm.confirmPassword"
            type="password"
            placeholder="请再次输入新密码"
            show-password
          />
        </el-form-item>
        <el-form-item>
          <el-button type="primary" :loading="passwordSaving" @click="changeAdminPassword">修改密码</el-button>
        </el-form-item>
      </el-form>
    </el-card>
  </div>
</template>

<script setup lang="ts">
import { ref, reactive, onMounted } from 'vue'
import { ElMessage, type FormInstance, type FormRules } from 'element-plus'
import { getSettings, updateSettings, changePassword } from '@/services/api'

const cleanupSaving = ref(false)
const passwordSaving = ref(false)
const passwordFormRef = ref<FormInstance>()

const cleanupForm = reactive({
  enabled: false,
  retentionDays: 45,
  cronExpression: '0 0 2 * * ?'
})

const passwordForm = reactive({
  currentPassword: '',
  newPassword: '',
  confirmPassword: ''
})

const validateConfirmPassword = (_rule: unknown, value: string, callback: (e?: Error) => void) => {
  if (value !== passwordForm.newPassword) {
    callback(new Error('两次输入的密码不一致'))
  } else {
    callback()
  }
}

const passwordRules: FormRules = {
  currentPassword: [{ required: true, message: '请输入当前密码', trigger: 'blur' }],
  newPassword: [
    { required: true, message: '请输入新密码', trigger: 'blur' },
    { min: 6, message: '密码至少6位', trigger: 'blur' }
  ],
  confirmPassword: [
    { required: true, message: '请确认新密码', trigger: 'blur' },
    { validator: validateConfirmPassword, trigger: 'blur' }
  ]
}

const loadSettings = async () => {
  try {
    const res = await getSettings()
    const data = res.data
    cleanupForm.enabled = data.cleanupEnabled ?? false
    cleanupForm.retentionDays = data.retentionDays ?? 45
    cleanupForm.cronExpression = data.cronExpression ?? '0 0 2 * * ?'
  } catch {
    // handled
  }
}

const saveCleanupSettings = async () => {
  cleanupSaving.value = true
  try {
    await updateSettings({
      cleanupEnabled: cleanupForm.enabled,
      retentionDays: cleanupForm.retentionDays,
      cronExpression: cleanupForm.cronExpression
    })
    ElMessage.success('设置保存成功')
  } catch {
    // handled
  } finally {
    cleanupSaving.value = false
  }
}

const changeAdminPassword = async () => {
  if (!passwordFormRef.value) return
  await passwordFormRef.value.validate(async (valid) => {
    if (!valid) return
    passwordSaving.value = true
    try {
      await changePassword(passwordForm.currentPassword, passwordForm.newPassword)
      ElMessage.success('密码修改成功')
      passwordForm.currentPassword = ''
      passwordForm.newPassword = ''
      passwordForm.confirmPassword = ''
    } catch {
      // handled
    } finally {
      passwordSaving.value = false
    }
  })
}

onMounted(loadSettings)
</script>

<style scoped>
.settings-card {
  margin-bottom: 24px;
  border-radius: 8px;
}

.card-title {
  font-weight: 600;
  font-size: 15px;
  color: #303133;
}
</style>
