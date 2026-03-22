<template>
  <el-card class="stats-card" shadow="hover">
    <div class="card-content">
      <div class="icon-wrapper" :style="{ backgroundColor: `${color}15`, color: color }">
        <el-icon :size="28">
          <component :is="icon" />
        </el-icon>
      </div>
      <div class="info">
        <div class="value" :style="{ color: color }">
          <CountUp :end-val="value" :duration="1500" />
        </div>
        <div class="title">{{ title }}</div>
      </div>
    </div>
  </el-card>
</template>

<script setup lang="ts">
import { defineComponent, ref, watch, h } from 'vue'

const CountUp = defineComponent({
  name: 'CountUp',
  props: {
    endVal: { type: Number, default: 0 },
    duration: { type: Number, default: 1500 }
  },
  setup(props) {
    const current = ref(0)
    let animFrame: number | null = null

    const animate = (target: number) => {
      const start = current.value
      const startTime = performance.now()
      const step = (now: number) => {
        const elapsed = now - startTime
        const progress = Math.min(elapsed / props.duration, 1)
        current.value = Math.round(start + (target - start) * progress)
        if (progress < 1) {
          animFrame = requestAnimationFrame(step)
        }
      }
      if (animFrame) cancelAnimationFrame(animFrame)
      animFrame = requestAnimationFrame(step)
    }

    watch(() => props.endVal, (val) => animate(val), { immediate: true })

    return () => h('span', current.value.toLocaleString())
  }
})

defineProps<{
  title: string
  value: number
  icon: string
  color: string
}>()
</script>

<style scoped>
.stats-card {
  border-radius: 10px;
  transition: transform 0.2s;
}

.stats-card:hover {
  transform: translateY(-2px);
}

.card-content {
  display: flex;
  align-items: center;
  gap: 16px;
  padding: 8px 0;
}

.icon-wrapper {
  width: 56px;
  height: 56px;
  border-radius: 12px;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}

.info {
  flex: 1;
}

.value {
  font-size: 28px;
  font-weight: 700;
  line-height: 1.2;
  margin-bottom: 4px;
}

.title {
  font-size: 13px;
  color: #909399;
}
</style>
