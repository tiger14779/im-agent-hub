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
              <span class="call-icon"><svg class="call-icon-svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M10.68 13.31a16 16 0 0 0 3.41 2.6l1.27-1.27a2 2 0 0 1 2.11-.45c.907.339 1.85.573 2.81.7A2 2 0 0 1 22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.42 19.42 0 0 1-3.33-2.67m-2.67-3.34a19.79 19.79 0 0 1-3.07-8.63A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72c.127.96.361 1.903.7 2.81a2 2 0 0 1-.45 2.11L8.09 9"/><line x1="23" y1="1" x2="1" y2="23"/></svg></span>
              <span>拒绝</span>
            </button>
            <button class="call-btn accept" @click="onAccept" :disabled="acceptPending">
              <span class="call-icon"><svg class="call-icon-svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07A19.5 19.5 0 0 1 4.69 12 19.79 19.79 0 0 1 1.61 3.37 2 2 0 0 1 3.6 1h3a2 2 0 0 1 2 1.72c.127.96.361 1.903.7 2.81a2 2 0 0 1-.45 2.11L7.91 9a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45c.907.339 1.85.573 2.81.7A2 2 0 0 1 22 16.92z"/></svg></span>
              <span>{{ acceptPending ? '请稍...' : '接听' }}</span>
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
              <span class="call-icon"><svg class="call-icon-svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M10.68 13.31a16 16 0 0 0 3.41 2.6l1.27-1.27a2 2 0 0 1 2.11-.45c.907.339 1.85.573 2.81.7A2 2 0 0 1 22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.42 19.42 0 0 1-3.33-2.67m-2.67-3.34a19.79 19.79 0 0 1-3.07-8.63A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72c.127.96.361 1.903.7 2.81a2 2 0 0 1-.45 2.11L8.09 9"/><line x1="23" y1="1" x2="1" y2="23"/></svg></span>
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
              <span class="call-icon">
                <svg v-if="!muted" class="call-icon-svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 1a3 3 0 0 0-3 3v8a3 3 0 0 0 6 0V4a3 3 0 0 0-3-3z"/><path d="M19 10v2a7 7 0 0 1-14 0v-2"/><line x1="12" y1="19" x2="12" y2="23"/><line x1="8" y1="23" x2="16" y2="23"/></svg>
                <svg v-else class="call-icon-svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="1" y1="1" x2="23" y2="23"/><path d="M9 9v3a3 3 0 0 0 5.12 2.12M15 9.34V4a3 3 0 0 0-5.94-.6"/><path d="M17 16.95A7 7 0 0 1 5 12v-2m14 0v2a7 7 0 0 1-.11 1.23"/><line x1="12" y1="19" x2="12" y2="23"/><line x1="8" y1="23" x2="16" y2="23"/></svg>
              </span>
              <span>{{ muted ? '取消静音' : '静音' }}</span>
            </button>
            <button class="call-btn speaker" :class="{ active: speakerOn }" @click="toggleSpeaker">
              <span class="call-icon">
                <svg v-if="speakerOn" class="call-icon-svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5"/><path d="M15.54 8.46a5 5 0 0 1 0 7.07"/><path d="M19.07 4.93a10 10 0 0 1 0 14.14"/></svg>
                <svg v-else class="call-icon-svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5"/><path d="M15.54 8.46a5 5 0 0 1 0 7.07"/></svg>
              </span>
              <span>{{ speakerOn ? '免提' : '听筒' }}</span>
            </button>
            <button class="call-btn hangup" @click="onHangup">
              <span class="call-icon"><svg class="call-icon-svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M10.68 13.31a16 16 0 0 0 3.41 2.6l1.27-1.27a2 2 0 0 1 2.11-.45c.907.339 1.85.573 2.81.7A2 2 0 0 1 22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.42 19.42 0 0 1-3.33-2.67m-2.67-3.34a19.79 19.79 0 0 1-3.07-8.63A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72c.127.96.361 1.903.7 2.81a2 2 0 0 1-.45 2.11L8.09 9"/><line x1="23" y1="1" x2="1" y2="23"/></svg></span>
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
              <span class="call-icon"><svg class="call-icon-svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M10.68 13.31a16 16 0 0 0 3.41 2.6l1.27-1.27a2 2 0 0 1 2.11-.45c.907.339 1.85.573 2.81.7A2 2 0 0 1 22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.42 19.42 0 0 1-3.33-2.67m-2.67-3.34a19.79 19.79 0 0 1-3.07-8.63A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72c.127.96.361 1.903.7 2.81a2 2 0 0 1-.45 2.11L8.09 9"/><line x1="23" y1="1" x2="1" y2="23"/></svg></span>
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
let playbackGain: GainNode | null = null           // playback volume boost
let speakerDest: MediaStreamAudioDestinationNode | null = null  // loudspeaker routing
let speakerAudio: HTMLAudioElement | null = null    // <audio> element for loudspeaker
let incomingTimer: ReturnType<typeof setTimeout> | null = null
let outgoingTimer: ReturnType<typeof setTimeout> | null = null
let playbackCursor = 0 // scheduled playback cursor - keeps frames contiguous, no overlap/gap
let ringtoneCtx: AudioContext | null = null
let ringtoneTimer: ReturnType<typeof setInterval> | null = null

