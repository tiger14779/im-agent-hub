/**
 * Native WebSocket chat service — replaces OpenIM SDK.
 *
 * Protocol: JSON envelopes  { type: string, data: object }
 * Server types: message_ack, new_message, history, pong
 * Client types: send_message, load_history, mark_read, ping
 */

import type { Message } from '@/types'

/** Portable UUID generator */
function uuid(): string {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
    return crypto.randomUUID()
  }
  return Array.from({ length: 16 }, () =>
    Math.floor(Math.random() * 256).toString(16).padStart(2, '0')
  ).join('')
}

interface AckData {
  clientMsgId: string
  serverMsgId?: string
  seq?: number
  sendTime?: number
  status: number
  error?: string
}

interface HistoryData {
  peerUserId: string
  conversationId: string
  messages: ServerMessage[]
  hasMore: boolean
}

interface ServerMessage {
  serverMsgID: string
  clientMsgID: string
  sendID: string
  recvID: string
  conversationID: string
  contentType: number
  content: string
  sendTime: number
  seq: number
  status: number
  isGroup?: boolean
  senderName?: string
  senderAvatar?: string
}

// ── 通话信令类型 ──────────────────────────────────────────────────
export interface CallInviteData {
  fromId: string
  fromName: string
  toId: string
  roomName: string
  livekitUrl: string
}

export interface CallSignalData {
  fromId: string
  toId: string
  roomName?: string
}

type Envelope = { type: string; data: unknown }

class ChatWsService {
  private ws: WebSocket | null = null
  private userId = ''
  private token = ''
  private role: 'client' | 'staff' = 'client'
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null
  private pingTimer: ReturnType<typeof setInterval> | null = null
  private connected = false
  private intentionalClose = false
  private reconnectAttempts = 0
  private lastServerTime = 0 // timestamp of last message received from server
  private static readonly PING_INTERVAL = 10000 // 10s
  private static readonly STALE_THRESHOLD = 25000 // 25s no response → stale
  private isFirstConnect = true // track first vs reconnect
  private visibilityHandler: (() => void) | null = null // page visibility listener
  private lastVisibilitySent: boolean | null = null // dedupe visibility reports

  /** Pending sends: clientMsgId → full payload + retry state */
  private pendingSends = new Map<string, {
    payload: { recvId: string; contentType: number; content: string; clientMsgId: string }
    timer: ReturnType<typeof setTimeout> | null
    retries: number
  }>()
  /** ACK watchdog timers for group messages (no retry, just timeout-fail) */
  private pendingGroupTimers = new Map<string, ReturnType<typeof setTimeout>>()
  private static readonly ACK_TIMEOUT = 8000 // 8s per attempt
  private static readonly MAX_RETRIES = 2     // retry up to 2 times on reconnect

  // Callbacks
  onNewMessage: (msg: Message) => void = () => {}
  onAck: (ack: AckData) => void = () => {}
  onHistory: (data: HistoryData) => void = () => {}
  onConnected: () => void = () => {}
  onDisconnected: () => void = () => {}
  onReconnected: () => void = () => {} // fires only on reconnect (not first connect)
  onMessageDeleted: (serverMsgId: string) => void = () => {} // message deleted by peer
  onGroupMemberAdded: (groupId: string, groupName: string, userId: string, nickname: string) => void = () => {}
  onGroupMemberRemoved: (groupId: string, userId: string) => void = () => {}
  onGroupDissolved: (groupId: string) => void = () => {}
  onNewGroupMessage: (msg: Message & { groupId: string; groupName: string }) => void = () => {}
  // ── 通话信令回调 ──────────────────────────────────────────────────
  onCallInvite: (data: CallInviteData) => void = () => {}
  onCallAccept: (data: CallSignalData) => void = () => {}
  onCallReject: (data: CallSignalData) => void = () => {}
  onCallBusy: (data: CallSignalData) => void = () => {}
  onCallEnd: (data: CallSignalData) => void = () => {}

