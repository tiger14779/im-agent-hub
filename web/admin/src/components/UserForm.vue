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
      <el-form-item label="昵称" prop="nickname">
        <el-input v-model="form.nickname" placeholder="请输入用户昵称" />
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

interface User {
  id: string
  nickname: string
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
  submit: [data: { nickname: string; serviceUserId: string }]
}>()

const formRef = ref<FormInstance>()
const form = reactive({
  nickname: '',
  serviceUserId: ''
})

// Generate a stable preview ID once per dialog open (not recomputed on every render)
const previewId = ref('')

const rules: FormRules = {
  nickname: [{ required: true, message: '请输入昵称', trigger: 'blur' }],
  serviceUserId: [{ required: true, message: '请选择绑定客服', trigger: 'change' }]
}

watch(() => props.visible, (val) => {
  if (val) {
    if (props.user) {
      form.nickname = props.user.nickname
      form.serviceUserId = props.user.serviceUserId
    } else {
      form.nickname = ''
      form.serviceUserId = ''
      previewId.value = 'user_' + Math.random().toString(36).substring(2, 10)
    }
  }
})

const handleSubmit = async () => {
  if (!formRef.value) return
  await formRef.value.validate((valid) => {
    if (valid) {
      emit('submit', { nickname: form.nickname, serviceUserId: form.serviceUserId })
    }
  })
}
</script>
