/**
 * OpenIM SDK wrapper service.
 *
 * The SDK uses WASM so we import it lazily. If WASM is unavailable the
 * methods reject gracefully so callers can show a user-friendly error.
 */

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type AnyFn = (...args: any[]) => any

interface SDKInstance {
  login: AnyFn
  logout: AnyFn
  createTextMessage: AnyFn
  createImageMessageByURL: AnyFn
  createSoundMessageByURL: AnyFn
  createFileMessageByURL: AnyFn
  sendMessage: AnyFn
  sendMessageNotOss: AnyFn
  getAdvancedHistoryMessageList: AnyFn
  getConversationIDBySessionType: AnyFn
  on: AnyFn
  off: AnyFn
}

/** Portable UUID generator — falls back to a random hex string when crypto.randomUUID is unavailable */
function uuid(): string {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
    return crypto.randomUUID()
  }
  return Array.from({ length: 16 }, () =>
    Math.floor(Math.random() * 256).toString(16).padStart(2, '0')
  ).join('')
}

class OpenIMService {
  private sdk: SDKInstance | null = null
  private wsUrl = ''
  private apiUrl = ''
  private initialized = false
  private currentUserId = ''

  /** Resolves when SDK connection is established after login */
  private connectedResolve: (() => void) | null = null
  private connectedPromise: Promise<void> | null = null

  /** Cached credentials for auto-reconnect on kick */
  private lastToken = ''

  // Public event callbacks — set by the consumer
  onNewMessage: (message: unknown) => void = () => {}
  onConnected: () => void = () => {}
  onDisconnected: () => void = () => {}
  onKickedOffline: () => void = () => {}

  private ensureSDKResultOk(result: unknown, action: string): unknown {
    const payload = result as { errCode?: number; errMsg?: string; data?: unknown } | null
    if (payload && typeof payload.errCode === 'number' && payload.errCode !== 0) {
      throw new Error(payload.errMsg || `${action} 失败: ${payload.errCode}`)
    }
    return payload?.data ?? result
  }

  /** Dynamically load the SDK and initialise it */
  async init(wsUrl: string, apiUrl: string): Promise<void> {
    this.wsUrl = wsUrl
    this.apiUrl = apiUrl
    if (this.sdk) return

    let getSDK: AnyFn
    try {
      const mod = await import('@openim/wasm-client-sdk')
      getSDK = mod.getSDK ?? (mod as unknown as { default: { getSDK: AnyFn } }).default?.getSDK
      if (typeof getSDK !== 'function') throw new Error('getSDK not found in SDK module')
    } catch (err) {
      throw new Error(`无法加载 OpenIM SDK: ${(err as Error).message}`)
    }

    this.sdk = getSDK() as SDKInstance

    // Register global event listeners
    this.sdk.on('OnRecvNewMessage', (data: unknown) => this.onNewMessage(data))
    this.sdk.on('OnRecvNewMessages', (payload: { data?: unknown[] }) => {
      const list = payload?.data ?? []
      for (const item of list) this.onNewMessage(item)
    })
    this.sdk.on('OnConnectSuccess', () => {
      this.connectedResolve?.()
      this.connectedResolve = null
      this.onConnected()
    })
    this.sdk.on('OnConnectFailed', () => this.onDisconnected())
    this.sdk.on('OnUserTokenInvalid', () => {
      console.warn('[OpenIM] token invalid, resetting state')
      this.initialized = false
      this.currentUserId = ''
      this.onDisconnected()
    })
    this.sdk.on('OnKickedOffline', () => {
      console.warn('[OpenIM] kicked offline, attempting auto-reconnect')
      this.initialized = false
      const uid = this.currentUserId
      const tok = this.lastToken
      this.currentUserId = ''
      this.onKickedOffline()
      // Auto-reconnect with cached credentials
      if (uid && tok) {
        this.login(uid, tok).catch((err) => {
          console.error('[OpenIM] auto-reconnect failed', err)
          this.onDisconnected()
        })
      }
    })
  }

  async login(userId: string, token: string): Promise<void> {
    this.assertSDKLoaded()

    // If already logged in with the same user, skip
    if (this.initialized && this.currentUserId === userId) {
      return
    }

    // If logged in with a different user, logout first
    if (this.initialized && this.currentUserId && this.currentUserId !== userId) {
      await this.logout()
    }

    // Create connection-ready promise before login so the listener is in place
    this.connectedPromise = new Promise<void>((resolve) => {
      this.connectedResolve = resolve
    })

    const result = await this.sdk!.login({
      userID: userId,
      token,
      platformID: 5,
      apiAddr: this.apiUrl,
      wsAddr: this.wsUrl,
      logLevel: 1
    })

    if (result && typeof result.errCode === 'number' && result.errCode !== 0) {
      this.connectedPromise = null
      this.connectedResolve = null
      throw new Error(result.errMsg || `OpenIM 登录失败: ${result.errCode}`)
    }

    this.initialized = true
    this.currentUserId = userId
    this.lastToken = token
  }

  /** Wait until the SDK WebSocket connection is ready */
  async waitForConnection(timeoutMs = 10000): Promise<void> {
    if (!this.connectedPromise) return
    const timeout = new Promise<void>((_, reject) =>
      setTimeout(() => reject(new Error('OpenIM 连接超时')), timeoutMs)
    )
    await Promise.race([this.connectedPromise, timeout])
  }

  async logout(): Promise<void> {
    if (!this.sdk || !this.initialized) return
    try {
      await this.sdk.logout()
    } catch {
      // ignore logout errors
    }
    this.initialized = false
    this.currentUserId = ''
    this.lastToken = ''
    this.connectedPromise = null
    this.connectedResolve = null
  }

