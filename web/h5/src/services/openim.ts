/**
 * OpenIM SDK wrapper service.
 *
 * The SDK uses WASM so we import it lazily. If WASM is unavailable the
 * methods reject gracefully so callers can show a user-friendly error.
 */

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type AnyFn = (...args: any[]) => any

interface SDKInstance {
  initSDK: AnyFn
  login: AnyFn
  logout: AnyFn
  createTextMessage: AnyFn
  createImageMessageByURL: AnyFn
  createSoundMessageByURL: AnyFn
  createFileMessageByURL: AnyFn
  sendMessage: AnyFn
  getAdvancedHistoryMessageList: AnyFn
  on: AnyFn
  off: AnyFn
}

class OpenIMService {
  private sdk: SDKInstance | null = null
  private initialized = false

  // Public event callbacks — set by the consumer
  onNewMessage: (message: unknown) => void = () => {}
  onConnected: () => void = () => {}
  onDisconnected: () => void = () => {}

  /** Dynamically load the SDK and initialise it */
  async init(wsUrl: string, apiUrl: string): Promise<void> {
    if (this.initialized) return

    let getSDK: AnyFn
    try {
      const mod = await import('@openim/wasm-client-sdk')
      getSDK = mod.getSDK ?? (mod as unknown as { default: { getSDK: AnyFn } }).default?.getSDK
      if (typeof getSDK !== 'function') throw new Error('getSDK not found in SDK module')
    } catch (err) {
      throw new Error(`无法加载 OpenIM SDK: ${(err as Error).message}`)
    }

    this.sdk = getSDK() as SDKInstance

    const ok = await this.sdk.initSDK(
      {
        platformID: 5, // H5 platform
        apiAddr: apiUrl,
        wsAddr: wsUrl,
        logLevel: 1
      },
      'im-h5'
    )

    if (!ok) throw new Error('OpenIM SDK initSDK 失败')

    // Register global event listeners
    this.sdk.on('OnRecvNewMessage', (data: unknown) => this.onNewMessage(data))
    this.sdk.on('OnConnected', () => this.onConnected())
    this.sdk.on('OnDisconnected', () => this.onDisconnected())

    this.initialized = true
  }

  async login(userId: string, token: string): Promise<void> {
    this.assertReady()
    await this.sdk!.login({ userID: userId, token })
  }

  async logout(): Promise<void> {
    if (!this.sdk || !this.initialized) return
    await this.sdk.logout()
    this.initialized = false
  }

  async sendTextMessage(toUserId: string, text: string): Promise<unknown> {
    this.assertReady()
    const msg = await this.sdk!.createTextMessage(text)
    return this.sdk!.sendMessage({
      recvID: toUserId,
      groupID: '',
      message: msg
    })
  }

  async sendImageMessage(toUserId: string, file: File): Promise<unknown> {
    this.assertReady()
    const url = URL.createObjectURL(file)
    const msg = await this.sdk!.createImageMessageByURL({
      sourcePicture: { url, type: file.type, size: file.size, width: 0, height: 0 },
      bigPicture: { url, type: file.type, size: file.size, width: 0, height: 0 },
      snapshotPicture: { url, type: file.type, size: file.size, width: 0, height: 0 }
    })
    return this.sdk!.sendMessage({ recvID: toUserId, groupID: '', message: msg })
  }

  async sendVoiceMessage(
    toUserId: string,
    audioBlob: Blob,
    duration: number
  ): Promise<unknown> {
    this.assertReady()
    const url = URL.createObjectURL(audioBlob)
    const msg = await this.sdk!.createSoundMessageByURL({
      uuid: crypto.randomUUID(),
      sourceUrl: url,
      dataSize: audioBlob.size,
      duration,
      soundPath: ''
    })
    return this.sdk!.sendMessage({ recvID: toUserId, groupID: '', message: msg })
  }

  async sendFileMessage(toUserId: string, file: File): Promise<unknown> {
    this.assertReady()
    const url = URL.createObjectURL(file)
    const msg = await this.sdk!.createFileMessageByURL({
      filePath: '',
      uuid: crypto.randomUUID(),
      sourceUrl: url,
      fileName: file.name,
      fileSize: file.size,
      fileType: file.type
    })
    return this.sdk!.sendMessage({ recvID: toUserId, groupID: '', message: msg })
  }

  async getHistoryMessages(
    toUserId: string,
    startClientMsgID = '',
    count = 20
  ): Promise<unknown[]> {
    this.assertReady()
    const result = await this.sdk!.getAdvancedHistoryMessageList({
      userID: toUserId,
      groupID: '',
      count,
      startClientMsgID,
      lastMinSeq: 0
    })
    return result?.messageList ?? []
  }

  private assertReady() {
    if (!this.sdk || !this.initialized) {
      throw new Error('OpenIM SDK 尚未初始化，请稍后重试')
    }
  }
}

export const openIMService = new OpenIMService()
