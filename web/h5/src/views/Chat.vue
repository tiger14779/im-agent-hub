<template>
  <div class="chat-container">
    <!-- 语音通话悬浮层（全局挂载，随时可接听） -->
    <VoiceCall
      v-if="userStore.userId"      ref="voiceCallRef"      :my-user-id="userStore.userId"
    />
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

    <!-- Chat UI -->
    <template v-if="state === 'ready'">
      <!-- Lottery result -->
      <LotteryResult />

      <!-- 群组入口横幅卡片（始终显示在开奖球下方） -->
      <div v-if="firstGroup" class="group-entry-card" @click="openGroupChat(firstGroup)">
        <div class="gec-avatar">
          <img v-if="firstGroup.avatar" :src="firstGroup.avatar" class="gec-avatar-img" />
          <span v-else class="gec-avatar-text">群</span>
        </div>
        <div class="gec-info">
          <div class="gec-row1">
            <span class="gec-name">{{ firstGroup.name }}</span>
            <span class="gec-count">{{ firstGroup.memberCount }}人</span>
            <span v-if="groupUnread > 0" class="gec-badge">{{ groupUnread > 99 ? '99+' : groupUnread }}</span>
          </div>
          <div class="gec-preview">{{ groupLastMsg || '点击进入群聊' }}</div>
        </div>
        <span class="gec-arrow">›</span>
      </div>

      <!-- 群组系统通知（被踢出/解散） -->
      <div v-if="groupBanner" class="group-banner">
        {{ groupBanner }}
      </div>

      <!-- Header -->
      <header class="chat-header">
        <button v-if="activeConversationIsGroup" class="back-btn-large" @click="backToServiceChat">‹</button>
        <button v-else class="back-btn" @click="onBackClick">‹</button>
        <span class="title">{{ activeConversationName || serviceUserName }}</span>
        <button v-if="activeConversationIsGroup" class="members-btn" @click="openMembersPanel" title="群成员">
          <span class="members-icon">👥</span>
        </button>
        <span v-else class="more-btn">···</span>
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
        :show-call="!activeConversationIsGroup"
        @send-text="onSendText"
        @send-image="onSendImage"
        @send-file="onSendFile"
        @send-voice="onSendVoice"
        @start-call="onStartCall"
      />
    </template>

    <!-- 群成员面板 -->
    <teleport to="body">
      <transition name="slide-up">
        <div v-if="showMembersPanel" class="members-overlay" @click.self="showMembersPanel = false">
          <div class="members-panel">
            <div class="members-panel-header">
              <span class="members-panel-title">群成员 ({{ groupMembers.length }})</span>
              <button class="members-panel-close" @click="showMembersPanel = false">✕</button>
            </div>
            <div v-if="membersLoading" class="members-loading">加载中...</div>
            <div v-else class="members-grid">
              <div v-for="m in groupMembers" :key="m.userId" class="member-item">
                <div class="member-avatar">
                  <img v-if="m.avatarUrl" :src="m.avatarUrl" class="member-avatar-img" />
                  <span v-else class="member-avatar-text">{{ (m.nickname || m.userId).charAt(0) }}</span>
                </div>
                <span class="member-name">{{ m.nickname || m.userId }}</span>
              </div>
            </div>
          </div>
        </div>
      </transition>
    </teleport>

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
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useUserStore } from '@/stores/user'
import { useChatStore } from '@/stores/chat'
import { chatWs } from '@/services/ws'
import request from '@/utils/request'
import type { Message } from '@/types'
import MessageList from '@/components/MessageList.vue'
import ChatInput from '@/components/ChatInput.vue'
import LotteryResult from '@/components/LotteryResult.vue'
import VoiceCall from '@/components/VoiceCall.vue'

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
const groups = ref<{ groupId: string; name: string; avatar: string; memberCount: number }[]>([])
const activeConversation = ref('')           // '' = show list; otherwise = active peer ID
const activeConversationName = ref('')
const activeConversationIsGroup = ref(false)
const voiceCallRef = ref<InstanceType<typeof VoiceCall> | null>(null)

// 群未读计数 & 最后一条消息预览
const groupUnread = ref(0)
const groupLastMsg = ref('')

// 群成员面板
const showMembersPanel = ref(false)
const membersLoading = ref(false)
const groupMembers = ref<{ userId: string; nickname: string; avatarUrl: string; role: string }[]>([])