  async sendTextMessage(toUserId: string, text: string): Promise<unknown> {
    this.assertReady()
    const msgResp = await this.sdk!.createTextMessage(text)
    const message = this.ensureSDKResultOk(msgResp, '创建文本消息')
    const sendResp = await this.sdk!.sendMessage({
      recvID: toUserId,
      groupID: '',
      message
    })
    return this.ensureSDKResultOk(sendResp, '发送文本消息')
  }

  /** Upload a file via our backend proxy to avoid unresolvable MinIO hostname */
  private async uploadFileToServer(file: File | Blob, fileName: string): Promise<string> {
    const f = file instanceof File ? file : new File([file], fileName, { type: file.type })
    console.log('[OpenIM] uploading file via backend', { name: fileName, size: f.size, type: f.type })
    const formData = new FormData()
    formData.append('file', f, fileName)
    const resp = await fetch('/api/upload', { method: 'POST', body: formData })
    if (!resp.ok) {
      const text = await resp.text()
      throw new Error(`文件上传失败: HTTP ${resp.status} ${text}`)
    }
    const json = await resp.json()
    const url = json?.data?.url
    if (!url || typeof url !== 'string') {
      console.error('[OpenIM] upload response:', json)
      throw new Error('文件上传失败：未返回有效URL')
    }
    console.log('[OpenIM] upload success', { url })
    return url
  }

  async sendImageMessage(toUserId: string, file: File): Promise<unknown> {
    this.assertReady()
    // Upload first, get real URL
    const url = await this.uploadFileToServer(file, file.name)
    const picBase = { uuid: uuid(), type: file.type, size: file.size, width: 0, height: 0, url }
    const msgResp = await this.sdk!.createImageMessageByURL({
      sourcePicture: picBase,
      bigPicture: picBase,
      snapshotPicture: picBase,
      sourcePath: ''
    })
    const message = this.ensureSDKResultOk(msgResp, '创建图片消息')
    // Use sendMessageNotOss since file is already uploaded
    const sendFn = this.sdk!.sendMessageNotOss ?? this.sdk!.sendMessage
    const sendResp = await sendFn.call(this.sdk, { recvID: toUserId, groupID: '', message })
    return this.ensureSDKResultOk(sendResp, '发送图片消息')
  }

  async sendVoiceMessage(
    toUserId: string,
    audioBlob: Blob,
    duration: number
  ): Promise<unknown> {
    this.assertReady()
    const url = await this.uploadFileToServer(audioBlob, 'voice.webm')
    const msgResp = await this.sdk!.createSoundMessageByURL({
      uuid: uuid(),
      sourceUrl: url,
      dataSize: audioBlob.size,
      duration,
      soundPath: ''
    })
    const message = this.ensureSDKResultOk(msgResp, '创建语音消息')
    const sendFn = this.sdk!.sendMessageNotOss ?? this.sdk!.sendMessage
    const sendResp = await sendFn.call(this.sdk, { recvID: toUserId, groupID: '', message })
    return this.ensureSDKResultOk(sendResp, '发送语音消息')
  }

  async sendFileMessage(toUserId: string, file: File): Promise<unknown> {
    this.assertReady()
    const url = await this.uploadFileToServer(file, file.name)
    const msgResp = await this.sdk!.createFileMessageByURL({
      filePath: '',
      uuid: uuid(),
      sourceUrl: url,
      fileName: file.name,
      fileSize: file.size,
      fileType: file.type
    })
    const message = this.ensureSDKResultOk(msgResp, '创建文件消息')
    const sendFn = this.sdk!.sendMessageNotOss ?? this.sdk!.sendMessage
    const sendResp = await sendFn.call(this.sdk, { recvID: toUserId, groupID: '', message })
    return this.ensureSDKResultOk(sendResp, '发送文件消息')
  }

  /** Get the conversationID for a single chat with another user */
  async getConversationID(otherUserId: string): Promise<string> {
    this.assertReady()
    try {
      const resp = await this.sdk!.getConversationIDBySessionType({
        sourceID: otherUserId,
        sessionType: 1 // single chat
      })
      const id = resp?.data ?? resp ?? ''
      if (id && typeof id === 'string') return id
    } catch (err) {
      console.warn('[OpenIM] getConversationIDBySessionType failed, using fallback', err)
    }
    // Fallback: construct conversation ID manually (OpenIM single chat pattern)
    const myId = this.currentUserId
    return myId < otherUserId
      ? `si_${myId}_${otherUserId}`
      : `si_${otherUserId}_${myId}`
  }

  async getHistoryMessages(
    conversationID: string,
    startClientMsgID = '',
    count = 20
  ): Promise<unknown[]> {
    this.assertReady()
    const result = await this.sdk!.getAdvancedHistoryMessageList({
      conversationID,
      startClientMsgID,
      count,
      viewType: 0 // ViewType.History
    })
    return result?.data?.messageList ?? result?.messageList ?? []
  }

  private assertSDKLoaded() {
    if (!this.sdk) {
      throw new Error('OpenIM SDK 未加载，请稍后重试')
    }
    if (!this.wsUrl || !this.apiUrl) {
      throw new Error('OpenIM 地址缺失，请重新登录')
    }
  }

  private assertReady() {
    if (!this.sdk || !this.initialized) {
      throw new Error('OpenIM SDK 尚未初始化，请稍后重试')
    }
  }
}

export const openIMService = new OpenIMService()
