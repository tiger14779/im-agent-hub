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
          <!-- Users -->
          <div
            v-for="u in assignedUsers"
            :key="u.userId"
            class="user-list-item"
            @click="selectUser(u.userId, u.nickname, u.avatar)"
          >
            <div class="avatar">{{ (u.nickname || u.userId).charAt(0) }}</div>
            <div class="user-list-info">
              <span class="user-list-name">{{ u.nickname || u.userId }}</span>
              <span class="user-list-id">{{ u.userId }}</span>
            </div>
          </div>
          <!-- Groups -->
          <div
            v-for="g in groups"
            :key="g.groupId"
            class="user-list-item"
            @click="selectGroup(g.groupId, g.name, g.avatar)"
          >
            <div class="avatar group-avatar">
              <img v-if="g.avatar" :src="g.avatar" style="width:100%;height:100%;object-fit:cover;border-radius:inherit" />
              <span v-else>群</span>
            </div>
            <div class="user-list-info">
              <span class="user-list-name">{{ g.name }}</span>
              <span class="user-list-id">群聊</span>
            </div>
          </div>
          <div v-if="assignedUsers.length === 0 && groups.length === 0" class="empty-hint">
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
          :staff-avatar="activePeerIsGroup ? undefined : activePeerAvatar"
          :staff-name="activePeerIsGroup ? undefined : activePeerName"
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
import { chatWs } from '@/services/ws'
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
const staffNickname = ref('客服')
const assignedUsers = ref<{ userId: string; nickname: string; avatar: string }[]>([])
const groups = ref<{ groupId: string; name: string; avatar: string }[]>([])

const activePeer = ref('')
const activePeerName = ref('')
const activePeerAvatar = ref('')
const activePeerIsGroup = ref(false)
const loadingMore = ref(false)
const oldestSeq = ref(0)
let isSyncing = false // flag: true when reloading history after reconnect
let pendingHistoryPeer = '' // tracks which peer's history we are waiting for (race guard)

