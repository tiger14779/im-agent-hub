<template>
  <div ref="listEl" class="chat-messages" @scroll="onScroll">
    <template v-for="(item, index) in messages" :key="item.clientMsgID">
      <!-- Time separator: show if gap > 5 min since previous message -->
      <div
        v-if="shouldShowTime(item, messages[index - 1])"
        class="message-time"
      >
        {{ formatTime(item.sendTime) }}
      </div>

      <MessageBubble :message="item" :is-self="item.sendID === myId" />
    </template>
  </div>
</template>

<script setup lang="ts">
import { ref, watch, nextTick } from 'vue'
import type { Message } from '@/types'
import MessageBubble from './MessageBubble.vue'

const props = defineProps<{
  messages: Message[]
  myId: string
}>()

const listEl = ref<HTMLElement | null>(null)
// Whether user has scrolled up to read old messages
let userScrolled = false

function onScroll() {
  if (!listEl.value) return
  const { scrollTop, scrollHeight, clientHeight } = listEl.value
  userScrolled = scrollHeight - scrollTop - clientHeight > 80
}

function scrollToBottom() {
  nextTick(() => {
    if (listEl.value && !userScrolled) {
      listEl.value.scrollTop = listEl.value.scrollHeight
    }
  })
}

watch(() => props.messages.length, scrollToBottom)

// 5-minute threshold for showing a time separator
const TIME_GAP_MS = 5 * 60 * 1000

function shouldShowTime(msg: Message, prev?: Message): boolean {
  if (!prev) return true
  return msg.sendTime - prev.sendTime > TIME_GAP_MS
}

function formatTime(ts: number): string {
  const d = new Date(ts)
  const now = new Date()
  const isToday =
    d.getDate() === now.getDate() &&
    d.getMonth() === now.getMonth() &&
    d.getFullYear() === now.getFullYear()

  const hh = String(d.getHours()).padStart(2, '0')
  const mm = String(d.getMinutes()).padStart(2, '0')

  if (isToday) return `${hh}:${mm}`

  const month = d.getMonth() + 1
  const day = d.getDate()
  return `${month}月${day}日 ${hh}:${mm}`
}
</script>
