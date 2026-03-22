<template>
  <div class="layout-container">
    <!-- Sidebar -->
    <aside class="sidebar" :class="{ collapsed: sidebarCollapsed }">
      <div class="sidebar-logo">
        <el-icon :size="24" color="#409EFF"><ChatDotRound /></el-icon>
        <span v-show="!sidebarCollapsed" class="logo-text">IM代理中心</span>
      </div>
      <el-menu
        :default-active="activeMenu"
        :collapse="sidebarCollapsed"
        router
        background-color="#1a1a2e"
        text-color="#c0c4cc"
        active-text-color="#409EFF"
        class="sidebar-menu"
      >
        <el-menu-item index="/admin/dashboard">
          <el-icon><Odometer /></el-icon>
          <template #title>仪表盘</template>
        </el-menu-item>
        <el-menu-item index="/admin/users">
          <el-icon><User /></el-icon>
          <template #title>用户管理</template>
        </el-menu-item>
        <el-menu-item index="/admin/services">
          <el-icon><Service /></el-icon>
          <template #title>客服管理</template>
        </el-menu-item>
        <el-menu-item index="/admin/settings">
          <el-icon><Setting /></el-icon>
          <template #title>系统设置</template>
        </el-menu-item>
      </el-menu>
    </aside>

    <!-- Main Area -->
    <div class="main-wrapper">
      <!-- Top Bar -->
      <header class="topbar">
        <div class="topbar-left">
          <el-button
            :icon="sidebarCollapsed ? Expand : Fold"
            text
            @click="sidebarCollapsed = !sidebarCollapsed"
          />
          <breadcrumb-nav />
        </div>
        <div class="topbar-right">
          <el-icon style="margin-right: 6px; color: #909399;"><Avatar /></el-icon>
          <span class="username">{{ authStore.username }}</span>
          <el-divider direction="vertical" />
          <el-button text type="danger" :icon="SwitchButton" @click="handleLogout">退出登录</el-button>
        </div>
      </header>

      <!-- Content -->
      <main class="content">
        <router-view />
      </main>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, computed, defineComponent, h } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { ElMessageBox } from 'element-plus'
import {
  Odometer, User, Service, Setting, ChatDotRound,
  Avatar, SwitchButton, Fold, Expand
} from '@element-plus/icons-vue'
import { useAuthStore } from '@/stores/auth'

const BreadcrumbNav = defineComponent({
  name: 'BreadcrumbNav',
  setup() {
    return () => h('span')
  }
})

const authStore = useAuthStore()
const route = useRoute()
const router = useRouter()
const sidebarCollapsed = ref(false)

const activeMenu = computed(() => route.path)

const handleLogout = async () => {
  try {
    await ElMessageBox.confirm('确认退出登录吗？', '退出确认', {
      confirmButtonText: '退出',
      cancelButtonText: '取消',
      type: 'warning'
    })
    authStore.logout()
    router.push('/admin/login')
  } catch {
    // cancelled
  }
}
</script>

<style scoped>
.layout-container {
  display: flex;
  height: 100vh;
  overflow: hidden;
  background: #f5f7fa;
}

.sidebar {
  width: 220px;
  background: #1a1a2e;
  display: flex;
  flex-direction: column;
  transition: width 0.3s;
  overflow: hidden;
  flex-shrink: 0;
}

.sidebar.collapsed {
  width: 64px;
}

.sidebar-logo {
  height: 60px;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 10px;
  padding: 0 16px;
  border-bottom: 1px solid rgba(255, 255, 255, 0.1);
  overflow: hidden;
}

.logo-text {
  color: #fff;
  font-size: 15px;
  font-weight: 600;
  white-space: nowrap;
}

.sidebar-menu {
  flex: 1;
  border-right: none !important;
  overflow-y: auto;
  overflow-x: hidden;
}

.main-wrapper {
  flex: 1;
  display: flex;
  flex-direction: column;
  overflow: hidden;
}

.topbar {
  height: 60px;
  background: #fff;
  border-bottom: 1px solid #e4e7ed;
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 0 20px;
  flex-shrink: 0;
  box-shadow: 0 1px 4px rgba(0, 21, 41, 0.08);
}

.topbar-left {
  display: flex;
  align-items: center;
  gap: 12px;
}

.topbar-right {
  display: flex;
  align-items: center;
}

.username {
  font-size: 14px;
  color: #606266;
  margin-right: 4px;
}

.content {
  flex: 1;
  padding: 24px;
  overflow-y: auto;
}
</style>
