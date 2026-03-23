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

    <!-- Login form when no id in query -->
    <div v-else-if="state === 'login'" class="login-page">
      <div class="login-card">
        <div class="login-logo">🎧</div>
        <h1 class="login-title">客服工作台</h1>
        <p class="login-subtitle">请输入您的客服 ID</p>
        <div class="login-form">
          <input
            v-model="loginId"
            type="text"
            placeholder="客服 ID"
            class="login-input"
            @keyup.enter="doLogin"
          />
          <button class="login-btn" :disabled="!loginId.trim()" @click="doLogin">
            登录
          </button>
        </div>
      </div>
    </div>

    <!-- User list sidebar + chat -->
    <template v-if="state === 'ready'">
      <!-- If no active chat target, show user list -->
      <div v-if="!activePeer" class="user-list-page">
        <header class="chat-header">
          <span class="title">{{ staffNickname }} — 客服工作台</span>
        </header>
        <div class="user-list">
          <div
            v-for="u in assignedUsers"
            :key="u.userId"
            class="user-list-item"
            @click="selectUser(u.userId, u.nickname)"
          >
            <div class="avatar">{{ (u.nickname || u.userId).charAt(0) }}</div>
            <div class="user-list-info">
              <span class="user-list-name">{{ u.nickname || u.userId }}</span>
              <span class="user-list-id">{{ u.userId }}</span>
            </div>
          </div>
          <div v-if="assignedUsers.length === 0" class="empty-hint">
            暂无分配的用户
          </div>
        </div>
      </div>

      <!-- Active chat -->
      <template v-if="activePeer">
        <header class="chat-header">
          <button class="back-btn" @click="goBack">‹</button>
          <span class="title">{{ activePeerName }}</span>
          <span class="more-btn">···</span>
        </header>

        <MessageList
          :messages="chatStore.messages"
          :my-id="myUserId"
          :loading-more="loadingMore"
          :has-more="chatStore.hasMore"
          @load-more="onLoadMore"
        />

        <ChatInput
          @send-text="onSendText"
          @send-image="onSendImage"
          @send-file="onSendFile"
          @send-voice="onSendVoice"
        />
      </template>
    </template>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted, onUnmounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useChatStore } from '@/stores/chat'
import { openIMService } from '@/services/openim'
import request from '@/utils/request'
import type { Message } from '@/types'
import MessageList from '@/components/MessageList.vue'
import ChatInput from '@/components/ChatInput.vue'

type PageState = 'login' | 'loading' | 'ready' | 'error'

const route = useRoute()
const router = useRouter()
const chatStore = useChatStore()

const state = ref<PageState>('loading')
const errorMsg = ref('')

const loginId = ref('')
const myUserId = ref('')
const myToken = ref('')
const wsUrl = ref('')
const apiUrl = ref('')
const staffNickname = ref('客服')
const assignedUsers = ref<{ userId: string; nickname: string }[]>([])

const activePeer = ref('')
const activePeerName = ref('')
const currentConversationID = ref('')
const loadingMore = ref(false)

function parseMessage(raw: Record<string, unknown>): Message {
  const contentType = Number(raw.contentType ?? 101)
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
  const queryId = (route.query.id as string | undefined)?.trim()
  if (!queryId) {
    state.value = 'login'
    return
  }

  loginId.value = queryId
  await doLogin()
}

async function doLogin() {
  const id = loginId.value.trim()
  if (!id) return

  state.value = 'loading'
  errorMsg.value = ''

  try {
    const res = await request.post<unknown, {
      token: string
      userId: string
      nickname: string
      wsUrl: string
      apiUrl: string
      users: { userId: string; nickname: string }[]
    }>('/service/auth/login', { userId: id })

    myUserId.value = res.userId
    myToken.value = res.token
    wsUrl.value = res.wsUrl
    apiUrl.value = res.apiUrl
    staffNickname.value = res.nickname || '客服'
    assignedUsers.value = res.users || []

    if (!res.token || !res.wsUrl || !res.apiUrl) {
      throw new Error('登录信息不完整，请检查后端配置')
    }

    await openIMService.init(res.wsUrl, res.apiUrl)
    await openIMService.login(res.userId, res.token)
    await openIMService.waitForConnection()

    openIMService.onNewMessage = (raw) => {
      const msg = parseMessage(raw as Record<string, unknown>)
      // Only add to current chat if it belongs to active conversation
      if (activePeer.value &&
          (msg.sendID === activePeer.value || msg.recvID === activePeer.value)) {
        chatStore.addMessage(msg)
      }
    }

    // Update URL to include id for refresh
    if (!route.query.id) {
      router.replace({ query: { id } })
    }

    state.value = 'ready'
  } catch (err) {
    console.error('[ServiceChat] login failed', err)
    errorMsg.value = (err as Error).message || '登录失败'
    state.value = 'error'
  }
}

async function selectUser(userId: string, nickname: string) {
  activePeer.value = userId
  activePeerName.value = nickname || userId
  chatStore.clearMessages()
  currentConversationID.value = ''

  try {
    const conversationID = await openIMService.getConversationID(userId)
    currentConversationID.value = conversationID
    if (conversationID) {
      const history = await openIMService.getHistoryMessages(conversationID)
      const parsed = (history as Record<string, unknown>[]).map(parseMessage)
      chatStore.loadHistory(parsed)
      if (parsed.length < 20) {
        chatStore.hasMore = false
      }
    }
  } catch (err) {
    console.error('[ServiceChat] load history failed', err)
  }
}

function goBack() {
  activePeer.value = ''
  activePeerName.value = ''
  currentConversationID.value = ''
  chatStore.clearMessages()
}

