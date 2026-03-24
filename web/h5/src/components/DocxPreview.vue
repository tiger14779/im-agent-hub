<template>
  <Teleport to="body">
    <div v-if="visible" class="docx-overlay" @click.self="close">
      <div class="docx-modal">
        <div class="docx-header">
          <span class="docx-title">{{ fileName }}</span>
          <div class="docx-actions">
            <button class="docx-zoom-btn" title="缩小" @click="zoomOut">−</button>
            <span class="docx-zoom-label">{{ Math.round(scale * 100) }}%</span>
            <button class="docx-zoom-btn" title="放大" @click="zoomIn">+</button>
            <button class="docx-zoom-btn" title="适合宽度" @click="zoomFit">⤢</button>
            <a :href="sourceUrl" class="docx-download-btn" title="下载">↓</a>
            <button class="docx-close-btn" @click="close">✕</button>
          </div>
        </div>
        <div v-if="loading" class="docx-loading">加载中...</div>
        <div v-if="error" class="docx-error">{{ error }}</div>
        <div ref="scrollRef" class="docx-body">
          <div ref="containerRef" class="docx-content-wrapper" :style="{ transform: `scale(${scale})`, transformOrigin: 'top center' }"></div>
        </div>
      </div>
    </div>
  </Teleport>
</template>

<script setup lang="ts">
import { ref, watch, nextTick, onUnmounted } from 'vue'
import { renderAsync } from 'docx-preview'

const props = defineProps<{
  visible: boolean
  sourceUrl: string
  fileName: string
}>()

const emit = defineEmits<{ (e: 'close'): void }>()

const containerRef = ref<HTMLDivElement>()
const scrollRef = ref<HTMLDivElement>()
const loading = ref(false)
const error = ref('')
const scale = ref(1)
const docRendered = ref(false)
const historyPushed = ref(false)

function close() {
  // If we pushed a history entry, go back to remove it
  if (historyPushed.value) {
    historyPushed.value = false
    window.history.back()
  }
  emit('close')
}

// Handle browser back button (Android)
function onPopState(e: PopStateEvent) {
  if (props.visible) {
    historyPushed.value = false
    emit('close')
  }
}

window.addEventListener('popstate', onPopState)

onUnmounted(() => {
  window.removeEventListener('popstate', onPopState)
  if (scrollRef.value) {
    scrollRef.value.removeEventListener('touchstart', onTouchStart)
    scrollRef.value.removeEventListener('touchmove', onTouchMove)
    scrollRef.value.removeEventListener('touchend', onTouchEnd)
  }
})

function zoomIn() {
  scale.value = Math.min(scale.value + 0.15, 3)
}

function zoomOut() {
  scale.value = Math.max(scale.value - 0.15, 0.3)
}

function zoomFit() {
  if (!scrollRef.value || !containerRef.value) return
  // Find the rendered docx-wrapper page width
  const wrapper = containerRef.value.querySelector('.docx-wrapper > section, .docx-wrapper') as HTMLElement
  if (!wrapper) return
  const pageWidth = wrapper.scrollWidth || wrapper.offsetWidth
  const viewWidth = scrollRef.value.clientWidth - 16 // small padding
  if (pageWidth > 0) {
    scale.value = Math.min(viewWidth / pageWidth, 1.5)
  }
}

function autoFitMobile() {
  // Auto-fit on mobile (screen width < 768px)
  if (window.innerWidth < 768) {
    nextTick(() => {
      setTimeout(zoomFit, 100) // wait for docx-preview DOM render
    })
  }
}

watch(() => props.visible, async (val) => {
  if (!val) {
    docRendered.value = false
    scale.value = 1
    // Remove history entry when closing
    if (historyPushed.value) {
      historyPushed.value = false
      // Avoid double-pop if already navigated back
    }
    return
  }

  // Push a history state so Android back button closes the preview instead of leaving the page
  window.history.pushState({ docxPreview: true }, '')
  historyPushed.value = true

  error.value = ''
  loading.value = true

  await nextTick()

  try {
    const resp = await fetch(props.sourceUrl)
    if (!resp.ok) throw new Error(`HTTP ${resp.status}`)
    const blob = await resp.blob()

    if (containerRef.value) {
      containerRef.value.innerHTML = ''
      await renderAsync(blob, containerRef.value, undefined, {
        className: 'docx-preview-content',
        inWrapper: true,
        ignoreWidth: false,
        ignoreHeight: false,
        ignoreFonts: false,
        breakPages: true,
      })
      docRendered.value = true
      autoFitMobile()
    }
  } catch (e: any) {
    error.value = '文档预览失败: ' + (e.message || e)
  } finally {
    loading.value = false
  }
})

