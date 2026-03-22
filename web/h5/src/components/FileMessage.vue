<template>
  <div class="file-message">
    <div class="file-icon">{{ fileIcon }}</div>
    <div class="file-info">
      <p class="file-name">{{ content.fileName ?? '未知文件' }}</p>
      <p class="file-size">{{ formatSize(content.fileSize) }}</p>
    </div>
    <a
      v-if="content.sourceUrl"
      :href="content.sourceUrl"
      target="_blank"
      rel="noopener noreferrer"
      class="file-download"
    >
      ↓
    </a>
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import type { FileContent } from '@/types'

const props = defineProps<{ content: FileContent }>()

const fileIcon = computed(() => {
  const type = (props.content.fileType ?? '').toLowerCase()
  if (type.includes('pdf')) return '📄'
  if (type.includes('image')) return '🖼️'
  if (type.includes('video')) return '🎬'
  if (type.includes('audio')) return '🎵'
  if (type.includes('zip') || type.includes('rar')) return '🗜️'
  if (type.includes('word') || type.includes('doc')) return '📝'
  if (type.includes('sheet') || type.includes('excel') || type.includes('xls')) return '📊'
  return '📎'
})

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
  min-width: 160px;
  max-width: 220px;
}

.file-icon {
  font-size: 28px;
  flex-shrink: 0;
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

.file-download {
  font-size: 18px;
  color: inherit;
  flex-shrink: 0;
  padding: 4px;
}
</style>