async function onLoadMore() {
  if (loadingMore.value || !chatStore.hasMore || !currentConversationID.value) return
  loadingMore.value = true
  try {
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
    console.warn('[ServiceChat] load more history failed', err)
  } finally {
    loadingMore.value = false
  }
}

async function onSendText(text: string) {
  const peerId = activePeer.value
  const tempMsg: Message = {
    clientMsgID: `tmp_${Date.now()}`,
    sendID: myUserId.value,
    recvID: peerId,
    sessionType: 1,
    contentType: 101,
    content: JSON.stringify({ content: text }),
    textContent: text,
    sendTime: Date.now(),
    status: 1
  }
  chatStore.addMessage(tempMsg)
  try {
    const sent = await openIMService.sendTextMessage(peerId, text)
    chatStore.updateMessageStatus(tempMsg.clientMsgID, 2, (sent as { serverMsgID?: string })?.serverMsgID)
  } catch (err) {
    console.error('[ServiceChat] send text failed', err)
    chatStore.updateMessageStatus(tempMsg.clientMsgID, 3)
  }
}

async function onSendImage(file: File) {
  const peerId = activePeer.value
  const url = URL.createObjectURL(file)
  const tempMsg: Message = {
    clientMsgID: `tmp_${Date.now()}`,
    sendID: myUserId.value,
    recvID: peerId,
    sessionType: 1,
    contentType: 102,
    content: '',
    pictureContent: { snapshotPicture: { url } },
    sendTime: Date.now(),
    status: 1
  }
  chatStore.addMessage(tempMsg)
  try {
    await openIMService.sendImageMessage(peerId, file)
    chatStore.updateMessageStatus(tempMsg.clientMsgID, 2)
  } catch (err) {
    console.error('[ServiceChat] send image failed', err)
    chatStore.updateMessageStatus(tempMsg.clientMsgID, 3)
  }
}

async function onSendFile(file: File) {
  const peerId = activePeer.value
  const tempMsg: Message = {
    clientMsgID: `tmp_${Date.now()}`,
    sendID: myUserId.value,
    recvID: peerId,
    sessionType: 1,
    contentType: 105,
    content: '',
    fileContent: { fileName: file.name, fileSize: file.size, fileType: file.type },
    sendTime: Date.now(),
    status: 1
  }
  chatStore.addMessage(tempMsg)
  try {
    await openIMService.sendFileMessage(peerId, file)
    chatStore.updateMessageStatus(tempMsg.clientMsgID, 2)
  } catch (err) {
    console.error('[ServiceChat] send file failed', err)
    chatStore.updateMessageStatus(tempMsg.clientMsgID, 3)
  }
}

async function onSendVoice({ blob, duration }: { blob: Blob; duration: number }) {
  const peerId = activePeer.value
  const url = URL.createObjectURL(blob)
  const tempMsg: Message = {
    clientMsgID: `tmp_${Date.now()}`,
    sendID: myUserId.value,
    recvID: peerId,
    sessionType: 1,
    contentType: 103,
    content: '',
    voiceContent: { sourceUrl: url, duration },
    sendTime: Date.now(),
    status: 1
  }
  chatStore.addMessage(tempMsg)
  try {
    await openIMService.sendVoiceMessage(peerId, blob, duration)
    chatStore.updateMessageStatus(tempMsg.clientMsgID, 2)
  } catch (err) {
    console.error('[ServiceChat] send voice failed', err)
    chatStore.updateMessageStatus(tempMsg.clientMsgID, 3)
  }
}

onMounted(init)
onUnmounted(() => {
  openIMService.onNewMessage = () => {}
})
</script>

<style scoped>
.user-list-page {
  display: flex;
  flex-direction: column;
  height: 100%;
  background: var(--wechat-bg, #ededed);
}

.user-list {
  flex: 1;
  overflow-y: auto;
  padding: 0;
}

.user-list-item {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 14px 16px;
  background: #fff;
  border-bottom: 1px solid var(--wechat-border, #e5e5e5);
  cursor: pointer;
  transition: background 0.15s;
}

.user-list-item:active {
  background: #d9d9d9;
}

.user-list-info {
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.user-list-name {
  font-size: 15px;
  color: var(--wechat-text, #1a1a1a);
  font-weight: 500;
}

.user-list-id {
  font-size: 12px;
  color: var(--wechat-text-secondary, #999);
}

.empty-hint {
  text-align: center;
  padding: 60px 20px;
  color: var(--wechat-text-secondary, #999);
  font-size: 14px;
}

.login-page {
  width: 100%;
  height: 100%;
  background: var(--wechat-bg, #ededed);
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 24px;
}

.login-card {
  width: 100%;
  max-width: 360px;
  background: #fff;
  border-radius: 12px;
  padding: 32px 24px;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 12px;
  box-shadow: 0 2px 12px rgba(0, 0, 0, 0.08);
}

.login-logo { font-size: 48px; }
.login-title { font-size: 20px; font-weight: 600; color: var(--wechat-text, #1a1a1a); }
.login-subtitle { font-size: 13px; color: var(--wechat-text-secondary, #999); }

.login-form {
  width: 100%;
  display: flex;
  flex-direction: column;
  gap: 12px;
  margin-top: 8px;
}

.login-input {
  width: 100%;
  height: 44px;
  border: 1px solid var(--wechat-border, #e5e5e5);
  border-radius: 6px;
  padding: 0 14px;
  font-size: 15px;
  background: #fafafa;
}

.login-btn {
  width: 100%;
  height: 44px;
  background: var(--wechat-green, #07c160);
  border: none;
  border-radius: 6px;
  font-size: 16px;
  font-weight: 500;
  color: #fff;
  cursor: pointer;
}

.login-btn:disabled { opacity: 0.5; }
</style>