  /** Build the WebSocket URL based on current page origin */
  private buildWsUrl(): string {
    const loc = window.location
    const proto = loc.protocol === 'https:' ? 'wss:' : 'ws:'
    const path = this.role === 'staff'
      ? `/api/service/ws?staffId=${encodeURIComponent(this.userId)}&token=${encodeURIComponent(this.token)}`
      : `/api/ws?userId=${encodeURIComponent(this.userId)}&token=${encodeURIComponent(this.token)}`
    return `${proto}//${loc.host}${path}`
  }

  connect(userId: string, token: string, role: 'client' | 'staff' = 'client') {
    this.userId = userId
    this.token = token
    this.role = role
    this.intentionalClose = false
    this.isFirstConnect = true
    this.doConnect()
  }

  /** Whether a connection attempt is already in flight */
  private get isConnecting() {
    return this.ws !== null && this.ws.readyState === WebSocket.CONNECTING
  }

  private doConnect() {
    // Don't abort a connection that's still being established
    if (this.isConnecting) return

    if (this.ws) {
      this.ws.onclose = null
      this.ws.close()
    }

    const url = this.buildWsUrl()
    this.ws = new WebSocket(url)

    this.ws.onopen = () => {
      this.connected = true
      this.reconnectAttempts = 0
      this.lastServerTime = Date.now()
      this.onConnected()
      this.startPing()
      this.flushPendingSends()
      this.startVisibilityTracking()
      if (!this.isFirstConnect) {
        // This is a reconnect — notify UI to sync missed messages
        this.onReconnected()
      }
      this.isFirstConnect = false
    }

    this.ws.onmessage = (ev) => {
      this.lastServerTime = Date.now()
      try {
        const env: Envelope = JSON.parse(ev.data)
        this.handleMessage(env)
      } catch {
        console.warn('[WS] bad message', ev.data)
      }
    }

    this.ws.onclose = () => {
      this.connected = false
      this.stopPing()
      this.stopVisibilityTracking()
      this.pausePendingTimers()
      this.onDisconnected()
      if (!this.intentionalClose) {
        this.scheduleReconnect()
      } else {
        this.failAllPending('连接已关闭')
      }
    }

    this.ws.onerror = () => {
      // onclose will fire after onerror
    }
  }

  private handleMessage(env: Envelope) {
    switch (env.type) {
      case 'new_message': {
        const raw = env.data as ServerMessage
        this.onNewMessage(this.toMessage(raw))
        break
      }
      case 'message_ack': {
        const ack = env.data as AckData
        this.removePending(ack.clientMsgId)
        this.onAck(ack)
        break
      }
      case 'history': {
        this.onHistory(env.data as HistoryData)
        break
      }
      case 'pong':
        break
      case 'message_deleted':
      case 'delete_ack': {
        const d = env.data as { serverMsgId: string }
        if (d.serverMsgId) this.onMessageDeleted(d.serverMsgId)
        break
      }
      case 'group_member_added': {
        const d = env.data as { groupId: string; groupName?: string; userId: string; nickname: string }
        this.onGroupMemberAdded(d.groupId, d.groupName ?? '', d.userId, d.nickname)
        break
      }
      case 'group_member_removed': {
        const d = env.data as { groupId: string; userId: string }
        this.onGroupMemberRemoved(d.groupId, d.userId)
        break
      }
      case 'group_dissolved': {
        const d = env.data as { groupId: string }
        this.onGroupDissolved(d.groupId)
        break
      }
      case 'new_group_message': {
        const raw = env.data as ServerMessage & { groupId: string; groupName: string }
        const msg = this.toMessage(raw) as Message & { groupId: string; groupName: string }
        msg.groupId = raw.groupId
        msg.groupName = raw.groupName
        msg.isGroup = true
        msg.senderName = raw.senderName
        this.onNewGroupMessage(msg)
        break
      }
      // ── 通话信令 ──────────────────────────────────────────────────
      case 'call_invite': {
        const d = env.data as CallInviteData
        this.onCallInvite(d)
        break
      }
      case 'call_accept': {
        const d = env.data as CallSignalData
        this.onCallAccept(d)
        break
      }
      case 'call_reject': {
        const d = env.data as CallSignalData
        this.onCallReject(d)
        break
      }
      case 'call_busy': {
        const d = env.data as CallSignalData
        this.onCallBusy(d)
        break
      }
      case 'call_end': {
        const d = env.data as CallSignalData
        this.onCallEnd(d)
        break
      }
      default:
        console.log('[WS] unknown type', env.type)
    }
  }

