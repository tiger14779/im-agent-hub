<template>
  <div class="voice-message" :class="{ self: isSelf, playing }" @click="togglePlay">
    <span class="voice-icon">🔊</span>
    <span class="voice-duration">{{ content.duration ?? 0 }}''</span>
    <!-- Animated bars when playing -->
    <span v-if="playing" class="voice-bars">
      <span /><span /><span />
    </span>
  </div>
</template>

<script setup lang="ts">
import { ref } from 'vue'
import type { VoiceContent } from '@/types'

const props = defineProps<{
  content: VoiceContent
  isSelf: boolean
}>()

const playing = ref(false)
let audio: HTMLAudioElement | null = null

function togglePlay() {
  const url = props.content.sourceUrl
  if (!url) return

  if (playing.value && audio) {
    audio.pause()
    audio.currentTime = 0
    playing.value = false
    return
  }

  audio = new Audio(url)
  audio.onended = () => { playing.value = false }
  audio.onerror = () => { playing.value = false }
  audio.play().catch(() => { playing.value = false })
  playing.value = true
}
</script>

<style scoped>
.voice-message {
  display: flex;
  align-items: center;
  gap: 6px;
  cursor: pointer;
  min-width: 60px;
  padding: 2px 0;
}

.voice-icon {
  font-size: 18px;
}

.voice-duration {
  font-size: 14px;
  color: inherit;
}

/* Animated bars */
.voice-bars {
  display: flex;
  align-items: flex-end;
  gap: 2px;
  height: 14px;
}

.voice-bars span {
  width: 3px;
  background: currentColor;
  border-radius: 2px;
  animation: bar-bounce 0.6s ease-in-out infinite alternate;
}

.voice-bars span:nth-child(2) { animation-delay: 0.2s; }
.voice-bars span:nth-child(3) { animation-delay: 0.4s; }

@keyframes bar-bounce {
  from { height: 4px; }
  to   { height: 14px; }
}
</style>
