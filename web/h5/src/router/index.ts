import { createRouter, createWebHistory } from 'vue-router'
import Shop from '@/views/Shop.vue'
import Chat from '@/views/Chat.vue'
import Login from '@/views/Login.vue'

const routes = [
  { path: '/', component: Shop },
  { path: '/chat', component: Chat },
  { path: '/login', component: Login }
]

export default createRouter({
  history: createWebHistory(),
  routes
})
