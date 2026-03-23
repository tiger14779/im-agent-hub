<template>
  <div class="chat-container">
    <!-- Loading overlay -->
    <div v-if="state === 'loading'" class="chat-loading">
      <div class="spinner" />
      <span>正在连接...</span>
    </div>

    <!-- Error overlay -->
    <div v-else-if="state === 'error'" class="chat-error">
      <span style="font-size: 40px">😕</span>
      <p>{{ errorMsg }}</p>
      <button class="retry-btn" @click="init">重新连接</button>
    </div>

    <!-- Chat UI (always rendered so transitions work) -->
    <template v-if="state === 'ready'">
      <!-- Header -->
      <header class="chat-header">
        <button class="back-btn" @click="$router.back()">‹</button>
        <span class="title">{{ serviceUserName }}</span>
        <span class="more-btn">···</span>
      </header>

      <!-- Message list -->
      <MessageList
        :messages="chatStore.messages"
        :my-id="userStore.userId"
        :loading-more="loadingMore"
        :has-more="chatStore.hasMore"
        @load-more="onLoadMore"
      />

      <!-- Chat input -->
      <ChatInput
        @send-text="onSendText"
        @send-image="onSendImage"
        @send-file="onSendFile"
        @send-voice="onSendVoice"
      />
    </template>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted, onUnmounted } from 'vue'
import { useRoute } from 'vue-router'
import { useUserStore } from '@/stores/user'
import { useChatStore } from '@/stores/chat'
import { chatWs } from '@/services/ws'
import request from '@/utils/request'
import type { Message } from '@/types'
import MessageList from '@/components/MessageList.vue'
import ChatInput from '@/components/ChatInput.vue'

type PageState = 'loading' | 'ready' | 'error'

const route = useRoute()
const userStore = useUserStore()
const chatStore = useChatStore()

const state = ref<PageState>('loading')
const errorMsg = ref('')
const serviceUserName = ref('客服')
const loadingMore = ref(false)
const oldestSeq = ref(0)

async function init() {
  const targetId = (route.query.id as string | undefined)?.trim()
  if (!targetId) {
    errorMsg.value = '无效的用户 ID'
    state.value = 'error'
    return
  }

  state.value = 'loading'
  errorMsg.value = ''
  chatStore.clearMessages()

  try {
    // 1. Authenticate via backend
    const res = await request.post<unknown, {
      token: string
      userId: string
      nickname?: string
      serviceUserId?: string
    }>('/client/auth/login', { userId: targetId })

    userStore.login({
      userId: targetId,
      token: res.token,
      nickname: res.nickname,
      serviceUserId: res.serviceUserId
    })

    serviceUserName.value = '客服'
    const serviceId = userStore.serviceUserId || targetId

    if (!userStore.token) {
      throw new Error('登录令牌缺失，请重新进入聊天链接')
    }

    // 2. Setup WebSocket callbacks
    chatWs.onNewMessage = (msg: Message) => {
      chatStore.addMessage(msg)
    }

    chatWs.onAck = (ack) => {
      chatStore.updateMessageStatus(
        ack.clientMsgId,
        ack.status,
        ack.serverMsgId
      )
    }

    chatWs.onHistory = (data) => {
      const msgs = data.messages as unknown as Message[]
      // Parse content for each message
      const parsed = msgs.map(m => {
        const msg = { ...m }
        try {
          const parsed = JSON.parse(m.content)
          if (m.contentType === 101) msg.textContent = parsed.text ?? parsed.content ?? m.content
          else if (m.contentType === 102) msg.pictureContent = { sourcePicture: { url: parsed.url }, snapshotPicture: { url: parsed.url } }
          else if (m.contentType === 103) msg.voiceContent = { sourceUrl: parsed.url, duration: parsed.duration }
          else if (m.contentType === 105) msg.fileContent = { sourceUrl: parsed.url, fileName: parsed.name, fileSize: parsed.size, fileType: parsed.type }
        } catch {
          if (m.contentType === 101) msg.textContent = m.content
        }
        return msg
      })

      chatStore.loadHistory(parsed)
      chatStore.hasMore = data.hasMore
      if (parsed.length > 0) {
        oldestSeq.value = Math.min(...parsed.map(m => (m as unknown as { seq: number }).seq || 0))
      }
    }

    // 3. Connect WebSocket
    await new Promise<void>((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error('WebSocket 连接超时')), 10000)
      chatWs.onConnected = () => {
        clearTimeout(timeout)
        resolve()
      }
      chatWs.connect(userStore.userId, userStore.token, 'client')
    })

    state.value = 'ready'

    // 4. Load recent history
    chatWs.loadHistory(serviceId)
    chatWs.markRead(serviceId)
  } catch (err) {
    console.error('[Chat] init failed', err)
    errorMsg.value = (err as Error).message || '连接失败，请重试'
    state.value = 'error'
  }
}

