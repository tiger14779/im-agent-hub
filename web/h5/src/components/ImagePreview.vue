<template>
  <teleport to="body">
    <transition name="fade">
      <div
        v-if="visible"
        class="preview-mask"
        @click="emit('close')"
        @touchstart="onTouchStart"
        @touchend="onTouchEnd"
      >
        <button class="preview-close" @click.stop="emit('close')">✕</button>
        <img
          :src="src"
          alt="预览"
          class="preview-img"
          @click.stop
        />
      </div>
    </transition>
  </teleport>
</template>

<script setup lang="ts">
let touchStartY = 0

defineProps<{
  src: string
  visible: boolean
}>()

const emit = defineEmits<{ (e: 'close'): void }>()

function onTouchStart(e: TouchEvent) {
  touchStartY = e.touches[0].clientY
}

function onTouchEnd(e: TouchEvent) {
  const dy = Math.abs(e.changedTouches[0].clientY - touchStartY)
  if (dy > 80) emit('close')
}
</script>

<style scoped>
.preview-mask {
  position: fixed;
  inset: 0;
  background: rgba(0, 0, 0, 0.92);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 999;
}

.preview-img {
  max-width: 100%;
  max-height: 90vh;
  object-fit: contain;
  border-radius: 4px;
}

.preview-close {
  position: absolute;
  top: 16px;
  right: 16px;
  font-size: 22px;
  color: #fff;
  background: rgba(0, 0, 0, 0.4);
  width: 36px;
  height: 36px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
}

.fade-enter-active,
.fade-leave-active {
  transition: opacity 0.25s;
}

.fade-enter-from,
.fade-leave-to {
  opacity: 0;
}
</style>