function parseContent(m: Message): Message {
  const msg = { ...m }
  try {
    const parsed = JSON.parse(m.content)
    if (m.contentType === 101) msg.textContent = parsed.text ?? parsed.content ?? m.content
    else if (m.contentType === 102) { const imgUrl = parsed.url ?? parsed.sourcePicture?.url ?? ''; msg.pictureContent = { sourcePicture: { url: imgUrl }, snapshotPicture: { url: imgUrl } } }
    else if (m.contentType === 103) msg.voiceContent = { sourceUrl: parsed.url, duration: parsed.duration }
    else if (m.contentType === 105) msg.fileContent = { sourceUrl: parsed.url, fileName: parsed.name, fileSize: parsed.size, fileType: parsed.type }
  } catch {
    if (m.contentType === 101) msg.textContent = m.content
  }
  return msg
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
      users: { userId: string; nickname: string }[]
    }>('/service/auth/login', { userId: id })

    myUserId.value = res.userId
    myToken.value = res.token
    staffNickname.value = res.nickname || '客服'
    assignedUsers.value = (res.users || []).map((u: { userId: string; nickname: string; avatar?: string }) => ({
      userId: u.userId,
      nickname: u.nickname,
      avatar: u.avatar || ''
    }))

    // Fetch groups this staff member belongs to
    try {
      const gRes = await request.get('/service/groups', {
        headers: {
          'Authorization': `Bearer ${res.token}`,
          'X-Service-UserID': res.userId
        }
      }) as { list: any[] }
      groups.value = (gRes?.list || []).map((g: any) => ({ groupId: g.id || g.groupId, name: g.name, avatar: g.avatar || '' }))
    } catch {
      groups.value = []
    }

    if (!res.token) {
      throw new Error('登录信息不完整')
    }

    // Setup callbacks
    chatWs.onNewMessage = (msg: Message) => {
      if (activePeer.value &&
          (msg.sendID === activePeer.value || msg.recvID === activePeer.value)) {
        chatStore.addMessage(msg)
      }
    }

    chatWs.onNewGroupMessage = (msg) => {
      if (activePeerIsGroup.value && activePeer.value === msg.groupId) {
        chatStore.addMessage(msg)
      }
    }

    chatWs.onAck = (ack) => {
      chatStore.updateMessageStatus(ack.clientMsgId, ack.status, ack.serverMsgId)
    }

    chatWs.onHistory = (data) => {
      // Discard stale responses that arrived after switching to a different peer
      if (data.peerUserId !== pendingHistoryPeer) return
      const parsed = (data.messages as unknown as Message[]).map(parseContent)
      if (isSyncing) {
        chatStore.mergeMessages(parsed)
        isSyncing = false
      } else {
        chatStore.loadHistory(parsed)
      }
      chatStore.hasMore = data.hasMore
      if (parsed.length > 0) {
        oldestSeq.value = Math.min(...parsed.map(m => (m as unknown as { seq: number }).seq || 0))
      }
      loadingMore.value = false
    }

    // Connect WebSocket
    await new Promise<void>((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error('WebSocket 连接超时')), 10000)
      chatWs.onConnected = () => {
        clearTimeout(timeout)
        resolve()
      }
      chatWs.connect(res.userId, res.token, 'staff')
    })

    // Sync missed messages on reconnect
    chatWs.onReconnected = () => {
      if (activePeer.value) {
        isSyncing = true
        const peerId = activePeerIsGroup.value ? 'group_' + activePeer.value : activePeer.value
        pendingHistoryPeer = peerId
        chatWs.loadHistory(peerId)
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

function selectUser(userId: string, nickname: string, avatar: string) {
  activePeer.value = userId
  activePeerName.value = nickname || userId
  activePeerAvatar.value = avatar || ''
  activePeerIsGroup.value = false
  isSyncing = false
  chatStore.clearMessages()
  oldestSeq.value = 0
  pendingHistoryPeer = userId
  chatWs.loadHistory(userId)
  chatWs.markRead(userId)
}

function goBack() {
  activePeer.value = ''
  activePeerName.value = ''
  activePeerAvatar.value = ''
  activePeerIsGroup.value = false
  chatStore.clearMessages()
}

function selectGroup(groupId: string, name: string, avatar = '') {
  activePeer.value = groupId
  activePeerName.value = name
  activePeerAvatar.value = avatar
  activePeerIsGroup.value = true
  isSyncing = false
  chatStore.clearMessages()
  oldestSeq.value = 0
  pendingHistoryPeer = 'group_' + groupId
  chatWs.loadHistory('group_' + groupId)
}

function onLoadMore() {
  if (loadingMore.value || !chatStore.hasMore) return
  loadingMore.value = true
  const peerId = activePeerIsGroup.value ? 'group_' + activePeer.value : activePeer.value
  chatWs.loadHistory(peerId, oldestSeq.value, 50)
}

function onSendText(text: string) {
  const peerId = activePeer.value
  if (activePeerIsGroup.value) {
    const clientMsgID = chatWs.sendGroupMessage(peerId, text)
    chatStore.addMessage({
      clientMsgID,
      sendID: myUserId.value,
      recvID: peerId,
      sessionType: 1,
      contentType: 101,
      content: JSON.stringify({ text }),
      textContent: text,
      sendTime: Date.now(),
      status: 1,
      isGroup: true
    })
    return
  }
  const clientMsgID = chatWs.sendTextMessage(peerId, text)
  chatStore.addMessage({
    clientMsgID,
    sendID: myUserId.value,
    recvID: peerId,
    sessionType: 1,
    contentType: 101,
    content: JSON.stringify({ text }),
    textContent: text,
    sendTime: Date.now(),
    status: 1
  })
}

async function onSendImage(file: File) {
  const peerId = activePeer.value
  const url = URL.createObjectURL(file)
  const tempMsgID = `tmp_${Date.now()}`
  chatStore.addMessage({
    clientMsgID: tempMsgID,
    sendID: myUserId.value,
    recvID: peerId,
    sessionType: 1,
    contentType: 102,
    content: '',
    pictureContent: { snapshotPicture: { url } },
    sendTime: Date.now(),
    status: 1
  })
  try {
    const realId = await chatWs.sendImageMessage(peerId, file)
    const msg = chatStore.messages.find(m => m.clientMsgID === tempMsgID)
    if (msg) msg.clientMsgID = realId
  } catch {
    chatStore.updateMessageStatus(tempMsgID, 3)
  }
}

async function onSendFile(file: File) {
  const peerId = activePeer.value
  const tempMsgID = `tmp_${Date.now()}`
  chatStore.addMessage({
    clientMsgID: tempMsgID,
    sendID: myUserId.value,
    recvID: peerId,
    sessionType: 1,
    contentType: 105,
    content: '',
    fileContent: { fileName: file.name, fileSize: file.size, fileType: file.type },
    sendTime: Date.now(),
    status: 1
  })
  try {
    const realId = await chatWs.sendFileMessage(peerId, file)
    const msg = chatStore.messages.find(m => m.clientMsgID === tempMsgID)
    if (msg) msg.clientMsgID = realId
  } catch {
    chatStore.updateMessageStatus(tempMsgID, 3)
  }
}

async function onSendVoice({ blob, duration }: { blob: Blob; duration: number }) {
  const peerId = activePeer.value
  const url = URL.createObjectURL(blob)
  const tempMsgID = `tmp_${Date.now()}`
  chatStore.addMessage({
    clientMsgID: tempMsgID,
    sendID: myUserId.value,
    recvID: peerId,
    sessionType: 1,
    contentType: 103,
    content: '',
    voiceContent: { sourceUrl: url, duration },
    sendTime: Date.now(),
    status: 1
  })
  try {
    const realId = await chatWs.sendVoiceMessage(peerId, blob, duration)
    const msg = chatStore.messages.find(m => m.clientMsgID === tempMsgID)
    if (msg) msg.clientMsgID = realId
  } catch {
    chatStore.updateMessageStatus(tempMsgID, 3)
  }
}

onMounted(init)
onUnmounted(() => {
  chatWs.disconnect()
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

.group-avatar {
  background: #5b8cff;
  font-size: 13px;
}
</style>