function onLoadMore() {
  if (loadingMore.value || !chatStore.hasMore) return
  loadingMore.value = true
  const serviceId = userStore.serviceUserId || (route.query.id as string)
  chatWs.loadHistory(serviceId, oldestSeq.value, 50)
  // The onHistory callback will handle the result
  setTimeout(() => { loadingMore.value = false }, 1000)
}

function onSendText(text: string) {
  const serviceId = userStore.serviceUserId || (route.query.id as string)
  const clientMsgID = chatWs.sendTextMessage(serviceId, text)
  const tempMsg: Message = {
    clientMsgID,
    sendID: userStore.userId,
    recvID: serviceId,
    sessionType: 1,
    contentType: 101,
    content: JSON.stringify({ text }),
    textContent: text,
    sendTime: Date.now(),
    status: 1
  }
  chatStore.addMessage(tempMsg)
}

async function onSendImage(file: File) {
  const serviceId = userStore.serviceUserId || (route.query.id as string)
  const url = URL.createObjectURL(file)
  const tempMsgID = `tmp_${Date.now()}`
  const tempMsg: Message = {
    clientMsgID: tempMsgID,
    sendID: userStore.userId,
    recvID: serviceId,
    sessionType: 1,
    contentType: 102,
    content: '',
    pictureContent: { snapshotPicture: { url } },
    sendTime: Date.now(),
    status: 1
  }
  chatStore.addMessage(tempMsg)
  try {
    const realId = await chatWs.sendImageMessage(serviceId, file)
    // Update temp msg's clientMsgID to the real one for ACK matching
    const msg = chatStore.messages.find(m => m.clientMsgID === tempMsgID)
    if (msg) msg.clientMsgID = realId
  } catch (err) {
    chatStore.updateMessageStatus(tempMsgID, 3)
  }
}

async function onSendFile(file: File) {
  const serviceId = userStore.serviceUserId || (route.query.id as string)
  const tempMsgID = `tmp_${Date.now()}`
  const tempMsg: Message = {
    clientMsgID: tempMsgID,
    sendID: userStore.userId,
    recvID: serviceId,
    sessionType: 1,
    contentType: 105,
    content: '',
    fileContent: { fileName: file.name, fileSize: file.size, fileType: file.type },
    sendTime: Date.now(),
    status: 1
  }
  chatStore.addMessage(tempMsg)
  try {
    const realId = await chatWs.sendFileMessage(serviceId, file)
    const msg = chatStore.messages.find(m => m.clientMsgID === tempMsgID)
    if (msg) msg.clientMsgID = realId
  } catch (err) {
    chatStore.updateMessageStatus(tempMsgID, 3)
  }
}

async function onSendVoice({ blob, duration }: { blob: Blob; duration: number }) {
  const serviceId = userStore.serviceUserId || (route.query.id as string)
  const url = URL.createObjectURL(blob)
  const tempMsgID = `tmp_${Date.now()}`
  const tempMsg: Message = {
    clientMsgID: tempMsgID,
    sendID: userStore.userId,
    recvID: serviceId,
    sessionType: 1,
    contentType: 103,
    content: '',
    voiceContent: { sourceUrl: url, duration },
    sendTime: Date.now(),
    status: 1
  }
  chatStore.addMessage(tempMsg)
  try {
    const realId = await chatWs.sendVoiceMessage(serviceId, blob, duration)
    const msg = chatStore.messages.find(m => m.clientMsgID === tempMsgID)
    if (msg) msg.clientMsgID = realId
  } catch (err) {
    chatStore.updateMessageStatus(tempMsgID, 3)
  }
}

onMounted(init)
onUnmounted(() => {
  chatWs.disconnect()
})
</script>

<style scoped>
/* All layout styles are in chat.css; only local overrides here */
</style>
