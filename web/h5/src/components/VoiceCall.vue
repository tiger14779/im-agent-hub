<template>
  <!-- 来电弹窗 -->
  <teleport to="body">
    <transition name="call-fade">
      <!-- 来电提醒 -->
      <div v-if="phase === 'incoming'" class="call-mask">
        <div class="call-panel">
          <div class="call-avatar">{{ callerName.charAt(0) }}</div>
          <div class="call-name">{{ callerName }}</div>
          <div class="call-hint">邀请你语音通话</div>
          <div v-if="callError" class="call-error-msg">{{ callError }}</div>
          <div class="call-actions">
            <button class="call-btn reject" @click="onReject">
              <span class="call-icon">📵</span>
              <span>拒绝</span>
            </button>
            <button class="call-btn accept" @click="onAccept" :disabled="acceptPending">
              <span class="call-icon">📞</span>
              <span>{{ acceptPending ? '请稿...' : '接听' }}</span>
            </button>
          </div>
        </div>
      </div>

      <!-- 连接中 -->
      <div v-else-if="phase === 'connecting'" class="call-mask">
        <div class="call-panel">
          <div class="call-avatar">{{ callerName.charAt(0) }}</div>
          <div class="call-name">{{ callerName }}</div>
          <div class="call-hint">正在连接...</div>
          <div v-if="callError" class="call-error-msg">{{ callError }}</div>
          <div class="call-actions">
            <button class="call-btn hangup" @click="onHangup">
              <span class="call-icon">📵</span>
              <span>挂断</span>
            </button>
          </div>
        </div>
      </div>

      <!-- 通话中 -->
      <div v-else-if="phase === 'active'" class="call-mask call-active">
        <div class="call-panel">
          <div class="call-avatar" :class="{ speaking: isSpeaking }">{{ callerName.charAt(0) }}</div>
          <div class="call-name">{{ callerName }}</div>
          <div class="call-timer">{{ formattedDuration }}</div>
          <div class="call-actions">
            <button class="call-btn mute" :class="{ active: muted }" @click="toggleMute">
              <span class="call-icon">{{ muted ? '🔇' : '🎤' }}</span>
              <span>{{ muted ? '取消静音' : '静音' }}</span>
            </button>
            <button class="call-btn hangup" @click="onHangup">
              <span class="call-icon">📵</span>
              <span>挂断</span>
            </button>
          </div>
        </div>
      </div>

      <!-- 呼出中（客服工作台主叫） -->
      <div v-else-if="phase === 'outgoing'" class="call-mask">
        <div class="call-panel">
          <div class="call-avatar">{{ callerName.charAt(0) }}</div>
          <div class="call-name">{{ callerName }}</div>
          <div class="call-hint">等待对方接听...</div>
          <div class="call-actions">
            <button class="call-btn hangup" @click="onCancel">
              <span class="call-icon">📵</span>
              <span>取消</span>
            </button>
          </div>
        </div>
      </div>
    </transition>
  </teleport>
</template>

<script setup lang="ts">
import { ref, computed, onUnmounted } from 'vue'
import { chatWs, type CallInviteData, type CallSignalData, type CallAudioReadyData } from '@/services/ws'

type CallPhase = 'idle' | 'incoming' | 'connecting' | 'outgoing' | 'active'

const props = defineProps<{
  myUserId: string
}>()

const phase = ref<CallPhase>('idle')
const callerName = ref('')
const callFromId = ref('') // 来电方 id
const callToId = ref('')   // 呼出方 id
const muted = ref(false)
const isSpeaking = ref(false)
const duration = ref(0) // 通话秒数
const callError = ref('') // 连接错误提示
const acceptPending = ref(false) // 接听按钮处理中

let durationTimer: ReturnType<typeof setInterval> | null = null
let audioCtx: AudioContext | null = null
let audioWs: WebSocket | null = null
let captureStream: MediaStream | null = null
let gainNode: GainNode | null = null
let incomingTimer: ReturnType<typeof setTimeout> | null = null
let outgoingTimer: ReturnType<typeof setTimeout> | null = null
let playbackCursor = 0 // scheduled playback cursor - keeps frames contiguous, no overlap/gap

