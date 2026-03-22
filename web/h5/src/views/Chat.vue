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
import { openIMService } from '@/services/openim'
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

/** Parse a raw SDK message into our Message type */
function parseMessage(raw: Record<string, unknown>): Message {
  const contentType = Number(raw.contentType ?? 101)
  const content = (raw.content as string) ?? ''
  const msg: Message = {
    clientMsgID: (raw.clientMsgID as string) ?? String(Date.now()),
    serverMsgID: raw.serverMsgID as string | undefined,
    sendID: (raw.sendID as string) ?? '',
    recvID: (raw.recvID as string) ?? '',
    sessionType: Number(raw.sessionType ?? 1),
    contentType,
    content,
    sendTime: Number(raw.sendTime ?? Date.now()),
    status: Number(raw.status ?? 2)
  }

  try {
    const parsed: Record<string, unknown> = typeof content === 'string' ? JSON.parse(content) : content
    if (contentType === 101) msg.textContent = parsed.content as string ?? content
    else if (contentType === 102) msg.pictureContent = parsed as Message['pictureContent']
    else if (contentType === 103) msg.voiceContent = parsed as Message['voiceContent']
    else if (contentType === 105) msg.fileContent = parsed as Message['fileContent']
  } catch {
    msg.textContent = content
  }

  return msg
}

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
    userStore.loadFromStorage()
    if (!userStore.isLoggedIn) {
      const res = await request.post<unknown, {
        token: string
        wsUrl?: string
        apiUrl?: string
        serviceUserId?: string
        serviceUserName?: string
      }>('/client/auth/login', { userId: targetId })

      userStore.login({
        userId: targetId,
        token: res.token,
        serviceUserId: res.serviceUserId,
        wsUrl: res.wsUrl,
        apiUrl: res.apiUrl
      })

      serviceUserName.value = res.serviceUserName ?? '客服'
    }

    const wsUrl = userStore.wsUrl || 'ws://localhost:10001'
    const apiUrl = userStore.apiUrl || 'http://localhost:10002'
    const serviceId = userStore.serviceUserId || targetId

    // 2. Initialise & login to OpenIM SDK
    await openIMService.init(wsUrl, apiUrl)
    await openIMService.login(userStore.userId, userStore.token)

    // 3. Listen for incoming messages
    openIMService.onNewMessage = (raw) => {
      const msg = parseMessage(raw as Record<string, unknown>)
      chatStore.addMessage(msg)
    }

    // 4. Load recent history
    const history = await openIMService.getHistoryMessages(serviceId)
    const parsed = (history as Record<string, unknown>[]).map(parseMessage)
    chatStore.loadHistory(parsed)

    state.value = 'ready'
  } catch (err) {
    console.error('[Chat] init failed', err)
    errorMsg.value = (err as Error).message || '连接失败，请重试'
    state.value = 'error'
  }
}

async function onSendText(text: string) {
  const serviceId = userStore.serviceUserId || (route.query.id as string)
  const tempMsg: Message = {
    clientMsgID: `tmp_${Date.now()}`,
    sendID: userStore.userId,
    recvID: serviceId,
    sessionType: 1,
    contentType: 101,
    content: JSON.stringify({ content: text }),
    textContent: text,
    sendTime: Date.now(),
    status: 1
  }
  chatStore.addMessage(tempMsg)

  try {
    const sent = await openIMService.sendTextMessage(serviceId, text)
    chatStore.updateMessageStatus(tempMsg.clientMsgID, 2, (sent as { serverMsgID?: string })?.serverMsgID)
  } catch {
    chatStore.updateMessageStatus(tempMsg.clientMsgID, 3)
  }
}

async function onSendImage(file: File) {
  const serviceId = userStore.serviceUserId || (route.query.id as string)
  const url = URL.createObjectURL(file)
  const tempMsg: Message = {
    clientMsgID: `tmp_${Date.now()}`,
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
    await openIMService.sendImageMessage(serviceId, file)
    chatStore.updateMessageStatus(tempMsg.clientMsgID, 2)
  } catch {
    chatStore.updateMessageStatus(tempMsg.clientMsgID, 3)
  }
}

async function onSendFile(file: File) {
  const serviceId = userStore.serviceUserId || (route.query.id as string)
  const tempMsg: Message = {
    clientMsgID: `tmp_${Date.now()}`,
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
    await openIMService.sendFileMessage(serviceId, file)
    chatStore.updateMessageStatus(tempMsg.clientMsgID, 2)
  } catch {
    chatStore.updateMessageStatus(tempMsg.clientMsgID, 3)
  }
}

async function onSendVoice({ blob, duration }: { blob: Blob; duration: number }) {
  const serviceId = userStore.serviceUserId || (route.query.id as string)
  const url = URL.createObjectURL(blob)
  const tempMsg: Message = {
    clientMsgID: `tmp_${Date.now()}`,
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
    await openIMService.sendVoiceMessage(serviceId, blob, duration)
    chatStore.updateMessageStatus(tempMsg.clientMsgID, 2)
  } catch {
    chatStore.updateMessageStatus(tempMsg.clientMsgID, 3)
  }
}

onMounted(init)
onUnmounted(() => {
  openIMService.onNewMessage = () => {}
})
</script>

<style scoped>
/* All layout styles are in chat.css; only local overrides here */
</style>