const speakerOn = ref(true)  // default: loudspeaker ON
// ── 来电提示音 ────────────────────────────────────────────────────
function playRingBeep() {
  try {
    if (!ringtoneCtx || ringtoneCtx.state === 'closed') ringtoneCtx = new AudioContext()
    if (ringtoneCtx.state === 'suspended') ringtoneCtx.resume().catch(() => {})
    const ctx = ringtoneCtx
    const t = ctx.currentTime
    // 两声准调鸣声：440Hz + 880Hz，间隔 0.28s
    ;([440, 880] as const).forEach((freq, i) => {
      const osc = ctx.createOscillator()
      const g = ctx.createGain()
      osc.connect(g)
      g.connect(ctx.destination)
      osc.type = 'sine'
      osc.frequency.value = freq
      const s = t + i * 0.28
      g.gain.setValueAtTime(0, s)
      g.gain.linearRampToValueAtTime(0.28, s + 0.02)
      g.gain.setValueAtTime(0.28, s + 0.15)
      g.gain.linearRampToValueAtTime(0, s + 0.20)
      osc.start(s)
      osc.stop(s + 0.22)
    })
  } catch (_) {}
}

function startRingtone() {
  stopRingtone()
  playRingBeep()
  ringtoneTimer = setInterval(playRingBeep, 2200)
}

function stopRingtone() {
  if (ringtoneTimer) { clearInterval(ringtoneTimer); ringtoneTimer = null }
  if (ringtoneCtx) { ringtoneCtx.close().catch(() => {}); ringtoneCtx = null }
}
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
    // 建立播放增益节点（提升音量）+ 免提路由
    playbackGain = audioCtx.createGain()
    playbackGain.gain.value = 3.0  // 提升 3倍音量
    // MediaStreamDestination 路由：让 <audio> 元素接管播放，强制使用底部扬声器
    speakerDest = audioCtx.createMediaStreamDestination()
    playbackGain.connect(speakerDest)
    speakerAudio = new Audio()
    speakerAudio.srcObject = speakerDest.stream
    speakerAudio.volume = 1.0
    speakerAudio.play().catch(() => {})
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
    // 通过 playbackGain 连接到 speakerDest（免提模式）或直接到 destination（听筒模式）
    if (playbackGain && speakerDest) {
      player.connect(playbackGain)
    } else {
      player.connect(audioCtx.destination)
    }

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
  startRingtone()
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
  stopRingtone()
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
  stopRingtone()
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
// 免提切换
function toggleSpeaker() {
  speakerOn.value = !speakerOn.value
  if (!audioCtx || !playbackGain || !speakerDest) return
  if (speakerOn.value) {
    // 免提：断开听筒，通过 <audio> 元素路由到底部扬声器
    try { playbackGain.disconnect(audioCtx.destination) } catch (_) { /* 未连接则忽略 */ }
    playbackGain.connect(speakerDest)
    if (speakerAudio) speakerAudio.play().catch(() => {})
  } else {
    // 听筒：断开 speakerDest，连接到默认输出（听筒）
    playbackGain.disconnect(speakerDest)
    if (speakerAudio) speakerAudio.pause()
    playbackGain.connect(audioCtx.destination)
  }
}
// ── 静音切换 ──────────────────────────────────────────────────────
function toggleMute() {
  muted.value = !muted.value
  if (gainNode) gainNode.gain.value = muted.value ? 0 : 1
}

// ── 结束通话清理 ──────────────────────────────────────────────────
function endCall() {
  stopRingtone()
  if (audioWs) { audioWs.onclose = null; audioWs.close(); audioWs = null }
  if (captureStream) { captureStream.getTracks().forEach(t => t.stop()); captureStream = null }
  if (speakerAudio) { speakerAudio.pause(); speakerAudio.srcObject = null; speakerAudio = null }
  if (audioCtx) { audioCtx.close(); audioCtx = null }
  gainNode = null
  playbackGain = null
  speakerDest = null
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
.call-btn.speaker .call-icon { background: #374151; }
.call-btn.speaker.active .call-icon { background: #3b82f6; }
.call-icon-svg {
  width: 26px;
  height: 26px;
  display: block;
}

.call-fade-enter-active,
.call-fade-leave-active { transition: opacity 0.25s; }
.call-fade-enter-from,
.call-fade-leave-to { opacity: 0; }
</style>