// 只使用第一个群（业务约定只有一个群）
const firstGroup = computed(() => groups.value[0] ?? null)

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
    groups.value = (res.groups || []) as { groupId: string; name: string; avatar: string; memberCount: number }[]

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
      } else {
        // 当前不在群聊中：增加未读 & 更新预览
        groupUnread.value++
        const senderPrefix = msg.senderName ? `${msg.senderName}: ` : ''
        if (msg.contentType === 101) groupLastMsg.value = senderPrefix + (msg.textContent || '')
        else if (msg.contentType === 102) groupLastMsg.value = senderPrefix + '[图片]'
        else if (msg.contentType === 103) groupLastMsg.value = senderPrefix + '[语音]'
        else if (msg.contentType === 105) groupLastMsg.value = senderPrefix + '[文件]'
        else groupLastMsg.value = senderPrefix + '新消息'
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
          groups.value.push({ groupId: gId, name: gName || '群聊', avatar: '', memberCount: 0 })
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

    // 始终默认打开客服私聊
    activeConversation.value = serviceId
    activeConversationName.value = serviceUserName.value
    activeConversationIsGroup.value = false
    pendingHistoryPeer = serviceId
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

// 打开群聊（点击群横幅卡片）
function openGroupChat(g: { groupId: string; name: string }) {
  selectConversation(g.groupId, g.name, true)
  groupUnread.value = 0
}

// 群聊内返回按钮 → 回到客服私聊
function backToServiceChat() {
  chatStore.clearMessages()
  activeConversation.value = serviceIdRef.value
  activeConversationName.value = serviceUserName.value
  activeConversationIsGroup.value = false
  isSyncing = false
  oldestSeq.value = 0
  const peerId = serviceIdRef.value
  pendingHistoryPeer = peerId
  chatWs.loadHistory(peerId)
  chatWs.markRead(peerId)
}

// 打开群成员面板
async function openMembersPanel() {
  if (!activeConversation.value) return
  showMembersPanel.value = true
  membersLoading.value = true
  try {
    const res = await request.get<unknown, { members: { userId: string; nickname: string; avatarUrl: string; role: string }[] }>(
      `/client/groups/${activeConversation.value}/members`
    )
    groupMembers.value = res.members || []
  } catch (e) {
    console.error('[Chat] fetchGroupMembers failed', e)
  } finally {
    membersLoading.value = false
  }
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
  const isGroup = activeConversationIsGroup.value
  const tempMsg: Message = {
    clientMsgID: tempMsgID,
    sendID: userStore.userId,
    recvID: peerId,
    sessionType: 1,
    contentType: 102,
    content: '',
    pictureContent: { snapshotPicture: { url } },
    sendTime: Date.now(),
    status: 1,
    ...(isGroup ? { isGroup: true } : {})
  }
  chatStore.addMessage(tempMsg)
  try {
    const realId = isGroup
      ? await chatWs.sendGroupImageMessage(peerId, file)
      : await chatWs.sendImageMessage(peerId, file)
    // Update temp msg's clientMsgID to the real one for ACK matching
    const msg = chatStore.messages.find(m => m.clientMsgID === tempMsgID)
    if (msg) msg.clientMsgID = realId
  } catch (err) {
    chatStore.updateMessageStatus(tempMsgID, 3)
  }
}

async function onSendFile(file: File) {
  const peerId = activeConversation.value || serviceIdRef.value
  const isGroup = activeConversationIsGroup.value
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
    status: 1,
    ...(isGroup ? { isGroup: true } : {})
  }
  chatStore.addMessage(tempMsg)
  try {
    const realId = isGroup
      ? await chatWs.sendGroupFileMessage(peerId, file)
      : await chatWs.sendFileMessage(peerId, file)
    const msg = chatStore.messages.find(m => m.clientMsgID === tempMsgID)
    if (msg) msg.clientMsgID = realId
  } catch (err) {
    chatStore.updateMessageStatus(tempMsgID, 3)
  }
}

