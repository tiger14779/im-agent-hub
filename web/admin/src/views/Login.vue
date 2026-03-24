<template>
  <div class="login-container">
    <div class="login-box">
      <div class="login-header">
        <el-icon class="login-icon" :size="40" color="#409EFF"><Monitor /></el-icon>
        <h2>管理后台</h2>
        <p>IM代理中心管理系统</p>
      </div>
      <el-form
        ref="formRef"
        :model="form"
        :rules="rules"
        size="large"
        @submit.prevent="handleLogin"
      >
        <el-form-item prop="username">
          <el-input
            v-model="form.username"
            placeholder="请输入用户名"
            prefix-icon="User"
            clearable
          />
        </el-form-item>
        <el-form-item prop="password">
          <el-input
            v-model="form.password"
            type="password"
            placeholder="请输入密码"
            prefix-icon="Lock"
            show-password
            clearable
          />
        </el-form-item>
        <el-form-item>
          <el-button
            type="primary"
            style="width: 100%"
            :loading="loading"
            @click="handleLogin"
          >
            登 录
          </el-button>
        </el-form-item>
      </el-form>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, reactive } from 'vue'
import { useRouter } from 'vue-router'
import { ElMessage, type FormInstance, type FormRules } from 'element-plus'
import { adminLogin } from '@/services/api'
import { useAuthStore } from '@/stores/auth'

const router = useRouter()
const authStore = useAuthStore()
const formRef = ref<FormInstance>()
const loading = ref(false)

const form = reactive({
  username: '',
  password: ''
})

const rules: FormRules = {
  username: [{ required: true, message: '请输入用户名', trigger: 'blur' }],
  password: [{ required: true, message: '请输入密码', trigger: 'blur' }]
}

const handleLogin = async () => {
  if (!formRef.value) return
  try {
    await formRef.value.validate()
  } catch {
    return // validation failed
  }
  loading.value = true
  try {
    const res = await adminLogin(form.username, form.password)
    const responseData = res?.data
    const loginData = responseData?.data && typeof responseData.data === 'object'
      ? responseData.data
      : responseData

    const token = loginData?.token
    const username = loginData?.username

    if (!token || typeof token !== 'string') {
      ElMessage.error('登录响应异常，请重试')
      return
    }

    authStore.setAuth(token, username || form.username)
    ElMessage.success('登录成功')
    await router.replace('/admin/dashboard')
  } catch {
    // Error handled by interceptor
  } finally {
    loading.value = false
  }
}
</script>

<style scoped>
.login-container {
  display: flex;
  justify-content: center;
  align-items: center;
  min-height: 100vh;
  background: linear-gradient(135deg, #1a1a2e 0%, #16213e 50%, #0f3460 100%);
}

.login-box {
  width: 420px;
  padding: 40px;
  background: rgba(255, 255, 255, 0.95);
  border-radius: 12px;
  box-shadow: 0 20px 60px rgba(0, 0, 0, 0.4);
}

.login-header {
  text-align: center;
  margin-bottom: 32px;
}

.login-icon {
  margin-bottom: 12px;
}

.login-header h2 {
  font-size: 24px;
  color: #303133;
  margin-bottom: 8px;
}

.login-header p {
  color: #909399;
  font-size: 14px;
}
</style>
