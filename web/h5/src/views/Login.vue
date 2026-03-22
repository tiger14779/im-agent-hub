<template>
  <div class="login-page">
    <div class="login-card">
      <div class="login-logo">💬</div>
      <h1 class="login-title">客服咨询</h1>
      <p class="login-subtitle">请输入您的用户 ID 以开始聊天</p>

      <div class="login-form">
        <input
          v-model="userId"
          type="text"
          placeholder="请输入用户 ID"
          class="login-input"
          :disabled="loading"
          @keyup.enter="handleLogin"
        />
        <p v-if="errorMsg" class="login-error">{{ errorMsg }}</p>
        <button class="login-btn" :disabled="loading || !userId.trim()" @click="handleLogin">
          <span v-if="loading" class="btn-spinner" />
          <span v-else>进入聊天</span>
        </button>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import request from '@/utils/request'
import { useUserStore } from '@/stores/user'

const router = useRouter()
const route = useRoute()
const userStore = useUserStore()

const userId = ref((route.query.id as string) || '')
const loading = ref(false)
const errorMsg = ref('')

async function handleLogin() {
  const id = userId.value.trim()
  if (!id) return

  loading.value = true
  errorMsg.value = ''

  try {
    const res = await request.post<unknown, {
      token: string
      wsUrl?: string
      apiUrl?: string
      serviceUserId?: string
    }>('/client/auth/login', { userId: id })

    userStore.login({
      userId: id,
      token: res.token,
      serviceUserId: res.serviceUserId,
      wsUrl: res.wsUrl,
      apiUrl: res.apiUrl
    })

    router.replace({ path: '/chat', query: { id } })
  } catch (err) {
    errorMsg.value = (err as Error).message || '登录失败，请重试'
  } finally {
    loading.value = false
  }
}
</script>

<style scoped>
.login-page {
  width: 100%;
  height: 100%;
  background: var(--wechat-bg);
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 24px;
}

.login-card {
  width: 100%;
  max-width: 360px;
  background: #fff;
  border-radius: 12px;
  padding: 32px 24px;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 12px;
  box-shadow: 0 2px 12px rgba(0, 0, 0, 0.08);
}

.login-logo {
  font-size: 48px;
  margin-bottom: 4px;
}

.login-title {
  font-size: 20px;
  font-weight: 600;
  color: var(--wechat-text);
}

.login-subtitle {
  font-size: 13px;
  color: var(--wechat-text-secondary);
  text-align: center;
}

.login-form {
  width: 100%;
  display: flex;
  flex-direction: column;
  gap: 12px;
  margin-top: 8px;
}

.login-input {
  width: 100%;
  height: 44px;
  border: 1px solid var(--wechat-border);
  border-radius: 6px;
  padding: 0 14px;
  font-size: 15px;
  color: var(--wechat-text);
  background: #fafafa;
}

.login-input:focus {
  border-color: var(--wechat-green-dark);
}

.login-error {
  font-size: 13px;
  color: var(--wechat-red);
  text-align: center;
}

.login-btn {
  width: 100%;
  height: 44px;
  background: var(--wechat-green);
  border-radius: 6px;
  font-size: 16px;
  font-weight: 500;
  color: var(--wechat-text);
  display: flex;
  align-items: center;
  justify-content: center;
}

.login-btn:disabled {
  opacity: 0.5;
}

@keyframes spin {
  to { transform: rotate(360deg); }
}

.btn-spinner {
  display: inline-block;
  width: 18px;
  height: 18px;
  border: 2px solid rgba(0, 0, 0, 0.2);
  border-top-color: #333;
  border-radius: 50%;
  animation: spin 0.7s linear infinite;
}
</style>
