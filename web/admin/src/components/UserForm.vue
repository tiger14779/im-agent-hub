<template>
  <el-dialog
    :model-value="visible"
    :title="user ? '编辑用户' : '创建用户'"
    width="440px"
    @close="emit('close')"
  >
    <el-form :model="form" :rules="rules" ref="formRef" label-width="90px">
      <el-form-item label="用户ID" v-if="!user">
        <el-input :value="previewId" disabled placeholder="系统自动生成" />
      </el-form-item>
      <el-form-item label="头像">
        <div style="display: flex; align-items: center; gap: 12px">
          <el-avatar :size="64" :src="form.avatar || undefined">
            {{ (form.nickname || '?').charAt(0) }}
          </el-avatar>
          <el-upload
            :show-file-list="false"
            :http-request="handleAvatarUpload"
            accept="image/*"
          >
            <el-button size="small">上传头像</el-button>
          </el-upload>
        </div>
      </el-form-item>
      <el-form-item label="昵称" prop="nickname">
        <el-input v-model="form.nickname" placeholder="请输入用户昵称（备注）" />
      </el-form-item>
      <el-form-item label="群内昵称" prop="groupNickname">
        <el-input v-model="form.groupNickname" placeholder="群聊中显示的名称（必填）" />
      </el-form-item>
      <el-form-item label="绑定客服" prop="serviceId">
        <el-select v-model="form.serviceUserId" placeholder="请选择客服" style="width: 100%">
          <el-option
            v-for="svc in services"
            :key="svc.userId"
            :label="svc.nickname"
            :value="svc.userId"
          />
        </el-select>
      </el-form-item>
    </el-form>
    <template #footer>
      <el-button @click="emit('close')">取消</el-button>
      <el-button type="primary" @click="handleSubmit">
        {{ user ? '保存' : '创建' }}
      </el-button>
    </template>
  </el-dialog>
</template>

<script setup lang="ts">
import { ref, reactive, watch } from 'vue'
import type { FormInstance, FormRules } from 'element-plus'
import { ElMessage } from 'element-plus'
import { uploadFile } from '@/services/api'

interface User {
  id: string
  nickname: string
  avatar?: string
  serviceUserId: string
  serviceName: string
  status: number
  createdAt: string
}

interface Service {
  userId: string
  nickname: string
}

const props = defineProps<{
  visible: boolean
  user: User | null
  services: Service[]
}>()

const emit = defineEmits<{
  close: []
  submit: [data: { nickname: string; groupNickname: string; serviceUserId: string; avatar?: string }]
}>()

const formRef = ref<FormInstance>()
const form = reactive({
  nickname: '',
  groupNickname: '',
  serviceUserId: '',
  avatar: ''
})

// Generate a stable preview ID once per dialog open (not recomputed on every render)
const previewId = ref('')

const rules: FormRules = {
  nickname: [{ required: true, message: '请输入昵称', trigger: 'blur' }],
  groupNickname: [{ required: true, message: '请输入群内昵称', trigger: 'blur' }],
  serviceUserId: [{ required: true, message: '请选择绑定客服', trigger: 'change' }]
}

watch(() => props.visible, (val) => {
  if (val) {
    if (props.user) {
      form.nickname = props.user.nickname
      form.groupNickname = (props.user as unknown as { groupNickname?: string }).groupNickname || ''
      form.serviceUserId = props.user.serviceUserId
      form.avatar = props.user.avatar || ''
    } else {
      form.nickname = ''
      form.groupNickname = ''
      form.serviceUserId = ''
      form.avatar = ''
      previewId.value = 'user_' + Math.random().toString(36).substring(2, 10)
    }
  }
})

const handleAvatarUpload = async (options: { file: File }) => {
  try {
    const res = await uploadFile(options.file)
    const url = (res.data as { url: string })?.url || ''
    if (url) {
      form.avatar = url
      ElMessage.success('头像上传成功')
    }
  } catch {
    ElMessage.error('头像上传失败')
  }
}

const handleSubmit = async () => {
  if (!formRef.value) return
  await formRef.value.validate((valid) => {
    if (valid) {
      emit('submit', {
        nickname: form.nickname,
        groupNickname: form.groupNickname,
        serviceUserId: form.serviceUserId,
        avatar: form.avatar || undefined
      })
    }
  })
}
</script>
