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

  // Callbacks
  onNewMessage: (msg: Message) => void = () => {}
  onAck: (ack: AckData) => void = () => {}
  onHistory: (data: HistoryData) => void = () => {}
  onConnected: () => void = () => {}
  onDisconnected: () => void = () => {}

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
    this.doConnect()
  }

  private doConnect() {
    if (this.ws) {
      this.ws.onclose = null
      this.ws.close()
    }

    const url = this.buildWsUrl()
    this.ws = new WebSocket(url)

    this.ws.onopen = () => {
      this.connected = true
      this.onConnected()
      this.startPing()
    }

    this.ws.onmessage = (ev) => {
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
      this.onDisconnected()
      if (!this.intentionalClose) {
        this.scheduleReconnect()
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
        this.onAck(env.data as AckData)
        break
      }
      case 'history': {
        this.onHistory(env.data as HistoryData)
        break
      }
      case 'pong':
        break
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
      status: raw.status || 2
    }

    // Parse content JSON into typed fields
    try {
      const parsed = JSON.parse(content)
      if (contentType === 101) {
        msg.textContent = parsed.text ?? parsed.content ?? content
      } else if (contentType === 102) {
        msg.pictureContent = { sourcePicture: { url: parsed.url }, snapshotPicture: { url: parsed.url } }
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
    }
  }

  // ── Public API ─────────────────────────────────────────────

  sendTextMessage(recvId: string, text: string): string {
    const clientMsgId = uuid()
    this.send('send_message', {
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
    this.send('send_message', {
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
    this.send('send_message', {
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
    this.send('send_message', {
      recvId,
      contentType: 105,
      content: JSON.stringify({ url, name: file.name, size: file.size, type: file.type }),
      clientMsgId
    })
    return clientMsgId
  }

  loadHistory(peerUserId: string, beforeSeq = 0, limit = 50) {
    this.send('load_history', { peerUserId, beforeSeq, limit })
  }

  markRead(peerUserId: string) {
    this.send('mark_read', { peerUserId })
  }

  disconnect() {
    this.intentionalClose = true
    this.stopPing()
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer)
      this.reconnectTimer = null
    }
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
      this.send('ping', {})
    }, 25000)
  }

  private stopPing() {
    if (this.pingTimer) {
      clearInterval(this.pingTimer)
      this.pingTimer = null
    }
  }

  private scheduleReconnect() {
    if (this.reconnectTimer) return
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = null
      if (!this.intentionalClose) {
        console.log('[WS] reconnecting...')
        this.doConnect()
      }
    }, 3000)
  }
}

export const chatWs = new ChatWsService()