  /** Convert server message to frontend Message type */
  private toMessage(raw: ServerMessage): Message {
    const contentType = raw.contentType
    const content = raw.content || ''
    const msg: Message = {
      clientMsgID: raw.clientMsgID,
      serverMsgID: raw.serverMsgID,
      sendID: raw.sendID,
      recvID: raw.recvID,
      sessionType: 1,
      contentType,
      content,
      sendTime: raw.sendTime,
      status: raw.status || 2,
      isGroup: raw.isGroup,
      senderName: raw.senderName,
      senderAvatar: raw.senderAvatar
    }

    // Parse content JSON into typed fields
    try {
      const parsed = JSON.parse(content)
      if (contentType === 101) {
        msg.textContent = parsed.text ?? parsed.content ?? content
      } else if (contentType === 102) {
        const imgUrl = parsed.url ?? parsed.sourcePicture?.url ?? ''
        msg.pictureContent = { sourcePicture: { url: imgUrl }, snapshotPicture: { url: imgUrl } }
      } else if (contentType === 103) {
        msg.voiceContent = { sourceUrl: parsed.url, duration: parsed.duration }
      } else if (contentType === 105) {
        msg.fileContent = { sourceUrl: parsed.url, fileName: parsed.name, fileSize: parsed.size, fileType: parsed.type }
      }
    } catch {
      if (contentType === 101) {
        msg.textContent = content
      }
    }

    return msg
  }

