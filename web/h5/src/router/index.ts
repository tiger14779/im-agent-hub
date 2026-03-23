import { createRouter, createWebHistory } from 'vue-router'
import Shop from '@/views/Shop.vue'
import Chat from '@/views/Chat.vue'
import Login from '@/views/Login.vue'
import ServiceChat from '@/views/ServiceChat.vue'

const routes = [
  { path: '/', component: Shop },
  { path: '/chat', component: Chat },
  { path: '/login', component: Login },
  { path: '/service', component: ServiceChat }
]

export default createRouter({
  history: createWebHistory(),
  routes
})
