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
          <div class="call-actions">
            <button class="call-btn reject" @click="onReject">
              <span class="call-icon">📵</span>
              <span>拒绝</span>
            </button>
            <button class="call-btn accept" @click="onAccept">
              <span class="call-icon">📞</span>
              <span>接听</span>
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
import { ref, computed, watch, onUnmounted } from 'vue'
import { chatWs, type CallInviteData, type CallSignalData } from '@/services/ws'
import request from '@/utils/request'

type CallPhase = 'idle' | 'incoming' | 'outgoing' | 'active'

const props = defineProps<{
  myUserId: string
  myToken: string  // 后端登录 token（用于获取 LiveKit token）
}>()

const phase = ref<CallPhase>('idle')
const callerName = ref('')
const callFromId = ref('') // 来电方 id
const callToId = ref('')   // 呼出方 id
const roomName = ref('')
const livekitUrl = ref('')
const livekitToken = ref('') // 呼出时提前获取的 token
const muted = ref(false)
const isSpeaking = ref(false)
const duration = ref(0) // 通话秒数

let durationTimer: ReturnType<typeof setInterval> | null = null
let lkRoom: any = null // LiveKit Room 实例（动态导入）
let incomingTimer: ReturnType<typeof setTimeout> | null = null // 来电超时自动拒绝
let outgoingTimer: ReturnType<typeof setTimeout> | null = null  // 呼出超时（30s 无人接听）

// ── 格式化通话时长 ─────────────────────────────────────────────────
const formattedDuration = computed(() => {
  const m = Math.floor(duration.value / 60).toString().padStart(2, '0')
  const s = (duration.value % 60).toString().padStart(2, '0')
  return `${m}:${s}`
})

// ── 注册 WS 信令回调 ───────────────────────────────────────────────
chatWs.onCallInvite = (data: CallInviteData) => {
  if (phase.value !== 'idle') {
    // 已有通话，起忙线信号
    chatWs.sendCallBusy(data.fromId)
    return
  }
  callerName.value = data.fromName || data.fromId
  callFromId.value = data.fromId
  roomName.value = data.roomName
  livekitUrl.value = data.livekitUrl
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

// 对方接听（呼出时使用）
chatWs.onCallAccept = async (_data: CallSignalData) => {
  if (phase.value !== 'outgoing') return
  clearOutgoingTimer()
  try {
    phase.value = 'active'
    startDurationTimer()
    await joinLiveKit(livekitToken.value, livekitUrl.value)
  } catch (e) {
    console.error('[VoiceCall] outgoing accept join failed', e)
    endCall()
  }
}

// 对方忙线（呼出时使用）
chatWs.onCallBusy = (_data: CallSignalData) => {
  if (phase.value !== 'outgoing') return
  clearOutgoingTimer()
  endCall()
}

// ── 接听 ──────────────────────────────────────────────────────────
async function onAccept() {
  try {
    // 1. 向后端获取 LiveKit token
    const res = await request.post<unknown, { token: string; wsUrl: string }>(
      `/livekit/token?userId=${encodeURIComponent(props.myUserId)}`,
      { roomName: roomName.value }
    )

    // 2. 通知客服已接听
    chatWs.sendCallAccept(callFromId.value, roomName.value)

    // 3. 连接 LiveKit
    phase.value = 'active'
    startDurationTimer()
    await joinLiveKit(res.token, res.wsUrl)
  } catch (e) {
    console.error('[VoiceCall] accept failed', e)
    endCall()
  }
}

// ── 拒绝 ──────────────────────────────────────────────────────────
function onReject() {
  chatWs.sendCallReject(callFromId.value)
  endCall()
}
// 取消呼出 ─────────────────────────────────────────────────────────────
function onCancel() {
  chatWs.sendCallEnd(callToId.value, roomName.value)
  endCall()
}
// ── 挂断 ──────────────────────────────────────────────────────────
function onHangup() {
  // callFromId: 来电方ID（被叫时设置）；callToId: 呼出对象ID（主叫时设置）
  const peerId = callFromId.value || callToId.value
  chatWs.sendCallEnd(peerId, roomName.value)
  endCall()
}

// ── 静音切换 ──────────────────────────────────────────────────────
async function toggleMute() {
  muted.value = !muted.value
  if (lkRoom) {
    try {
      await lkRoom.localParticipant.setMicrophoneEnabled(!muted.value)
    } catch { /* ignore */ }
  }
}

// ── LiveKit 连接 ──────────────────────────────────────────────────
async function joinLiveKit(token: string, wsUrl: string) {
  try {
    // 动态导入 livekit-client，避免首包体积过大
    const { Room, RoomEvent } = await import('livekit-client')
    lkRoom = new Room({ audioCaptureDefaults: { echoCancellation: true, noiseSuppression: true } })

    lkRoom.on(RoomEvent.Disconnected, () => { endCall() })
    lkRoom.on(RoomEvent.ActiveSpeakersChanged, (speakers: any[]) => {
      isSpeaking.value = speakers.some((s: any) => s.identity !== props.myUserId)
    })

    // Attach incoming audio tracks so remote audio actually plays
    lkRoom.on(RoomEvent.TrackSubscribed, (track: any) => {
      if (track.kind === 'audio') {
        const el = track.attach() as HTMLAudioElement
        el.autoplay = true
        document.body.appendChild(el)
        // Resume AudioContext if suspended (required on mobile/some browsers)
        lkRoom.startAudio().catch(() => {})
      }
    })
    lkRoom.on(RoomEvent.TrackUnsubscribed, (track: any) => {
      track.detach()
    })
    // Retry AudioContext resume if it gets suspended after playback starts
    lkRoom.on(RoomEvent.AudioPlaybackStatusChanged, () => {
      if (!lkRoom.canPlaybackAudio) lkRoom.startAudio().catch(() => {})
    })

    await lkRoom.connect(wsUrl, token)
    await lkRoom.localParticipant.setMicrophoneEnabled(true)
  } catch (e) {
    console.error('[VoiceCall] LiveKit connect error', e)
    endCall()
  }
}

// ── 结束通话清理 ──────────────────────────────────────────────────
function endCall() {
  if (lkRoom) {
    lkRoom.disconnect()
    lkRoom = null
  }
  if (incomingTimer) { clearTimeout(incomingTimer); incomingTimer = null }
  clearOutgoingTimer()
  stopDurationTimer()
  phase.value = 'idle'
  muted.value = false
  isSpeaking.value = false
  duration.value = 0
  callerName.value = ''
  callFromId.value = ''
  callToId.value = ''
  roomName.value = ''
  livekitToken.value = ''
}

// 呼出接口（客服工作台主叫时调用）──────────────────────────────────
function beginOutgoing(peerId: string, peerName: string, token: string, room: string, wsUrl: string) {
  callToId.value = peerId
  callerName.value = peerName
  livekitToken.value = token
  roomName.value = room
  livekitUrl.value = wsUrl
  phase.value = 'outgoing'
  // 30秒无人接听自动取消
  clearOutgoingTimer()
  outgoingTimer = setTimeout(() => {
    if (phase.value === 'outgoing') {
      chatWs.sendCallEnd(callToId.value, roomName.value)
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
