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

      <!-- Conversation list (shown when user has groups and no active chat) -->
      <template v-if="groups.length > 0 && !activeConversation">
        <header class="chat-header">
          <span class="title">消息</span>
        </header>
        <div class="user-list">
          <!-- Service staff 1-on-1 -->
          <div class="user-list-item" @click="selectConversation(serviceIdRef, serviceUserName, false)">
            <div class="avatar">{{ serviceUserName.charAt(0) }}</div>
            <div class="user-list-info">
              <span class="user-list-name">{{ serviceUserName }}</span>
              <span class="user-list-id">客服</span>
            </div>
          </div>
          <!-- Groups -->
          <div
            v-for="g in groups"
            :key="g.groupId"
            class="user-list-item"
            @click="selectConversation(g.groupId, g.name, true)"
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
        </div>
      </template>

      <!-- Active chat panel (shown when conversation is selected, or no groups) -->
      <template v-if="activeConversation || groups.length === 0">
        <!-- Lottery result -->
        <LotteryResult />

        <!-- Group banner notification -->
        <div v-if="groupBanner" class="group-banner">
          {{ groupBanner }}
        </div>

        <!-- Header -->
        <header class="chat-header">
          <button class="back-btn" @click="groups.length > 0 ? goBackToList() : onBackClick()">‹</button>
          <span class="title">{{ activeConversationName || serviceUserName }}</span>
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
const serviceIdRef = ref('')
const loadingMore = ref(false)
const oldestSeq = ref(0)
const groupBanner = ref('')   // 群组通知横幅（被踢出 / 群解散）

// Conversation list (groups the user belongs to)
const groups = ref<{ groupId: string; name: string; avatar: string }[]>([])
const activeConversation = ref('')           // '' = show list; otherwise = active peer ID
const activeConversationName = ref('')
const activeConversationIsGroup = ref(false)

let isSyncing = false // flag: true when reloading history after reconnect
let pendingHistoryPeer = '' // race guard: expected peerUserId for the next history response

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
      groups?: { groupId: string; name: string; avatar: string }[]
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
    serviceIdRef.value = serviceId
    groups.value = res.groups || []

    if (!userStore.token) {
      throw new Error('登录令牌缺失，请重新进入聊天链接')
    }

    // 2. Setup WebSocket callbacks
    chatWs.onNewMessage = (msg: Message) => {
      // Only add to current chat if it matches the active private conversation
      if (!activeConversationIsGroup.value && activeConversation.value) {
        chatStore.addMessage(msg)
      } else if (groups.value.length === 0) {
        chatStore.addMessage(msg)
      }
    }

    chatWs.onNewGroupMessage = (msg) => {
      if (activeConversationIsGroup.value && activeConversation.value === msg.groupId) {
        chatStore.addMessage(msg)
      }
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

    chatWs.onGroupMemberRemoved = (groupId: string, userId: string) => {
      if (userId === userStore.userId) {
        groupBanner.value = '您已被移出群聊'
        // Remove the group from the local list so user knows they left
        groups.value = groups.value.filter(g => g.groupId !== groupId)
      }
    }

    chatWs.onGroupMemberAdded = (gId: string, gName: string, userId: string) => {
      if (userId === userStore.userId) {
        // Clear any kick/dissolve banner
        groupBanner.value = ''
        // Re-add the group to the list if it's not already there
        const alreadyListed = groups.value.some(g => g.groupId === gId)
        if (!alreadyListed) {
          groups.value.push({ groupId: gId, name: gName || '群聊', avatar: '' })
        }
      }
    }

    chatWs.onGroupDissolved = (_groupId: string) => {
      groupBanner.value = '该群聊已解散'
    }

    chatWs.onHistory = (data) => {
      // Discard stale responses that arrived after switching conversations
      if (data.peerUserId !== pendingHistoryPeer) return
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
      if (activeConversation.value) {
        isSyncing = true
        const peerId = activeConversationIsGroup.value ? 'group_' + activeConversation.value : activeConversation.value
        pendingHistoryPeer = peerId
        chatWs.loadHistory(peerId)
      }
    }

    state.value = 'ready'

    // 5. If no groups, open service staff chat directly; otherwise show list
    if (groups.value.length === 0) {
      activeConversation.value = serviceId
      activeConversationName.value = serviceUserName.value
      activeConversationIsGroup.value = false
      pendingHistoryPeer = serviceId
      chatWs.loadHistory(serviceId)
      chatWs.markRead(serviceId)
    }
    // else: leave activeConversation empty so the list is shown
  } catch (err) {
    console.error('[Chat] init failed', err)
    errorMsg.value = (err as Error).message || '连接失败，请重试'
    state.value = 'error'
  }
}

