<template>
  <div class="file-message" :class="{ clickable: isDocx }" @click="onClick">
    <div class="file-icon-box" :style="{ background: iconBg }">
      <span class="file-icon-text" :style="{ color: iconColor }">{{ iconLabel }}</span>
    </div>
    <div class="file-info">
      <p class="file-name">{{ content.fileName ?? '未知文件' }}</p>
      <p class="file-size">{{ formatSize(content.fileSize) }}</p>
    </div>
    <DocxPreview
      v-if="isDocx"
      :visible="showPreview"
      :source-url="content.sourceUrl ?? ''"
      :file-name="content.fileName ?? '文档'"
      @close="showPreview = false"
    />
  </div>
</template>

<script setup lang="ts">
import { computed, ref } from 'vue'
import type { FileContent } from '@/types'
import DocxPreview from './DocxPreview.vue'

const props = defineProps<{ content: FileContent }>()

const showPreview = ref(false)

const fileName = computed(() => (props.content.fileName ?? '').toLowerCase())

const isDocx = computed(() => fileName.value.endsWith('.docx') || fileName.value.endsWith('.doc'))

const fileExt = computed(() => {
  const name = fileName.value
  if (name.endsWith('.doc') || name.endsWith('.docx')) return 'word'
  if (name.endsWith('.xls') || name.endsWith('.xlsx')) return 'excel'
  if (name.endsWith('.ppt') || name.endsWith('.pptx')) return 'ppt'
  if (name.endsWith('.pdf')) return 'pdf'
  if (name.endsWith('.zip') || name.endsWith('.rar') || name.endsWith('.7z')) return 'zip'
  if (name.endsWith('.png') || name.endsWith('.jpg') || name.endsWith('.jpeg') || name.endsWith('.gif') || name.endsWith('.webp')) return 'image'
  if (name.endsWith('.mp4') || name.endsWith('.avi') || name.endsWith('.mov') || name.endsWith('.mkv')) return 'video'
  if (name.endsWith('.mp3') || name.endsWith('.wav') || name.endsWith('.flac')) return 'audio'
  if (name.endsWith('.txt') || name.endsWith('.log') || name.endsWith('.md')) return 'text'
  return 'other'
})

const iconBg = computed(() => {
  const map: Record<string, string> = {
    word: '#2b6cb0', excel: '#217346', ppt: '#d04423', pdf: '#e2574c',
    zip: '#f0ad4e', image: '#8e44ad', video: '#e67e22', audio: '#1abc9c',
    text: '#95a5a6', other: '#bdc3c7'
  }
  return map[fileExt.value] ?? '#bdc3c7'
})

const iconLabel = computed(() => {
  const map: Record<string, string> = {
    word: 'W', excel: 'X', ppt: 'P', pdf: 'PDF',
    zip: 'ZIP', image: 'IMG', video: 'MP4', audio: 'MP3',
    text: 'TXT', other: 'FILE'
  }
  return map[fileExt.value] ?? 'FILE'
})

const iconColor = computed(() => 'white')

function onClick() {
  if (isDocx.value && props.content.sourceUrl) {
    showPreview.value = true
  } else if (props.content.sourceUrl) {
    window.open(props.content.sourceUrl, '_blank')
  }
}

function formatSize(bytes?: number): string {
  if (!bytes) return ''
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
}
</script>

<style scoped>
.file-message {
  display: flex;
  align-items: center;
  gap: 10px;
  min-width: 180px;
  max-width: 240px;
  padding: 6px 4px;
  border-radius: 6px;
  transition: background 0.15s;
}

.file-message.clickable {
  cursor: pointer;
}

.file-message.clickable:hover {
  background: rgba(0, 0, 0, 0.04);
}

.file-icon-box {
  width: 40px;
  height: 40px;
  border-radius: 6px;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}

.file-icon-text {
  font-size: 13px;
  font-weight: 700;
  letter-spacing: 0.5px;
}

.file-info {
  flex: 1;
  min-width: 0;
}

.file-name {
  font-size: 14px;
  color: inherit;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.file-size {
  font-size: 11px;
  color: #888;
  margin-top: 2px;
}
</style>
