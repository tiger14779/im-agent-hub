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
      <!-- Lottery result -->
      <LotteryResult />

      <!-- Header -->
      <header class="chat-header">
        <button class="back-btn" @click="onBackClick">‹</button>
        <span class="title">{{ serviceUserName }}</span>
        <span class="more-btn">···</span>
      </header>

      <!-- Message list -->
      <MessageList
        :messages="chatStore.messages"
        :my-id="userStore.userId"
        :loading-more="loadingMore"
        :has-more="chatStore.hasMore"
        :staff-avatar="userStore.serviceAvatar"
        :staff-name="userStore.serviceNickname"
        :my-avatar="userStore.avatar"
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

    <!-- Back confirm dialog -->
    <teleport to="body">
      <transition name="fade">
        <div v-if="showBackConfirm" class="back-confirm-mask" @click.self="cancelBack">
          <div class="back-confirm-dialog">
            <p class="back-confirm-text">确定要离开当前聊天吗？</p>
            <div class="back-confirm-btns">
              <button class="back-confirm-cancel" @click="cancelBack">取消</button>
              <button class="back-confirm-ok" @click="confirmBack">离开</button>
            </div>
          </div>
        </div>
      </transition>
    </teleport>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted, onUnmounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useUserStore } from '@/stores/user'
import { useChatStore } from '@/stores/chat'
import { chatWs } from '@/services/ws'
import request from '@/utils/request'
import type { Message } from '@/types'
import MessageList from '@/components/MessageList.vue'
import ChatInput from '@/components/ChatInput.vue'
import LotteryResult from '@/components/LotteryResult.vue'

type PageState = 'loading' | 'ready' | 'error'

const route = useRoute()
const router = useRouter()
const userStore = useUserStore()
const chatStore = useChatStore()

const state = ref<PageState>('loading')
const errorMsg = ref('')
const serviceUserName = ref('客服')
const loadingMore = ref(false)
const oldestSeq = ref(0)
let isSyncing = false // flag: true when reloading history after reconnect

/* ---- Back-navigation guard ---- */
const showBackConfirm = ref(false)
let backGuardPushed = false

function pushBackGuard() {
  if (!backGuardPushed) {
    history.pushState({ chatBackGuard: true }, '')
    backGuardPushed = true
  }
}

function onPopState(_e: PopStateEvent) {
  // Ignore popstate triggered by DocxPreview closing — just re-push guard
  if (history.state?.chatBackGuard) {
    return
  }
  // Browser back / swipe-back popped our guard state
  if (backGuardPushed) {
    backGuardPushed = false
    showBackConfirm.value = true
  }
}

function onBackClick() {
  showBackConfirm.value = true
}

function confirmBack() {
  showBackConfirm.value = false
  window.removeEventListener('popstate', onPopState)
  // If guard state was NOT yet popped (click-triggered), pop it first
  if (backGuardPushed) {
    backGuardPushed = false
    history.back() // pop the guard entry
    // After a tick, actually navigate back
    setTimeout(() => router.back(), 0)
  } else {
    // Guard was already popped by swipe; just navigate
    router.back()
  }
}

function cancelBack() {
  showBackConfirm.value = false
  // Re-push guard if it was consumed by swipe
  pushBackGuard()
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
    const res = await request.post<unknown, {
      token: string
      userId: string
      nickname?: string
      avatar?: string
      serviceUserId?: string
      serviceNickname?: string
      serviceAvatar?: string
    }>('/client/auth/login', { userId: targetId })

    userStore.login({
      userId: targetId,
      token: res.token,
      nickname: res.nickname,
      avatar: res.avatar,
      serviceUserId: res.serviceUserId,
      serviceNickname: res.serviceNickname,
      serviceAvatar: res.serviceAvatar
    })

    serviceUserName.value = res.serviceNickname || '客服'
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

    chatWs.onMessageDeleted = (serverMsgId: string) => {
      chatStore.removeMessageByServerMsgID(serverMsgId)
    }

    chatWs.onHistory = (data) => {
      const msgs = data.messages as unknown as Message[]
      // Parse content for each message
      const parsed = msgs.map(m => {
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
      })

      if (isSyncing) {
        // Reconnect sync: append new messages to the end (don't prepend)
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

    // 3. Connect WebSocket
    await new Promise<void>((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error('WebSocket 连接超时')), 10000)
      chatWs.onConnected = () => {
        clearTimeout(timeout)
        resolve()
      }
      chatWs.connect(userStore.userId, userStore.token, 'client')
    })

    // 4. Sync missed messages on reconnect
    chatWs.onReconnected = () => {
      // Reload history to catch messages received while WS was down
      isSyncing = true
      chatWs.loadHistory(serviceId)
    }

    state.value = 'ready'

    // 5. Load recent history
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

onMounted(() => {
  pushBackGuard()
  window.addEventListener('popstate', onPopState)
  init()
})
onUnmounted(() => {
  window.removeEventListener('popstate', onPopState)
  chatWs.disconnect()
})
</script>

<style scoped>
/* All layout styles are in chat.css; only local overrides here */

.back-confirm-mask {
  position: fixed;
  inset: 0;
  background: rgba(0, 0, 0, 0.45);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 9999;
}
.back-confirm-dialog {
  background: #fff;
  border-radius: 12px;
  width: 280px;
  padding: 24px 20px 16px;
  text-align: center;
  box-shadow: 0 4px 24px rgba(0, 0, 0, 0.15);
}
.back-confirm-text {
  font-size: 16px;
  color: #333;
  margin: 0 0 20px;
}
.back-confirm-btns {
  display: flex;
  gap: 12px;
}
.back-confirm-btns button {
  flex: 1;
  height: 40px;
  border: none;
  border-radius: 8px;
  font-size: 15px;
  cursor: pointer;
}
.back-confirm-cancel {
  background: #f0f0f0;
  color: #666;
}
.back-confirm-ok {
  background: #07c160;
  color: #fff;
}
.fade-enter-active, .fade-leave-active {
  transition: opacity 0.2s;
}
.fade-enter-from, .fade-leave-to {
  opacity: 0;
}
</style>