function onLoadMore() {
  if (loadingMore.value || !chatStore.hasMore) return
  loadingMore.value = true
  const peerId = activeConversationIsGroup.value ? 'group_' + activeConversation.value : activeConversation.value
  chatWs.loadHistory(peerId, oldestSeq.value, 50)
}

function selectConversation(id: string, name: string, isGroup: boolean) {
  activeConversation.value = id
  activeConversationName.value = name
  activeConversationIsGroup.value = isGroup
  isSyncing = false
  chatStore.clearMessages()
  oldestSeq.value = 0
  groupBanner.value = ''
  const peerId = isGroup ? 'group_' + id : id
  pendingHistoryPeer = peerId
  chatWs.loadHistory(peerId)
  if (!isGroup) chatWs.markRead(id)
}

function goBackToList() {
  activeConversation.value = ''
  activeConversationName.value = ''
  activeConversationIsGroup.value = false
  chatStore.clearMessages()
}

function onSendText(text: string) {
  const peerId = activeConversation.value || serviceIdRef.value
  if (activeConversationIsGroup.value) {
    const clientMsgID = chatWs.sendGroupMessage(peerId, text)
    chatStore.addMessage({
      clientMsgID,
      sendID: userStore.userId,
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
  const tempMsg: Message = {
    clientMsgID,
    sendID: userStore.userId,
    recvID: peerId,
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
  const peerId = activeConversation.value || serviceIdRef.value
  const url = URL.createObjectURL(file)
  const tempMsgID = `tmp_${Date.now()}`
  const tempMsg: Message = {
    clientMsgID: tempMsgID,
    sendID: userStore.userId,
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
    const realId = await chatWs.sendImageMessage(peerId, file)
    // Update temp msg's clientMsgID to the real one for ACK matching
    const msg = chatStore.messages.find(m => m.clientMsgID === tempMsgID)
    if (msg) msg.clientMsgID = realId
  } catch (err) {
    chatStore.updateMessageStatus(tempMsgID, 3)
  }
}

async function onSendFile(file: File) {
  const peerId = activeConversation.value || serviceIdRef.value
  const tempMsgID = `tmp_${Date.now()}`
  const tempMsg: Message = {
    clientMsgID: tempMsgID,
    sendID: userStore.userId,
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
    const realId = await chatWs.sendFileMessage(peerId, file)
    const msg = chatStore.messages.find(m => m.clientMsgID === tempMsgID)
    if (msg) msg.clientMsgID = realId
  } catch (err) {
    chatStore.updateMessageStatus(tempMsgID, 3)
  }
}

async function onSendVoice({ blob, duration }: { blob: Blob; duration: number }) {
  const peerId = activeConversation.value || serviceIdRef.value
  const url = URL.createObjectURL(blob)
  const tempMsgID = `tmp_${Date.now()}`
  const tempMsg: Message = {
    clientMsgID: tempMsgID,
    sendID: userStore.userId,
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
    const realId = await chatWs.sendVoiceMessage(peerId, blob, duration)
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

.user-list {
  flex: 1;
  overflow-y: auto;
  padding: 0;
  background: var(--wechat-bg, #ededed);
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

.avatar {
  width: 40px;
  height: 40px;
  border-radius: 6px;
  background: var(--wechat-green, #07c160);
  color: #fff;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 18px;
  font-weight: 600;
  flex-shrink: 0;
}

.group-avatar {
  background: #5b8cff;
  font-size: 13px;
}

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
.group-banner {
  position: sticky;
  top: 0;
  z-index: 10;
  background: #fff3cd;
  color: #856404;
  text-align: center;
  padding: 8px 16px;
  font-size: 13px;
  border-bottom: 1px solid #ffc107;
}
</style>