async function onSendVoice({ blob, duration }: { blob: Blob; duration: number }) {
  const peerId = activeConversation.value || serviceIdRef.value
  const isGroup = activeConversationIsGroup.value
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
    status: 1,
    ...(isGroup ? { isGroup: true } : {})
  }
  chatStore.addMessage(tempMsg)
  try {
    const realId = isGroup
      ? await chatWs.sendGroupVoiceMessage(peerId, blob, duration)
      : await chatWs.sendVoiceMessage(peerId, blob, duration)
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

// ── H5 用户主动发起语音通话 ────────────────────────────────────────
function onStartCall() {
  const peerId = activeConversation.value || serviceIdRef.value
  if (!peerId) return
  const peerName = activeConversationName.value || serviceUserName.value
  voiceCallRef.value?.beginOutgoing(peerId, peerName)
}
</script>

<style scoped>
/* ── 群组入口横幅卡片 ──────────────────────────────── */
.group-entry-card {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 10px 14px;
  background: linear-gradient(135deg, #1a2540 0%, #1e3a5f 100%);
  border-bottom: 1px solid rgba(255,255,255,0.1);
  cursor: pointer;
  flex-shrink: 0;
  transition: background 0.15s;
}
.group-entry-card:active {
  background: linear-gradient(135deg, #243060 0%, #244870 100%);
}
.gec-avatar {
  width: 44px;
  height: 44px;
  border-radius: 10px;
  background: #3b5bdb;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
  overflow: hidden;
}
.gec-avatar-img { width: 100%; height: 100%; object-fit: cover; }
.gec-avatar-text { color: #fff; font-size: 16px; font-weight: 700; }
.gec-info {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 3px;
}
.gec-row1 {
  display: flex;
  align-items: center;
  gap: 6px;
}
.gec-name {
  font-size: 14px;
  font-weight: 600;
  color: #fff;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.gec-count {
  font-size: 11px;
  color: rgba(255,255,255,0.55);
  flex-shrink: 0;
}
.gec-badge {
  background: #e53935;
  color: #fff;
  border-radius: 10px;
  font-size: 11px;
  font-weight: 700;
  padding: 1px 6px;
  flex-shrink: 0;
  min-width: 18px;
  text-align: center;
}
.gec-preview {
  font-size: 12px;
  color: rgba(255,255,255,0.55);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.gec-arrow {
  color: rgba(255,255,255,0.35);
  font-size: 20px;
  flex-shrink: 0;
}

/* ── 群聊 Header 按钮 ──────────────────────────────── */
.back-btn-large {
  background: none;
  border: none;
  font-size: 30px;
  line-height: 1;
  padding: 0 10px 0 4px;
  color: #fff;
  cursor: pointer;
  font-weight: 300;
}
.members-btn {
  background: none;
  border: none;
  padding: 0 4px 0 10px;
  cursor: pointer;
  line-height: 1;
}
.members-icon { font-size: 20px; }

/* ── 群成员面板 ──────────────────────────────────────── */
.members-overlay {
  position: fixed;
  inset: 0;
  background: rgba(0,0,0,0.5);
  z-index: 2000;
  display: flex;
  align-items: flex-end;
}
.members-panel {
  width: 100%;
  background: #fff;
  border-radius: 16px 16px 0 0;
  max-height: 70vh;
  display: flex;
  flex-direction: column;
}
.members-panel-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 16px 20px 12px;
  border-bottom: 1px solid #f0f0f0;
  flex-shrink: 0;
}
.members-panel-title { font-size: 16px; font-weight: 600; color: #1a1a1a; }
.members-panel-close {
  background: none;
  border: none;
  font-size: 18px;
  color: #999;
  cursor: pointer;
  padding: 4px;
}
.members-loading {
  text-align: center;
  padding: 30px;
  color: #999;
  font-size: 14px;
}
.members-grid {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 16px 8px;
  padding: 16px;
  overflow-y: auto;
}
.member-item {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 5px;
}
.member-avatar {
  width: 52px;
  height: 52px;
  border-radius: 10px;
  background: #3b5bdb;
  display: flex;
  align-items: center;
  justify-content: center;
  overflow: hidden;
}
.member-avatar-img { width: 100%; height: 100%; object-fit: cover; }
.member-avatar-text { color: #fff; font-size: 18px; font-weight: 600; }
.member-name {
  font-size: 11px;
  color: #555;
  text-align: center;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  width: 100%;
}

/* ── 面板滑入动画 ─────────────────────────────────── */
.slide-up-enter-active, .slide-up-leave-active {
  transition: transform 0.25s ease;
}
.slide-up-enter-from, .slide-up-leave-to {
  transform: translateY(100%);
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