// ── 格式化通话时长 ─────────────────────────────────────────────────
const formattedDuration = computed(() => {
  const m = Math.floor(duration.value / 60).toString().padStart(2, '0')
  const s = (duration.value % 60).toString().padStart(2, '0')
  return `${m}:${s}`
})

// ── WebSocket PCM 音频中继 ──────────────────────────────────────────
// 关键设计：
//   1. 音频管道（captureStream → scriptNode → WS）在 onopen 里构建
//   2. phase = 'active' 也在 onopen 里设置
//   3. WS 连接失败（onclose 在 connecting 阶段）只显示错误，绝不调 endCall
async function connectAudioWs(wsBase: string, roomId: string, token: string) {
  const proto = location.protocol === 'https:' ? 'wss:' : 'ws:'
  const base = wsBase || `${proto}//${location.host}/api/call/audio`
  const url = `${base}?roomId=${encodeURIComponent(roomId)}&token=${encodeURIComponent(token)}`
  console.log('[VoiceCall] audio WS url:', url)

  if (!audioCtx) audioCtx = new AudioContext({ sampleRate: 48000 })
  if (audioCtx.state === 'suspended') await audioCtx.resume().catch(() => {})
  console.log('[VoiceCall] AudioContext actual sampleRate:', audioCtx.sampleRate)

  // 预先确保 captureStream 可用（onAccept 里应已获取）
  if (!captureStream) {
    console.warn('[VoiceCall] captureStream not pre-acquired, requesting now')
    try {
      captureStream = await navigator.mediaDevices.getUserMedia({ audio: { channelCount: 1 } })
    } catch (err) {
      const msg = err instanceof Error ? (err.name + ': ' + err.message) : String(err)
      console.error('[VoiceCall] getUserMedia failed:', msg)
      callError.value = `麦克风无法使用：${msg}`
      return // phase 保持 connecting，显示错误
    }
  }

  audioWs = new WebSocket(url)
  audioWs.binaryType = 'arraybuffer'

  // ── WS 成功连接：此时才构建音频管道并切换到 active ──
  audioWs.onopen = () => {
    console.log('[VoiceCall] audio WS connected, building pipeline')
    if (!audioCtx || !captureStream) {
      callError.value = '内部错误：音频资源丢失'
      if (audioWs) { audioWs.onclose = null; audioWs.close(); audioWs = null }
      return
    }
    if (audioCtx.state === 'suspended') audioCtx.resume().catch(() => {})

    const source = audioCtx.createMediaStreamSource(captureStream)
    gainNode = audioCtx.createGain()
    gainNode.gain.value = muted.value ? 0 : 1
    const scriptNode = audioCtx.createScriptProcessor(1024, 1, 1)
    scriptNode.onaudioprocess = (e) => {
      if (!audioWs || audioWs.readyState !== WebSocket.OPEN) return
      const float32 = e.inputBuffer.getChannelData(0)
      const int16 = new Int16Array(float32.length)
      for (let i = 0; i < float32.length; i++) {
        int16[i] = Math.max(-32768, Math.min(32767, Math.round(float32[i] * 32767)))
      }
      audioWs.send(int16.buffer)
    }
    source.connect(gainNode)
    gainNode.connect(scriptNode)
    scriptNode.connect(audioCtx.destination)

    console.log('[VoiceCall] pipeline ready, phase -> active')
    playbackCursor = 0
    phase.value = 'active'
    startDurationTimer()
  }

  // ── 接收对端音频 ──
  audioWs.onmessage = (ev) => {
    if (!audioCtx || !(ev.data instanceof ArrayBuffer)) return
    if (audioCtx.state === 'suspended') audioCtx.resume().catch(() => {})
    const int16 = new Int16Array(ev.data)
    const float32 = new Float32Array(int16.length)
    let sumSq = 0
    for (let i = 0; i < int16.length; i++) {
      float32[i] = int16[i] / 32768
      sumSq += float32[i] * float32[i]
    }
    isSpeaking.value = Math.sqrt(sumSq / int16.length) > 0.015
    const buf = audioCtx.createBuffer(1, float32.length, 48000)
    buf.getChannelData(0).set(float32)
    const player = audioCtx.createBufferSource()
    player.buffer = buf
    player.connect(audioCtx.destination)

    // 调度播放：维护时间游标，让每个帧严格接续，消除报文重叠戚斩断
    const now = audioCtx.currentTime
    if (playbackCursor < now + 0.02) {
      // 游标落后超过 20ms（初始化或长时间延迟后），重置并加 60ms 抖动缓冲
      playbackCursor = now + 0.06
    }
    player.start(playbackCursor)
    playbackCursor += buf.duration
  }

  // ── WS 关闭：active 才 endCall；connecting 只显示错误，窗口不关 ──
  audioWs.onclose = (ev) => {
    console.error('[VoiceCall] audio WS closed', ev.code, ev.reason)
    if (phase.value === 'active') {
      endCall()
    } else if (phase.value === 'connecting') {
      callError.value = `音频连接失败 (code ${ev.code}) — 请检查网络后重试`
      audioWs = null
      // 不调 endCall，保持 connecting 界面显示错误
    }
  }

  audioWs.onerror = () => {
    console.error('[VoiceCall] audio WS error')
    // onclose 紧接着会触发，错误提示在那里设置
  }
}

