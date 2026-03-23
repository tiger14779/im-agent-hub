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
const currentConversationID = ref('')
const loadingMore = ref(false)

/** Parse a raw SDK message into our Message type */
function parseMessage(raw: Record<string, unknown>): Message {
  const contentType = Number(raw.contentType ?? 101)
  // content may arrive as a pre-parsed object or as a JSON string
  const rawContent = raw.content
  const content =
    typeof rawContent === 'string'
      ? rawContent
      : rawContent != null
        ? JSON.stringify(rawContent)
        : ''
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

  // SDK returns rich fields like textElem, pictureElem, etc.
  const textElem = raw.textElem as Record<string, unknown> | undefined
  const pictureElem = raw.pictureElem as Record<string, unknown> | undefined
  const soundElem = raw.soundElem as Record<string, unknown> | undefined
  const fileElem = raw.fileElem as Record<string, unknown> | undefined

  if (contentType === 101) {
    // Priority: textElem.content > parsed content JSON > raw content string
    if (textElem && typeof textElem.content === 'string') {
      msg.textContent = textElem.content
    } else {
      try {
        const parsed = typeof content === 'string' ? JSON.parse(content) : content
        msg.textContent = (parsed as Record<string, unknown>).content as string || content
      } catch {
        msg.textContent = content
      }
    }
  } else if (contentType === 102) {
    msg.pictureContent = (pictureElem as Message['pictureContent']) ?? tryParseJSON(content)
  } else if (contentType === 103) {
    msg.voiceContent = (soundElem as Message['voiceContent']) ?? tryParseJSON(content)
  } else if (contentType === 105) {
    msg.fileContent = (fileElem as Message['fileContent']) ?? tryParseJSON(content)
  }

  return msg
}

function tryParseJSON(s: string): Record<string, unknown> | undefined {
  try { return JSON.parse(s) } catch { return undefined }
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
    // 1. Authenticate via backend (always refresh to avoid stale local cache)
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

    const wsUrl = userStore.wsUrl
    const apiUrl = userStore.apiUrl
    const serviceId = userStore.serviceUserId || targetId

    if (!userStore.token) {
      throw new Error('登录令牌缺失，请重新进入聊天链接')
    }
    if (!wsUrl || !apiUrl) {
      throw new Error('OpenIM 连接地址缺失，请检查后端登录接口返回')
    }

    // 2. Initialise & login to OpenIM SDK
    await openIMService.init(wsUrl, apiUrl)
    await openIMService.login(userStore.userId, userStore.token)

    // 3. Listen for incoming messages
    openIMService.onNewMessage = (raw) => {
      const msg = parseMessage(raw as Record<string, unknown>)
      chatStore.addMessage(msg)
    }

    // Wait for SDK connection to be fully established
    await openIMService.waitForConnection()

    state.value = 'ready'

    // 4. Load recent history (non-blocking — don't let failures prevent chatting)
    try {
      const conversationID = await openIMService.getConversationID(serviceId)
      currentConversationID.value = conversationID
      if (conversationID) {
        const history = await openIMService.getHistoryMessages(conversationID)
        const parsed = (history as Record<string, unknown>[]).map(parseMessage)
        chatStore.loadHistory(parsed)
        if (parsed.length < 20) {
          chatStore.hasMore = false
        }
      }
    } catch (histErr) {
      console.warn('[Chat] load history failed (non-fatal)', histErr)
    }
  } catch (err) {
    console.error('[Chat] init failed', err)
    errorMsg.value = (err as Error).message || '连接失败，请重试'
    state.value = 'error'
  }
}

async function onLoadMore() {
  if (loadingMore.value || !chatStore.hasMore || !currentConversationID.value) return
  loadingMore.value = true
  try {
    // Use the oldest message's clientMsgID as the cursor
    const oldest = chatStore.messages[0]
    const startMsgID = oldest?.clientMsgID ?? ''
    const history = await openIMService.getHistoryMessages(
      currentConversationID.value,
      startMsgID,
      20
    )
    const parsed = (history as Record<string, unknown>[]).map(parseMessage)
    if (parsed.length === 0) {
      chatStore.hasMore = false
    } else {
      chatStore.loadHistory(parsed)
      if (parsed.length < 20) {
        chatStore.hasMore = false
      }
    }
  } catch (err) {
    console.warn('[Chat] load more history failed', err)
  } finally {
    loadingMore.value = false
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
  } catch (err) {
    console.error('[Chat] send text failed', { serviceId, err })
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
  } catch (err) {
    console.error('[Chat] send image failed', { serviceId, err })
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
  } catch (err) {
    console.error('[Chat] send file failed', { serviceId, err })
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
  } catch (err) {
    console.error('[Chat] send voice failed', { serviceId, err })
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
