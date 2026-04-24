<template>
  <transition name="slide-up">
    <div v-if="visible" class="emoji-panel-overlay" @click.self="close">
      <div class="emoji-panel">
        <div class="emoji-panel-header">
          <span class="emoji-panel-title">表情</span>
          <button class="emoji-panel-close" @click="close">✕</button>
        </div>
        <div v-if="loading" class="emoji-panel-loading">加载中…</div>
        <div v-else-if="emojis.length === 0" class="emoji-panel-empty">
          暂无表情<br /><small>请联系管理员上传到 data/Emoji 目录</small>
        </div>
        <div v-else class="emoji-grid">
          <button
            v-for="e in sortedEmojis"
            :key="e.url"
            class="emoji-item"
            @click="onPick(e)"
          >
            <img
              :src="e.url"
              :alt="e.name"
              loading="lazy"
              decoding="async"
              class="emoji-img"
            />
          </button>
        </div>
      </div>
    </div>
  </transition>
</template>

<script setup lang="ts">
import { computed, ref, watch } from 'vue'

interface EmojiItem {
  name: string
  url: string
}

const props = defineProps<{
  visible: boolean
  userId: string  // 用于按用户区分 MRU 排序
}>()

const emit = defineEmits<{
  (e: 'close'): void
  (e: 'pick', emoji: EmojiItem): void
}>()

const emojis = ref<EmojiItem[]>([])
const loading = ref(false)
// 强制刷新 sortedEmojis 的 key（点击表情后让其重排）
const sortTick = ref(0)

// session 缓存：避免短时间内重复请求列表接口
const SESSION_KEY = 'emoji_list_cache_v1'

async function loadEmojis() {
  // 优先用 sessionStorage 中的列表（同会话内不再请求）
  try {
    const cached = sessionStorage.getItem(SESSION_KEY)
    if (cached) {
      emojis.value = JSON.parse(cached) as EmojiItem[]
      return
    }
  } catch {}

  loading.value = true
  try {
    const resp = await fetch('/api/emojis')
    const json = await resp.json()
    const list: EmojiItem[] = Array.isArray(json?.data?.emojis) ? json.data.emojis : []
    emojis.value = list
    try { sessionStorage.setItem(SESSION_KEY, JSON.stringify(list)) } catch {}
  } catch (err) {
    console.error('[emoji] load failed', err)
    emojis.value = []
  } finally {
    loading.value = false
  }
}

// MRU：localStorage[`emoji_mru_<userId>`] = { name: timestamp }
function mruKey() {
  return `emoji_mru_${props.userId || 'anonymous'}`
}
function readMru(): Record<string, number> {
  try {
    const raw = localStorage.getItem(mruKey())
    if (!raw) return {}
    const obj = JSON.parse(raw)
    return typeof obj === 'object' && obj ? obj : {}
  } catch {
    return {}
  }
}
function touchMru(name: string) {
  const m = readMru()
  m[name] = Date.now()
  try { localStorage.setItem(mruKey(), JSON.stringify(m)) } catch {}
}

const sortedEmojis = computed(() => {
  // eslint-disable-next-line @typescript-eslint/no-unused-expressions
  sortTick.value
  const mru = readMru()
  return [...emojis.value].sort((a, b) => {
    const ta = mru[a.name] || 0
    const tb = mru[b.name] || 0
    if (ta !== tb) return tb - ta
    return a.name < b.name ? -1 : 1
  })
})

function onPick(e: EmojiItem) {
  touchMru(e.name)
  sortTick.value++
  emit('pick', e)
  close()
}

function close() {
  emit('close')
}

watch(() => props.visible, (v) => {
  if (v && emojis.value.length === 0) loadEmojis()
})
</script>

<style scoped>
.emoji-panel-overlay {
  position: fixed;
  left: 0;
  right: 0;
  bottom: 0;
  z-index: 50;
}

.emoji-panel {
  background: #f7f7f7;
  border-top: 1px solid #e0e0e0;
  padding: 8px 12px 14px;
  max-height: 280px;
  display: flex;
  flex-direction: column;
}

.emoji-panel-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 4px 4px 8px;
}

.emoji-panel-title {
  font-size: 13px;
  color: #555;
  font-weight: 500;
}

.emoji-panel-close {
  width: 24px;
  height: 24px;
  border: none;
  background: rgba(0, 0, 0, 0.06);
  border-radius: 50%;
  font-size: 12px;
  color: #888;
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
}

.emoji-panel-loading,
.emoji-panel-empty {
  color: #999;
  font-size: 13px;
  text-align: center;
  padding: 24px 0;
  line-height: 1.6;
}
.emoji-panel-empty small {
  color: #bbb;
  font-size: 11px;
}

.emoji-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(56px, 1fr));
  gap: 8px;
  overflow-y: auto;
  padding: 4px 2px;
  max-height: 220px;
  -webkit-overflow-scrolling: touch;
}

.emoji-item {
  width: 56px;
  height: 56px;
  background: #fff;
  border: 1px solid #ececec;
  border-radius: 6px;
  padding: 4px;
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  overflow: hidden;
}
.emoji-item:active {
  background: #eef7ee;
  border-color: #07c160;
}

.emoji-img {
  max-width: 100%;
  max-height: 100%;
  object-fit: contain;
}

.slide-up-enter-active,
.slide-up-leave-active {
  transition: transform 0.2s ease, opacity 0.2s ease;
}
.slide-up-enter-from,
.slide-up-leave-to {
  transform: translateY(100%);
  opacity: 0;
}
</style>