// ── 注册 WS 信令回调 ───────────────────────────────────────────────
chatWs.onCallInvite = (data: CallInviteData) => {
  if (phase.value !== 'idle') {
    chatWs.sendCallBusy(data.fromId)
    return
  }
  callerName.value = data.fromName || data.fromId
  callFromId.value = data.fromId
  phase.value = 'incoming'
  // 30 秒无操作自动拒绝
  incomingTimer = setTimeout(() => {
    if (phase.value === 'incoming') {
      chatWs.sendCallReject(callFromId.value)
      endCall()
    }
  }, 30000)
}

chatWs.onCallEnd = (_data: CallSignalData) => {
  endCall()
}

chatWs.onCallReject = (_data: CallSignalData) => {
  endCall()
}

chatWs.onCallBusy = (_data: CallSignalData) => {
  if (phase.value !== 'outgoing') return
  clearOutgoingTimer()
  endCall()
}

// 服务端下发音频中继凭证（主叫和被叫都会收到）
chatWs.onCallAudioReady = (data: CallAudioReadyData) => {
  if (phase.value !== 'outgoing' && phase.value !== 'incoming' && phase.value !== 'connecting') return
  // phase → active 由 connectAudioWs 内部在音频图就绪后设置
  connectAudioWs(data.wsBase, data.roomId, data.token)
}

// 对方接听（呼出时服务端会同时下发 call_accept + call_audio_ready）
chatWs.onCallAccept = (_data: CallSignalData) => {
  // call_audio_ready 会触发真正的启动；此处仅做日志
  console.log('[VoiceCall] call_accept received, waiting for call_audio_ready')
}

// ── 接听 ──────────────────────────────────────────────────────────
async function onAccept() {
  if (incomingTimer) { clearTimeout(incomingTimer); incomingTimer = null }
  callError.value = ''
  acceptPending.value = true

  // 在用户手势上下文中立即创建 AudioContext
  if (!audioCtx) audioCtx = new AudioContext({ sampleRate: 48000 })

  // 在用户点击时就申请麦克风权限；如果失败则留在 incoming 界面显示错误
  if (!captureStream) {
    try {
      captureStream = await navigator.mediaDevices.getUserMedia({ audio: { channelCount: 1 } })
    } catch (err) {
      const msg = err instanceof Error ? (err.name + ': ' + err.message) : String(err)
      callError.value = `麦克风无法使用：${msg}\n(若 PC 客户端占用了麦克风，请先关闭它)`
      acceptPending.value = false
      return // 不进入 connecting，保持 incoming 状态让用户看到错误
    }
  }

  acceptPending.value = false
  phase.value = 'connecting'
  chatWs.sendCallAccept(callFromId.value)
}

// ── 拒绝 ──────────────────────────────────────────────────────────
function onReject() {
  chatWs.sendCallReject(callFromId.value)
  endCall()
}

// 取消呼出
function onCancel() {
  chatWs.sendCallEnd(callToId.value)
  endCall()
}

// ── 挂断 ──────────────────────────────────────────────────────────
function onHangup() {
  const peerId = callFromId.value || callToId.value
  chatWs.sendCallEnd(peerId)
  endCall()
}

