/** MediaRecorder-based audio recorder utility */
export class AudioRecorder {
  private mediaRecorder: MediaRecorder | null = null
  private chunks: Blob[] = []
  private startTime = 0

  /** Pick a supported MIME type for the current browser */
  private getSupportedMimeType(): string | undefined {
    const types = [
      'audio/webm;codecs=opus',
      'audio/webm',
      'audio/mp4',
      'audio/ogg;codecs=opus',
      'audio/aac',
    ]
    return types.find((t) => MediaRecorder.isTypeSupported(t))
  }

  async start(): Promise<void> {
    if (!navigator.mediaDevices?.getUserMedia) {
      throw new Error(
        window.isSecureContext === false
          ? '需要 HTTPS 才能使用麦克风，请用 https:// 访问'
          : '当前浏览器不支持录音功能',
      )
    }

    this.chunks = []
    const stream = await navigator.mediaDevices.getUserMedia({ audio: true })

    const mimeType = this.getSupportedMimeType()
    const options: MediaRecorderOptions = mimeType ? { mimeType } : {}
    this.mediaRecorder = new MediaRecorder(stream, options)

    this.mediaRecorder.ondataavailable = (e) => {
      if (e.data.size > 0) this.chunks.push(e.data)
    }

    this.mediaRecorder.start()
    this.startTime = Date.now()
  }

  stop(): Promise<{ blob: Blob; duration: number }> {
    return new Promise((resolve, reject) => {
      if (!this.mediaRecorder) {
        reject(new Error('Recorder not started'))
        return
      }

      const duration = Math.round((Date.now() - this.startTime) / 1000)

      this.mediaRecorder.onstop = () => {
      const mimeType = this.mediaRecorder?.mimeType || 'audio/webm'
      const blob = new Blob(this.chunks, { type: mimeType })
        // Stop all tracks to release the microphone
        this.mediaRecorder?.stream.getTracks().forEach((t) => t.stop())
        this.mediaRecorder = null
        resolve({ blob, duration })
      }

      this.mediaRecorder.stop()
    })
  }

  cancel(): void {
    if (!this.mediaRecorder) return
    this.mediaRecorder.onstop = null
    this.mediaRecorder.stream.getTracks().forEach((t) => t.stop())
    this.mediaRecorder.stop()
    this.mediaRecorder = null
    this.chunks = []
  }

  isRecording(): boolean {
    return this.mediaRecorder?.state === 'recording'
  }
}
