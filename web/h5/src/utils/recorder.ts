/** MediaRecorder-based audio recorder utility */
export class AudioRecorder {
  private mediaRecorder: MediaRecorder | null = null
  private chunks: Blob[] = []
  private startTime = 0

  async start(): Promise<void> {
    this.chunks = []
    const stream = await navigator.mediaDevices.getUserMedia({ audio: true })
    this.mediaRecorder = new MediaRecorder(stream)

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
        const blob = new Blob(this.chunks, { type: 'audio/webm' })
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