// ── 静音切换 ──────────────────────────────────────────────────────
function toggleMute() {
  muted.value = !muted.value
  if (gainNode) gainNode.gain.value = muted.value ? 0 : 1
}

// ── 结束通话清理 ──────────────────────────────────────────────────
function endCall() {
  if (audioWs) { audioWs.onclose = null; audioWs.close(); audioWs = null }
  if (captureStream) { captureStream.getTracks().forEach(t => t.stop()); captureStream = null }
  if (audioCtx) { audioCtx.close(); audioCtx = null }
  gainNode = null
  if (incomingTimer) { clearTimeout(incomingTimer); incomingTimer = null }
  clearOutgoingTimer()
  stopDurationTimer()
  callError.value = ''
  acceptPending.value = false
  phase.value = 'idle'
  muted.value = false
  isSpeaking.value = false
  duration.value = 0
  callerName.value = ''
  callFromId.value = ''
  callToId.value = ''
}

// 呼出接口（H5 用户主动发起语音通话时调用）
function beginOutgoing(peerId: string, peerName: string) {
  callError.value = ''
  callToId.value = peerId
  callerName.value = peerName
  // 在用户手势上下文中立即创建 AudioContext
  if (!audioCtx) {
    audioCtx = new AudioContext({ sampleRate: 48000 })
  }
  phase.value = 'outgoing'
  // 发出邀请
  chatWs.sendCallInvite(peerId, props.myUserId)
  // 30 秒无人接听自动取消
  clearOutgoingTimer()
  outgoingTimer = setTimeout(() => {
    if (phase.value === 'outgoing') {
      chatWs.sendCallEnd(callToId.value)
      endCall()
    }
  }, 30000)
}

defineExpose({ beginOutgoing })

function startDurationTimer() {
  stopDurationTimer()
  durationTimer = setInterval(() => { duration.value++ }, 1000)
}

function stopDurationTimer() {
  if (durationTimer) { clearInterval(durationTimer); durationTimer = null }
}

function clearOutgoingTimer() {
  if (outgoingTimer) { clearTimeout(outgoingTimer); outgoingTimer = null }
}

onUnmounted(() => { endCall() })
</script>

<style scoped>
.call-mask {
  position: fixed;
  inset: 0;
  background: rgba(0, 0, 0, 0.65);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 9999;
}
.call-panel {
  background: #1c1c2e;
  border-radius: 20px;
  padding: 32px 40px;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 12px;
  min-width: 280px;
  box-shadow: 0 8px 40px rgba(0,0,0,0.5);
}
.call-avatar {
  width: 80px;
  height: 80px;
  border-radius: 50%;
  background: linear-gradient(135deg, #667eea, #764ba2);
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 32px;
  color: #fff;
  font-weight: bold;
  transition: box-shadow 0.3s;
}
.call-avatar.speaking {
  box-shadow: 0 0 0 6px rgba(102, 126, 234, 0.5);
}
.call-name {
  color: #fff;
  font-size: 20px;
  font-weight: 600;
}
.call-hint {
  color: #aaa;
  font-size: 14px;
}
.call-error-msg {
  color: #f87171;
  font-size: 12px;
  margin-top: 6px;
  padding: 4px 8px;
  background: rgba(248,113,113,0.1);
  border-radius: 4px;
  word-break: break-all;
}
.call-timer {
  color: #7ecdff;
  font-size: 18px;
  font-variant-numeric: tabular-nums;
  letter-spacing: 2px;
}
.call-actions {
  display: flex;
  gap: 24px;
  margin-top: 8px;
}
.call-btn {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 6px;
  background: none;
  border: none;
  cursor: pointer;
  color: #fff;
  font-size: 12px;
}
.call-icon {
  width: 56px;
  height: 56px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 24px;
}
.call-btn.accept .call-icon { background: #22c55e; }
.call-btn.reject .call-icon, .call-btn.hangup .call-icon { background: #ef4444; }
.call-btn.mute .call-icon { background: #374151; }
.call-btn.mute.active .call-icon { background: #f59e0b; }

.call-fade-enter-active,
.call-fade-leave-active { transition: opacity 0.25s; }
.call-fade-enter-from,
.call-fade-leave-to { opacity: 0; }
</style>
