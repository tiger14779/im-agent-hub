<template>
  <div class="chat-input-area">
    <!-- Voice / keyboard toggle -->
    <button class="voice-btn" @click="toggleVoiceMode">
      {{ voiceMode ? '⌨️' : '🎤' }}
    </button>

    <!-- Text textarea or hold-to-record button -->
    <template v-if="!voiceMode">
      <textarea
        ref="textareaEl"
        v-model="text"
        class="chat-textarea"
        placeholder="发消息…"
        rows="1"
        @input="autoResize"
        @keydown.enter.exact.prevent="onSendText"
      />
    </template>
    <template v-else>
      <div
        class="voice-record-btn"
        :class="{ recording: isRecording }"
        @touchstart.prevent="startRecord"
        @touchend.prevent="stopRecord"
        @touchcancel.prevent="cancelRecord"
        @mousedown.prevent="startRecord"
        @mouseup.prevent="stopRecord"
      >
        {{ isRecording ? '松开发送' : '按住说话' }}
      </div>
    </template>

    <!-- Emoji / attachment toggle -->
    <button class="attach-btn" @click="toggleAttach">➕</button>

    <!-- Send button (visible when text is non-empty) -->
    <button v-if="text.trim() && !voiceMode" class="send-btn" @click="onSendText">
      发送
    </button>

    <!-- Attachment popup -->
    <transition name="slide-up">
      <div v-if="showAttach" class="attach-popup">
        <button class="attach-close-btn" @click="showAttach = false">✕</button>
        <label class="attach-item">
          <div class="attach-item-icon">🖼️</div>
          <span>图片</span>
          <input
            type="file"
            accept="image/*"
            style="display: none"
            @change="onImageSelected"
          />
        </label>
        <label class="attach-item">
          <div class="attach-item-icon">📁</div>
          <span>文件</span>
          <input
            type="file"
            style="display: none"
            @change="onFileSelected"
          />
        </label>
        <button v-if="showCall" class="attach-item call-attach-item" @click="onCallClick">
          <div class="attach-item-icon">📞</div>
          <span>语音通话</span>
        </button>
      </div>
    </transition>
  </div>

  <!-- Recording overlay indicator -->
  <transition name="fade">
    <div v-if="isRecording" class="recording-overlay">
      <div class="recording-icon">🎙️</div>
      <p>正在录音…</p>
      <span class="recording-time">{{ recordSeconds }}s</span>
    </div>
  </transition>
</template>

<script setup lang="ts">
import { ref, onUnmounted } from 'vue'
import { AudioRecorder } from '@/utils/recorder'

const props = withDefaults(defineProps<{ showCall?: boolean }>(), { showCall: false })

const emit = defineEmits<{
  (e: 'send-text', text: string): void
  (e: 'send-image', file: File): void
  (e: 'send-file', file: File): void
  (e: 'send-voice', payload: { blob: Blob; duration: number }): void
  (e: 'start-call'): void
}>()

const text = ref('')
const voiceMode = ref(false)
const showAttach = ref(false)
const isRecording = ref(false)
const recordSeconds = ref(0)

const textareaEl = ref<HTMLTextAreaElement | null>(null)
const recorder = new AudioRecorder()
let recordTimer: ReturnType<typeof setInterval> | null = null

function toggleVoiceMode() {
  voiceMode.value = !voiceMode.value
  showAttach.value = false
}

function toggleAttach() {
  showAttach.value = !showAttach.value
}

function autoResize() {
  const el = textareaEl.value
  if (!el) return
  el.style.height = 'auto'
  el.style.height = `${Math.min(el.scrollHeight, 100)}px`
}

function onSendText() {
  const t = text.value.trim()
  if (!t) return
  emit('send-text', t)
  text.value = ''
  autoResize()
  showAttach.value = false
}

async function startRecord() {
  try {
    await recorder.start()
    isRecording.value = true
    recordSeconds.value = 0
    recordTimer = setInterval(() => { recordSeconds.value++ }, 1000)
  } catch (err) {
    alert('无法访问麦克风: ' + (err as Error).message)
  }
}

async function stopRecord() {
  if (!recorder.isRecording()) return
  if (recordTimer) { clearInterval(recordTimer); recordTimer = null }
  isRecording.value = false
  try {
    const { blob, duration } = await recorder.stop()
    if (duration < 1) return // Too short
    emit('send-voice', { blob, duration })
  } catch (err) {
    console.error('录音停止失败', err)
  }
}

function cancelRecord() {
  if (recordTimer) { clearInterval(recordTimer); recordTimer = null }
  recorder.cancel()
  isRecording.value = false
}

function onImageSelected(e: Event) {
  const file = (e.target as HTMLInputElement).files?.[0]
  if (file) emit('send-image', file)
  showAttach.value = false
  ;(e.target as HTMLInputElement).value = ''
}

function onFileSelected(e: Event) {
  const file = (e.target as HTMLInputElement).files?.[0]
  if (file) emit('send-file', file)
  showAttach.value = false
  ;(e.target as HTMLInputElement).value = ''
}

function onCallClick() {
  showAttach.value = false
  emit('start-call')
}

onUnmounted(() => {
  if (recordTimer) clearInterval(recordTimer)
  recorder.cancel()
})
</script>

<style scoped>
/* Voice call in attach popup */
.call-attach-item {
  background: none;
  border: none;
  padding: 0;
  cursor: pointer;
  font-size: inherit;
  font-family: inherit;
  color: inherit;
}
.call-attach-item:active .attach-item-icon {
  background: rgba(0, 0, 0, 0.08);
}
/* Voice call initiative button */
.call-initiative-btn {
  flex-shrink: 0;
  width: 36px;
  height: 36px;
  border: none;
  background: none;
  border-radius: 50%;
  font-size: 18px;
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  transition: background 0.15s;
}
.call-initiative-btn:active {
  background: rgba(0, 0, 0, 0.08);
}

/* Slide-up transition for attachment panel */
.slide-up-enter-active,
.slide-up-leave-active {
  transition: all 0.2s ease;
}

.slide-up-enter-from,
.slide-up-leave-to {
  opacity: 0;
  transform: translateY(100%);
}

/* Close button in attachment panel */
.attach-close-btn {
  position: absolute;
  top: 8px;
  right: 12px;
  width: 28px;
  height: 28px;
  border: none;
  background: rgba(0, 0, 0, 0.08);
  border-radius: 50%;
  font-size: 14px;
  color: var(--wechat-text-secondary, #999);
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
}

/* Recording overlay */
.recording-overlay {
  position: fixed;
  top: 50%;
  left: 50%;
  transform: translate(-50%, -50%);
  background: rgba(0, 0, 0, 0.72);
  border-radius: 12px;
  padding: 24px 32px;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 8px;
  z-index: 100;
  color: #fff;
}

.recording-icon {
  font-size: 40px;
}

.recording-time {
  font-size: 18px;
  font-weight: 600;
}

.fade-enter-active,
.fade-leave-active {
  transition: opacity 0.2s;
}

.fade-enter-from,
.fade-leave-to {
  opacity: 0;
}
</style>
