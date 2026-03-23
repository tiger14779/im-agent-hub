<template>
  <div class="image-message" @click="previewVisible = true">
    <img
      :src="thumbUrl"
      alt="图片"
      class="msg-image"
      @load="loading = false"
      @error="onImgError"
    />
    <div v-if="loading" class="img-loading">加载中…</div>
  </div>

  <ImagePreview
    v-if="previewVisible"
    :src="fullUrl"
    :visible="previewVisible"
    @close="previewVisible = false"
  />
</template>

<script setup lang="ts">
import { computed, ref } from 'vue'
import type { PictureContent } from '@/types'
import ImagePreview from './ImagePreview.vue'

const props = defineProps<{ content: PictureContent }>()

const previewVisible = ref(false)
const loading = ref(true)

const thumbUrl = computed(
  () =>
    props.content.snapshotPicture?.url ||
    props.content.bigPicture?.url ||
    props.content.sourcePicture?.url ||
    ''
)

const fullUrl = computed(
  () =>
    props.content.bigPicture?.url ||
    props.content.sourcePicture?.url ||
    thumbUrl.value
)

function onImgError() {
  loading.value = false
}
</script>

<style scoped>
.image-message {
  position: relative;
  cursor: pointer;
}

.msg-image {
  max-width: 200px;
  max-height: 200px;
  border-radius: 4px;
  object-fit: cover;
  display: block;
}

.img-loading {
  position: absolute;
  inset: 0;
  background: rgba(255, 255, 255, 0.6);
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 12px;
  color: #666;
}
</style>