// Pinch-to-zoom on touch devices
let lastPinchDist = 0

function onTouchStart(e: TouchEvent) {
  if (e.touches.length === 2) {
    lastPinchDist = Math.hypot(
      e.touches[0].clientX - e.touches[1].clientX,
      e.touches[0].clientY - e.touches[1].clientY
    )
  }
}

function onTouchMove(e: TouchEvent) {
  if (e.touches.length === 2) {
    const dist = Math.hypot(
      e.touches[0].clientX - e.touches[1].clientX,
      e.touches[0].clientY - e.touches[1].clientY
    )
    if (lastPinchDist > 0) {
      const delta = (dist - lastPinchDist) * 0.005
      scale.value = Math.min(Math.max(scale.value + delta, 0.3), 3)
    }
    lastPinchDist = dist
    e.preventDefault()
  }
}

function onTouchEnd() {
  lastPinchDist = 0
}

watch(scrollRef, (el) => {
  if (el) {
    el.addEventListener('touchstart', onTouchStart, { passive: true })
    el.addEventListener('touchmove', onTouchMove, { passive: false })
    el.addEventListener('touchend', onTouchEnd, { passive: true })
  }
})
</script>

<style scoped>
.docx-overlay {
  position: fixed;
  inset: 0;
  z-index: 9999;
  background: rgba(0, 0, 0, 0.55);
  display: flex;
  justify-content: center;
  align-items: center;
}

.docx-modal {
  background: #fff;
  border-radius: 8px;
  width: 90vw;
  max-width: 900px;
  height: 85vh;
  display: flex;
  flex-direction: column;
  box-shadow: 0 4px 24px rgba(0, 0, 0, 0.3);
}

/* Mobile: full-screen modal */
@media (max-width: 768px) {
  .docx-modal {
    width: 100vw;
    height: 100vh;
    max-width: none;
    border-radius: 0;
  }
}

.docx-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 10px 12px;
  border-bottom: 1px solid #e8e8e8;
  flex-shrink: 0;
  gap: 6px;
}

.docx-title {
  font-size: 14px;
  font-weight: 500;
  color: #333;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  flex: 1;
  min-width: 0;
}

.docx-actions {
  display: flex;
  gap: 4px;
  align-items: center;
  flex-shrink: 0;
}

.docx-zoom-btn {
  width: 28px;
  height: 28px;
  font-size: 16px;
  border: 1px solid #ddd;
  background: #fafafa;
  border-radius: 4px;
  cursor: pointer;
  color: #555;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 0;
}

.docx-zoom-btn:hover {
  background: #eee;
}

.docx-zoom-btn:active {
  background: #ddd;
}

.docx-zoom-label {
  font-size: 12px;
  color: #666;
  min-width: 36px;
  text-align: center;
  user-select: none;
}

.docx-download-btn {
  font-size: 18px;
  text-decoration: none;
  color: #555;
  padding: 4px 6px;
  border-radius: 4px;
}

.docx-download-btn:hover {
  background: #f0f0f0;
}

.docx-close-btn {
  font-size: 16px;
  border: none;
  background: none;
  cursor: pointer;
  color: #999;
  padding: 4px 6px;
  border-radius: 4px;
}

.docx-close-btn:hover {
  background: #f0f0f0;
  color: #333;
}

.docx-loading,
.docx-error {
  padding: 20px;
  text-align: center;
  color: #888;
  font-size: 14px;
}

.docx-error {
  color: #e55;
}

.docx-body {
  flex: 1;
  overflow: auto;
  padding: 0;
  -webkit-overflow-scrolling: touch;
  touch-action: pan-x pan-y;
}

.docx-content-wrapper {
  width: fit-content;
  margin: 0 auto;
}
</style>

<style>
/* docx-preview renders into the container — global styles needed */
.docx-preview-content {
  padding: 10px;
}

.docx-preview-content .docx-wrapper {
  background: #fff;
}

/* On mobile, remove page shadow/margin for cleaner look */
@media (max-width: 768px) {
  .docx-preview-content {
    padding: 4px;
  }

  .docx-preview-content .docx-wrapper > section {
    box-shadow: none !important;
    margin: 0 auto !important;
    padding: 10px !important;
  }
}
</style>
