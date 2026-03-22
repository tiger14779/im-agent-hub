<template>
  <div class="dashboard">
    <div class="page-header">
      <h2>仪表盘</h2>
      <el-button :icon="RefreshRight" @click="loadStats" :loading="loading">刷新</el-button>
    </div>

    <el-row :gutter="20" class="stats-row">
      <el-col :xs="24" :sm="12" :lg="6">
        <StatsCard title="用户总数" :value="stats.totalUsers" icon="User" color="#409EFF" />
      </el-col>
      <el-col :xs="24" :sm="12" :lg="6">
        <StatsCard title="今日新增" :value="stats.todayNew" icon="UserFilled" color="#67C23A" />
      </el-col>
      <el-col :xs="24" :sm="12" :lg="6">
        <StatsCard title="在线用户" :value="stats.onlineUsers" icon="Connection" color="#E6A23C" />
      </el-col>
      <el-col :xs="24" :sm="12" :lg="6">
        <StatsCard title="客服数量" :value="stats.serviceCount" icon="Service" color="#F56C6C" />
      </el-col>
    </el-row>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { RefreshRight } from '@element-plus/icons-vue'
import { getStats } from '@/services/api'
import StatsCard from '@/components/StatsCard.vue'

const loading = ref(false)
const stats = ref({
  totalUsers: 0,
  todayNew: 0,
  onlineUsers: 0,
  serviceCount: 0
})

const loadStats = async () => {
  loading.value = true
  try {
    const res = await getStats()
    stats.value = res.data
  } catch {
    // handled by interceptor
  } finally {
    loading.value = false
  }
}

onMounted(loadStats)
</script>

<style scoped>
.dashboard {
  padding: 0;
}

.page-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 24px;
}

.page-header h2 {
  font-size: 20px;
  color: #303133;
}

.stats-row .el-col {
  margin-bottom: 20px;
}
</style>