  private send(type: string, data: unknown) {
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify({ type, data }))
      return true
    }
    return false
  }

  /** Enqueue a message send with retry support */
  private sendMessage(payload: { recvId: string; contentType: number; content: string; clientMsgId: string }) {
    const entry = { payload, timer: null as ReturnType<typeof setTimeout> | null, retries: 0 }
    this.pendingSends.set(payload.clientMsgId, entry)
    if (this.send('send_message', payload)) {
      this.startAckTimer(payload.clientMsgId)
    } else if (!this.isConnecting && !this.reconnectTimer && !this.intentionalClose) {
      // Only trigger reconnect if NOT already connecting / reconnecting
      this.scheduleReconnect()
    }
    // Otherwise: WS is CONNECTING — message stays in pendingSends,
    // will be sent when onopen fires via flushPendingSends()
  }

  /** Start ACK timeout for a specific message */
  private startAckTimer(clientMsgId: string) {
    const entry = this.pendingSends.get(clientMsgId)
    if (!entry) return
    if (entry.timer) clearTimeout(entry.timer)
    entry.timer = setTimeout(() => {
      entry.timer = null
      if (!this.connected) return // disconnected — will be retried on reconnect
      // ACK timeout while "connected" → connection is likely stale
      // Force close to trigger reconnect; message stays in pendingSends for retry
      console.warn('[WS] ACK timeout for', clientMsgId, '— forcing reconnect')
      this.forceClose()
    }, ChatWsService.ACK_TIMEOUT)
  }

  /** Force-close a stale connection to trigger reconnect */
  private forceClose() {
    if (this.ws) {
      this.ws.close()
    }
  }

  /** Remove a message from pending (ACK received) */
  private removePending(clientMsgId: string) {
    const entry = this.pendingSends.get(clientMsgId)
    if (entry) {
      if (entry.timer) clearTimeout(entry.timer)
      this.pendingSends.delete(clientMsgId)
    }
    // Also clear group message watchdog timer if present
    const groupTimer = this.pendingGroupTimers.get(clientMsgId)
    if (groupTimer) {
      clearTimeout(groupTimer)
      this.pendingGroupTimers.delete(clientMsgId)
    }
  }

  /** Pause all ACK timers on disconnect (don't fail — will retry) */
  private pausePendingTimers() {
    for (const entry of this.pendingSends.values()) {
      if (entry.timer) {
        clearTimeout(entry.timer)
        entry.timer = null
      }
    }
  }

  /** Resend all pending messages after reconnect */
  private flushPendingSends() {
    for (const [clientMsgId, entry] of this.pendingSends) {
      entry.retries++
      if (entry.retries > ChatWsService.MAX_RETRIES) {
        this.pendingSends.delete(clientMsgId)
        this.onAck({ clientMsgId, status: 3, error: '多次重试失败' })
        continue
      }
      if (this.send('send_message', entry.payload)) {
        this.startAckTimer(clientMsgId)
      }
    }
  }

  /** Fail all pending messages (only on intentional close) */
  private failAllPending(reason: string) {
    for (const [id, entry] of this.pendingSends) {
      if (entry.timer) clearTimeout(entry.timer)
      this.onAck({ clientMsgId: id, status: 3, error: reason })
    }
    this.pendingSends.clear()
  }

  // ── Public API ─────────────────────────────────────────────

  sendTextMessage(recvId: string, text: string): string {
    const clientMsgId = uuid()
    this.sendMessage({
      recvId,
      contentType: 101,
      content: JSON.stringify({ text }),
      clientMsgId
    })
    return clientMsgId
  }

  async sendImageMessage(recvId: string, file: File): Promise<string> {
    const url = await this.uploadFile(file)
    const clientMsgId = uuid()
    this.sendMessage({
      recvId,
      contentType: 102,
      content: JSON.stringify({ url, name: file.name, size: file.size, type: file.type }),
      clientMsgId
    })
    return clientMsgId
  }

  async sendVoiceMessage(recvId: string, blob: Blob, duration: number): Promise<string> {
    const url = await this.uploadFile(new File([blob], 'voice.webm', { type: blob.type }))
    const clientMsgId = uuid()
    this.sendMessage({
      recvId,
      contentType: 103,
      content: JSON.stringify({ url, duration, size: blob.size }),
      clientMsgId
    })
    return clientMsgId
  }

  async sendFileMessage(recvId: string, file: File): Promise<string> {
    const url = await this.uploadFile(file)
    const clientMsgId = uuid()
    this.sendMessage({
      recvId,
      contentType: 105,
      content: JSON.stringify({ url, name: file.name, size: file.size, type: file.type }),
      clientMsgId
    })
    return clientMsgId
  }

  sendGroupMessage(groupId: string, text: string): string {
    const clientMsgId = uuid()
    const sent = this.send('send_group_message', {
      groupId,
      contentType: 101,
      content: JSON.stringify({ text }),
      clientMsgId
    })
    if (!sent) {
      // WS not open — fail immediately so the UI doesn't stay stuck in "sending"
      setTimeout(() => this.onAck({ clientMsgId, status: 3, error: '连接已断开，请稍后重试' }), 0)
    } else {
      // Start an ACK watchdog: if no response arrives within timeout, mark as failed
      const timer = setTimeout(() => {
        if (this.pendingGroupTimers.has(clientMsgId)) {
          this.pendingGroupTimers.delete(clientMsgId)
          this.onAck({ clientMsgId, status: 3, error: '发送超时' })
        }
      }, ChatWsService.ACK_TIMEOUT)
      this.pendingGroupTimers.set(clientMsgId, timer)
    }
    return clientMsgId
  }

  loadHistory(peerUserId: string, beforeSeq = 0, limit = 50) {
    this.send('load_history', { peerUserId, beforeSeq, limit })
  }

  markRead(peerUserId: string) {
    this.send('mark_read', { peerUserId })
  }

  // ── 通话信令发送方法 ──────────────────────────────────────────────
  sendCallInvite(toId: string, roomName: string, livekitUrl: string, fromName: string) {
    this.send('call_invite', { toId, fromId: this.userId, fromName, roomName, livekitUrl })
  }

  sendCallAccept(toId: string, roomName: string) {
    this.send('call_accept', { toId, fromId: this.userId, roomName })
  }

  sendCallReject(toId: string) {
    this.send('call_reject', { toId, fromId: this.userId })
  }

  sendCallBusy(toId: string) {
    this.send('call_busy', { toId, fromId: this.userId })
  }

  sendCallEnd(toId: string, roomName: string) {
    this.send('call_end', { toId, fromId: this.userId, roomName })
  }

  disconnect() {
    this.intentionalClose = true
    this.stopPing()
    this.stopVisibilityTracking()
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer)
      this.reconnectTimer = null
    }
    this.failAllPending('连接已关闭')
    if (this.ws) {
      this.ws.close()
      this.ws = null
    }
    this.connected = false
  }

  get isConnected() {
    return this.connected
  }

  // ── Internal helpers ───────────────────────────────────────

  private async uploadFile(file: File): Promise<string> {
    const formData = new FormData()
    formData.append('file', file, file.name)
    const resp = await fetch('/api/upload', { method: 'POST', body: formData })
    if (!resp.ok) throw new Error(`文件上传失败: HTTP ${resp.status}`)
    const json = await resp.json()
    const url = json?.data?.url
    if (!url || typeof url !== 'string') throw new Error('文件上传失败：未返回有效URL')
    return url
  }

  private startPing() {
    this.stopPing()
    this.pingTimer = setInterval(() => {
      // Check for stale connection: no server message for too long
      if (this.lastServerTime > 0 && Date.now() - this.lastServerTime > ChatWsService.STALE_THRESHOLD) {
        console.warn('[WS] stale connection detected (no server response for',
          Math.round((Date.now() - this.lastServerTime) / 1000), 's), forcing reconnect')
        this.forceClose()
        return
      }
      this.send('ping', {})
    }, ChatWsService.PING_INTERVAL)
  }

  private stopPing() {
    if (this.pingTimer) {
      clearInterval(this.pingTimer)
      this.pingTimer = null
    }
  }

  private startVisibilityTracking() {
    this.stopVisibilityTracking()
    this.visibilityHandler = () => {
      this.sendVisibilityIfChanged(false)
    }
    document.addEventListener('visibilitychange', this.visibilityHandler)
    this.sendVisibilityIfChanged(true)
  }

  private stopVisibilityTracking() {
    if (this.visibilityHandler) {
      document.removeEventListener('visibilitychange', this.visibilityHandler)
      this.visibilityHandler = null
    }
  }

  private sendVisibilityIfChanged(force: boolean) {
    const visible = !document.hidden
    if (!force && this.lastVisibilitySent === visible) {
      return
    }
    if (this.send('visibility', { visible })) {
      this.lastVisibilitySent = visible
    }
  }

  private scheduleReconnect() {
    if (this.reconnectTimer || this.isConnecting) return
    // Exponential backoff: 0 → 1s → 3s → 6s → 12s → 30s
    const delays = [0, 1000, 3000, 6000, 12000, 30000]
    const delay = delays[Math.min(this.reconnectAttempts, delays.length - 1)]
    this.reconnectAttempts++
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = null
      if (!this.intentionalClose) {
        console.log('[WS] reconnecting... attempt', this.reconnectAttempts)
        this.doConnect()
      }
    }, delay)
  }
}

export const chatWs = new ChatWsService()
