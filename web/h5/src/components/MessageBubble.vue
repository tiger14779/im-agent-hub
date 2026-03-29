<template>
  <div class="message-item" :class="isSelf ? 'self' : 'other'">
    <!-- Avatar -->
    <div class="avatar">
      <img
        v-if="isSelf && myAvatar"
        :src="myAvatar"
      />
      <img
        v-else-if="!isSelf && staffAvatar"
        :src="staffAvatar"
      />
      <template v-else>
        {{ isSelf ? '我' : (staffName ? staffName.charAt(0) : '客') }}
      </template>
    </div>

    <!-- Bubble + status -->
    <div class="bubble-and-status" :class="{ self: isSelf }">
      <!-- Status indicator (sending / failed) -->
      <span
        v-if="isSelf && message.status !== 2"
        class="message-status"
        :class="{ failed: message.status === 3 }"
      >
        {{ message.status === 1 ? '发送中' : '!' }}
      </span>

      <!-- Arrow + bubble wrapper -->
      <div class="bubble-wrapper">
        <div class="bubble-arrow" />
        <div class="message-bubble" :class="isSelf ? 'self' : 'other'">
          <!-- Text message -->
          <span v-if="message.contentType === 101" class="bubble-text">
            {{ message.textContent ?? message.content }}
          </span>

          <!-- Image message -->
          <ImageMessage v-else-if="message.contentType === 102" :content="message.pictureContent ?? {}" />

          <!-- Voice message -->
          <VoiceMessage
            v-else-if="message.contentType === 103"
            :content="message.voiceContent ?? {}"
            :is-self="isSelf"
          />

          <!-- File message -->
          <FileMessage v-else-if="message.contentType === 105" :content="message.fileContent ?? {}" />

          <!-- Unknown type fallback -->
          <span v-else class="bubble-text">[不支持的消息类型]</span>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import type { Message } from '@/types'
import ImageMessage from './ImageMessage.vue'
import VoiceMessage from './VoiceMessage.vue'
import FileMessage from './FileMessage.vue'

defineProps<{
  message: Message
  isSelf: boolean
  staffAvatar?: string
  staffName?: string
  myAvatar?: string
}>()
</script>

<style scoped>
.bubble-and-status {
  display: flex;
  align-items: flex-end;
  gap: 4px;
  max-width: calc(100vw - 120px);
}

.bubble-and-status.self {
  flex-direction: row-reverse;
}

.bubble-text {
  font-size: 15px;
  line-height: 1.5;
  word-break: break-word;
  white-space: pre-wrap;
}
</style>
