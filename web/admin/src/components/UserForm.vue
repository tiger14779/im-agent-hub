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
        <el-select v-model="form.serviceId" placeholder="请选择客服" style="width: 100%">
          <el-option
            v-for="svc in services"
            :key="svc.id"
            :label="svc.nickname"
            :value="svc.id"
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
import { ref, reactive, watch, computed } from 'vue'
import type { FormInstance, FormRules } from 'element-plus'

interface User {
  id: string
  nickname: string
  serviceId: string
  serviceName: string
  status: number
  createdAt: string
}

interface Service {
  id: string
  nickname: string
}

const props = defineProps<{
  visible: boolean
  user: User | null
  services: Service[]
}>()

const emit = defineEmits<{
  close: []
  submit: [data: { nickname: string; serviceId: string }]
}>()

const formRef = ref<FormInstance>()
const form = reactive({
  nickname: '',
  serviceId: ''
})

const previewId = computed(() => {
  return 'user_' + Math.random().toString(36).substring(2, 10)
})

const rules: FormRules = {
  nickname: [{ required: true, message: '请输入昵称', trigger: 'blur' }],
  serviceId: [{ required: true, message: '请选择绑定客服', trigger: 'change' }]
}

watch(() => props.visible, (val) => {
  if (val) {
    if (props.user) {
      form.nickname = props.user.nickname
      form.serviceId = props.user.serviceId
    } else {
      form.nickname = ''
      form.serviceId = ''
    }
  }
})

const handleSubmit = async () => {
  if (!formRef.value) return
  await formRef.value.validate((valid) => {
    if (valid) {
      emit('submit', { nickname: form.nickname, serviceId: form.serviceId })
    }
  })
}
</script>
