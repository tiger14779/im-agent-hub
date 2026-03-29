<template>
  <div v-if="issue" class="lottery-result">
    <div class="lottery-left">
      <span class="lottery-issue">上期 第 <em>{{ issue }}</em> 期</span>
      <div class="lottery-balls">
        <div
          v-for="(num, idx) in balls"
          :key="idx"
          class="ball"
          :class="ballColor(idx)"
        >
          {{ num }}
        </div>
      </div>
    </div>
    <div class="lottery-right">
      <span class="lottery-current">当前:第 <em>{{ nextIssue }}</em> 期</span>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted, onUnmounted } from 'vue'

const issue = ref('')
const nextIssue = ref('')
const balls = ref<string[]>([])

let nextTimer: ReturnType<typeof setTimeout> | null = null
let retryTimer: ReturnType<typeof setTimeout> | null = null

// 解析开奖时间字符串为本地时间戳
function parseDrawTime(timeStr: string): number {
  // "2026-03-29 16:48:40" → Date
  return new Date(timeStr.replace(' ', 'T')).getTime()
}

// 计算距离下一期开奖的等待毫秒数：开奖时间 + 5分钟 + 10秒延迟
function msUntilNextDraw(drawTimeStr: string): number {
  const drawMs = parseDrawTime(drawTimeStr)
  const nextMs = drawMs + 5 * 60 * 1000 + 10 * 1000 // +5min +10s
  const wait = nextMs - Date.now()
  return wait > 0 ? wait : 1000 // 如果已经过了就1秒后刷新
}

async function fetchLatest(): Promise<boolean> {
  try {
    const res = await fetch('/api/lottery/latest')
    const json = await res.json()
    if (json.errorCode === 0 && json.result?.data?.length) {
      const first = json.result.data[0]
      const newIssue = String(first.preDrawIssue)
      const isNew = newIssue !== issue.value
      issue.value = newIssue
      nextIssue.value = String(Number(newIssue) + 1)
      balls.value = (first.preDrawCode as string).split(',')

      // 根据本期开奖时间安排下一次刷新
      if (first.preDrawTime) {
        scheduleNext(first.preDrawTime)
      }
      return isNew
    }
  } catch (e) {
    console.warn('[Lottery] fetch failed', e)
  }
  return false
}

// 带重试的请求：如果没拿到新数据，间隔3秒再试，最多重试2次
async function fetchWithRetry(prevIssue: string, retryLeft = 2) {
  const isNew = await fetchLatest()
  if (!isNew && retryLeft > 0) {
    retryTimer = setTimeout(() => fetchWithRetry(prevIssue, retryLeft - 1), 3000)
  }
}

function scheduleNext(drawTimeStr: string) {
  clearTimers()
  const wait = msUntilNextDraw(drawTimeStr)
  const currentIssue = issue.value
  nextTimer = setTimeout(() => fetchWithRetry(currentIssue), wait)
}

function clearTimers() {
  if (nextTimer) { clearTimeout(nextTimer); nextTimer = null }
  if (retryTimer) { clearTimeout(retryTimer); retryTimer = null }
}

function ballColor(idx: number): string {
  const colors = ['ball-red', 'ball-blue', 'ball-green', 'ball-orange', 'ball-purple']
  return colors[idx % colors.length]
}

onMounted(() => {
  fetchLatest()
})

onUnmounted(() => {
  clearTimers()
})
</script>

<style scoped>
.lottery-result {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 6px 12px;
  background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
  border-bottom: 1px solid rgba(255, 255, 255, 0.08);
  flex-shrink: 0;
}

.lottery-left {
  display: flex;
  align-items: center;
  gap: 8px;
}

.lottery-right {
  flex-shrink: 0;
}

.lottery-issue {
  font-size: 11px;
  color: rgba(255, 255, 255, 0.7);
  white-space: nowrap;
}

.lottery-issue em {
  font-style: normal;
  color: #ffd700;
  font-weight: 600;
}

.lottery-current {
  font-size: 12px;
  color: rgba(255, 255, 255, 0.85);
  white-space: nowrap;
}

.lottery-current em {
  font-style: normal;
  color: #56ccf2;
  font-weight: 600;
}

.lottery-balls {
  display: flex;
  gap: 5px;
}

.ball {
  width: 28px;
  height: 28px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 13px;
  font-weight: 700;
  color: #fff;
  text-shadow: 0 1px 2px rgba(0, 0, 0, 0.3);
  box-shadow:
    inset 0 -3px 6px rgba(0, 0, 0, 0.25),
    inset 0 3px 6px rgba(255, 255, 255, 0.25),
    0 2px 8px rgba(0, 0, 0, 0.3);
  position: relative;
  overflow: hidden;
}

/* 球面高光效果 */
.ball::before {
  content: '';
  position: absolute;
  top: 2px;
  left: 5px;
  width: 11px;
  height: 8px;
  background: radial-gradient(ellipse, rgba(255, 255, 255, 0.5) 0%, transparent 70%);
  border-radius: 50%;
}

.ball-red {
  background: radial-gradient(circle at 35% 35%, #ff6b6b, #e63946);
}

.ball-blue {
  background: radial-gradient(circle at 35% 35%, #74b9ff, #0984e3);
}

.ball-green {
  background: radial-gradient(circle at 35% 35%, #55efc4, #00b894);
}

.ball-orange {
  background: radial-gradient(circle at 35% 35%, #ffa751, #e17055);
}

.ball-purple {
  background: radial-gradient(circle at 35% 35%, #a29bfe, #6c5ce7);
}

/* 小屏适配 */
@media (max-width: 360px) {
  .lottery-balls {
    gap: 4px;
  }
  .ball {
    width: 24px;
    height: 24px;
    font-size: 11px;
  }
  .lottery-issue {
    font-size: 10px;
  }
  .lottery-current {
    font-size: 10px;
  }
}
</style>
